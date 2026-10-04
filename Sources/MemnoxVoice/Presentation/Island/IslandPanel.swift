import AppKit
import MetalKit
import MemnoxVoiceCore
import SwiftUI

/// The face Memnox puts on screen: an island that grows out of the notch, holding the orb, the
/// sessions, the voice's caption and, for a held call, the answer buttons. It never takes focus
/// from the editor underneath, and lets every click outside its own shape through.
final class IslandPanel: NSPanel, Face {
    private let model: IslandModel
    private let orb: MTKView
    private let renderer: OrbRenderer?
    private var poll: Timer?
    private var hoverSince: Date?
    private var lastActivity = Date()
    private var lastMouse = NSPoint.zero
    private var refresher: Task<Void, Never>?
    private var finishing: Task<Void, Never>?
    private var clicks: EventMonitor?
    private var list: () async -> [SessionCard] = { [] }
    private var view: (String) async -> SessionView? = { _ in nil }
    /// Where the history is kept between launches; none in the preview, which keeps it in memory only.
    private var historyFile: HistoryFile?
    /// The history at the left of the screen, opened from the left of the notch.
    private var side: SidePanel?
    /// Whether the pointer resting on the notch is on its left, where the orb sits, which opens the side panel instead.
    private var restingOnLeft = false

    private enum Layout {
        /// The orb view's size before the island lays it out at its real size.
        static let initialOrbSide: CGFloat = 64
        /// Levels above the main menu bar's, so the island covers the bar either side of the notch.
        static let levelAboveMenuBar = 3
        /// How far past its drawn edge the island still counts as under the pointer.
        static let pointerSlop: CGFloat = 6
    }

    private enum Timing {
        /// The orb draws and the pointer is polled once a frame at this rate.
        static let framesPerSecond = 60
        static let hoverResponse = 0.28
        static let hoverDamping = 0.6
        /// Sessions are read this often while the island is open, and less often while it only shows dots.
        static let openRefresh: TimeInterval = 2
        static let restingRefresh: TimeInterval = 5
        static let nanosecondsPerSecond: TimeInterval = 1_000_000_000
    }

    /// The agent kind Memnox's own operator reports under.
    private static let operatorKindPrefix = "memnox"

    init(loudness: @escaping () -> Float) {
        let model = IslandModel()
        self.model = model
        orb = MTKView(frame: NSRect(x: 0, y: 0, width: Layout.initialOrbSide, height: Layout.initialOrbSide), device: MTLCreateSystemDefaultDevice())
        orb.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        orb.preferredFramesPerSecond = Timing.framesPerSecond
        orb.wantsLayer = true
        orb.layer?.isOpaque = false
        renderer = OrbRenderer(view: orb)
        renderer?.loudness = loudness
        orb.delegate = renderer
        super.init(
            contentRect: NSRect(origin: .zero, size: Island.window),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Above the menu bar, since the island has to cover the notch and the bar either side of it.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + Layout.levelAboveMenuBar)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        model.focus = { [weak self] session in self?.focus(session) }
        model.toggleSide = { [weak self] in self?.side?.toggle() }
        model.showExchange = { [weak self] id in self?.showExchange(id) }
        // Takes the first click, since the island never becomes the active window and would otherwise swallow it.
        let hosting = FirstClickHosting(rootView: IslandView(model: model, orb: orb, loudness: loudness))
        // The window keeps its own size, since the island grows inside it rather than with it.
        hosting.sizingOptions = []
        contentView = hosting
        place()
        orderFrontRegardless()
        side = SidePanel(model: model)
        // Polled rather than tracked, because the window is larger than the island and must let clicks past its shape.
        poll = Timer.scheduledTimer(withTimeInterval: 1.0 / Double(Timing.framesPerSecond), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.follow() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.place() }
        }
        // A click anywhere else puts the open island away; clicks on the island itself are not global.
        clicks = EventMonitor.global([.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeIsland() }
        }
    }

    override var canBecomeKey: Bool { false }

    /// Not pushed below the menu bar, which is exactly where the island lives.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    /// The answer buttons and a tap on the resting orb, wired by the app delegate.
    @MainActor func wire(answer: @escaping (HeldCard, HoldAnswer) -> Void, tapped: @escaping () -> Void) {
        model.answer = answer
        model.tapped = tapped
    }

    /// Where the sessions come from, and how a session's own window is brought forward.
    @MainActor func wireSessions(
        list: @escaping () async -> [SessionCard],
        view: @escaping (String) async -> SessionView?,
        open: @escaping (String, DisplayHost?) -> Void
    ) {
        self.list = list
        self.view = view
        model.openWindow = open
        refresh()
    }

    /// The history read back from where it was kept, and kept there again after every answer.
    @MainActor func keepHistory(in file: HistoryFile) {
        historyFile = file
        model.history = file.load()
        model.forgetHistory = { [weak self] in
            guard let self else { return }
            self.model.history.forget()
            self.historyFile?.save(self.model.history)
            self.model.settle()
        }
    }

    /// What a button on an answer or a draft does, wired by the app delegate.
    @MainActor func wireConversation(
        openAnswer: @escaping (Exchange) -> Void,
        answerDraft: @escaping (DraftCard, Bool) -> Void,
        answerRule: @escaping (RuleCard, RuleScope?) -> Void,
        askAgain: @escaping (String) -> Void
    ) {
        model.openAnswer = openAnswer
        model.answerDraft = answerDraft
        model.answerRule = answerRule
        model.askAgain = askAgain
    }

    /// Control and Option held or let go: the island says it is taking down a rule while they are held.
    nonisolated func ruling(_ on: Bool) {
        DispatchQueue.main.async { [self] in
            withAnimation(.snappy) { model.ruling = on }
            model.settle()
        }
    }

    /// A proposed rule arrived: the island opens on it with the places it could hold, the suggested one picked.
    nonisolated func rule(subject: String, _ rule: RuleDraft) {
        let card = RuleCard(subject: subject, draft: rule)
        DispatchQueue.main.async { [self] in
            place()
            model.rule = card
            model.ruleScope = rule.suggestedScope?.id
            model.sending = false
            model.settle()
        }
    }

    /// Enforce or Not now ended: the card stays up when Touch ID was cancelled, and shakes when it did not go through.
    nonisolated func ruleAnswered(_ card: RuleCard, _ outcome: HeldOutcome) {
        DispatchQueue.main.async { [self] in
            model.sending = false
            switch outcome {
            case .answered:
                guard model.rule?.subject == card.subject else { return }
                model.rule = nil
                model.ruleScope = nil
                model.settle()
            case .cancelled: break
            case .failed: model.shakes += 1
            }
        }
    }

    /// The person's choice to see their own words in the notch as they say them.
    @MainActor func showLiveWords(_ on: Bool) {
        model.liveWords = on
        if !on { model.heard = "" }
        model.settle()
    }

    /// Where the orb is on screen while it shows large, for a card that flies out of it.
    @MainActor var orbFrame: NSRect? {
        guard model.mode.isOpen else { return nil }
        let orb = Island.orb(model.mode, model.notch, hovering: false)
        let size = model.size(of: model.mode)
        let left = frame.midX - size.width / 2
        return NSRect(
            x: left + orb.center.x - orb.diameter / 2, y: frame.maxY - orb.center.y - orb.diameter / 2,
            width: orb.diameter, height: orb.diameter
        )
    }

    nonisolated func present() {
        DispatchQueue.main.async { [self] in
            place()
            if !model.active { model.talkingSince = Date() }
            model.active = true
            model.settle()
        }
    }

    nonisolated func dismiss() {
        DispatchQueue.main.async { [self] in
            model.active = false
            model.caption = ""
            model.heard = ""
            model.expanded = false
            model.talkingSince = nil
            model.state = .idle
            renderer?.state = .idle
            model.settle()
        }
    }

    /// Every word heard so far, the moment the recognizer has it, for the notch to show as it is said.
    nonisolated func hearing(_ words: String) {
        DispatchQueue.main.async { [self] in
            guard model.liveWords, model.active, words != model.heard else { return }
            model.heard = words
            model.settle()
        }
    }

    nonisolated func asked(_ words: String) {
        DispatchQueue.main.async { [self] in
            model.history.ask(words, at: Date())
            model.heard = ""
            model.settle()
        }
    }

    nonisolated func replying(_ text: String) {
        DispatchQueue.main.async { [self] in model.history.reply(text) }
    }

    nonisolated func replied(failure: String?) {
        DispatchQueue.main.async { [self] in
            model.history.end(at: Date(), failure: failure)
            historyFile?.save(model.history)
            model.settle()
        }
    }

    /// Sending mail is set aside for now, so a drafted message is left unshown and nothing can send it.
    private nonisolated static let showsDrafts = false

    /// A drafted message arrived: the island opens on it, over whatever it was showing, until it is sent or closed.
    nonisolated func draft(subject: String, _ draft: MailDraft) {
        guard Self.showsDrafts else { return }
        let card = DraftCard(subject: subject, draft: draft)
        DispatchQueue.main.async { [self] in
            place()
            model.draft = card
            model.sending = false
            model.settle()
        }
    }

    /// A Send or a close ended: the card stays up when Touch ID was cancelled, and shakes when it did not go through.
    nonisolated func draftAnswered(_ card: DraftCard, _ outcome: HeldOutcome) {
        DispatchQueue.main.async { [self] in
            model.sending = false
            switch outcome {
            case .answered:
                guard model.draft?.subject == card.subject else { return }
                model.draft = nil
                model.settle()
            case .cancelled: break
            case .failed: model.shakes += 1
            }
        }
    }

    nonisolated func show(_ state: VoiceState, caption text: String) {
        DispatchQueue.main.async { [self] in
            renderer?.state = state
            model.state = state
            if !text.isEmpty || state == .idle { model.caption = text }
            // A fresh listen starts with no words, so nothing heard last time lingers in the bubble.
            if state == .listening, text.isEmpty { model.heard = "" }
            model.settle()
        }
    }

    /// An agent started waiting on the person: the island opens with the buttons to answer it.
    nonisolated func hold(_ event: DaemonEvent) {
        let card = HeldCard(event)
        DispatchQueue.main.async { [self] in
            place()
            model.held = card
            model.answering = false
            model.settle()
        }
    }

    /// The call was answered, here or anywhere else, so its buttons go.
    nonisolated func release(_ subject: String) {
        DispatchQueue.main.async { [self] in
            guard model.held?.subject == subject else { return }
            model.held = nil
            model.answering = false
            model.settle()
        }
    }

    /// A button press ended: the call stays up when Touch ID was cancelled or the answer failed.
    nonisolated func answered(_ subject: String, _ outcome: HeldOutcome) {
        DispatchQueue.main.async { [self] in
            model.answering = false
            switch outcome {
            case .answered: release(subject)
            case .cancelled: break
            case .failed: model.shakes += 1
            }
        }
    }

    /// A session finished: the island opens on it for a few seconds with a swell, then folds back.
    nonisolated func finished(_ event: DaemonEvent) {
        let card = FinishedCard(event)
        DispatchQueue.main.async { [self] in
            model.finished = card
            model.settle()
            model.hops += 1
            finishing?.cancel()
            finishing = Task { [weak self] in
                try? await Task.sleep(nanoseconds: Island.finishedFor)
                guard !Task.isCancelled, let model = self?.model else { return }
                model.finished = nil
                model.settle()
            }
        }
    }

    /// A shake, for something refused or paused.
    nonisolated func shake() {
        DispatchQueue.main.async { [self] in model.shakes += 1 }
    }

    /// Pinned to the top centre of the screen with the notch, or the main one on a Mac without.
    @MainActor private func place() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let notch = NotchGeometry.of(screen)
        if model.notch != notch { model.notch = notch }
        let origin = NSPoint(x: screen.frame.midX - Island.window.width / 2, y: screen.frame.maxY - Island.window.height)
        setFrame(NSRect(origin: origin, size: Island.window), display: false)
    }

    /// Every frame: lets clicks through outside the island, opens it on a dwell, and closes it after a minute untouched.
    @MainActor private func follow() {
        let size = model.size(of: model.mode)
        let shape = NSRect(
            x: frame.midX - size.width / 2 - Island.flare, y: frame.maxY - size.height,
            width: size.width + 2 * Island.flare, height: size.height
        ).insetBy(dx: -Layout.pointerSlop, dy: -Layout.pointerSlop)
        let mouse = NSEvent.mouseLocation
        let over = shape.contains(mouse)
        if ignoresMouseEvents == over { ignoresMouseEvents = !over }
        let now = Date()
        if over, mouse != lastMouse { lastActivity = now }
        lastMouse = mouse

        let small = model.mode == .peek || model.mode == .compact
        let hovering = over && small
        if hovering != model.hovering {
            withAnimation(.spring(response: Timing.hoverResponse, dampingFraction: Timing.hoverDamping)) { model.hovering = hovering }
        }
        // The left of the notch, where the orb rests, opens the side panel; anywhere else opens the island.
        let onLeft = mouse.x < frame.midX - model.notch.width / 2
        if hovering, onLeft != restingOnLeft {
            restingOnLeft = onLeft
            hoverSince = nil
        }
        if hovering, !model.active, !(onLeft && model.sideOpen) {
            let since = hoverSince ?? now
            hoverSince = since
            let dwell = model.mode == .peek ? Island.dwellResting : Island.dwellBusy
            if now.timeIntervalSince(since) >= dwell {
                if onLeft {
                    hoverSince = nil
                    side?.open()
                } else {
                    openIsland()
                }
            }
        } else {
            hoverSince = nil
        }

        guard model.opened, !model.active, [.overview, .session, .empty, .answer].contains(model.mode) else {
            if model.countdown != nil { model.countdown = nil }
            return
        }
        let left = Island.idleClose - now.timeIntervalSince(lastActivity)
        if left <= 0 {
            closeIsland()
            return
        }
        let countdown = left < Island.countdownFrom ? CGFloat(left / Island.countdownFrom) : nil
        if countdown != model.countdown { model.countdown = countdown }
    }

    @MainActor func openIsland() {
        hoverSince = nil
        lastActivity = Date()
        model.opened = true
        model.detail = false
        model.settle()
        refresh()
    }

    @MainActor func closeIsland() {
        guard model.opened else { return }
        model.opened = false
        model.detail = false
        model.picked = nil
        model.countdown = nil
        model.settle()
        refresh()
    }

    /// Reads the sessions, quickly while the island is open and slowly while it only shows dots.
    @MainActor private func refresh() {
        refresher?.cancel()
        refresher = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                // Memnox's own operator answers the person; it is not one of the agents being watched.
                let cards = await list().filter { !IslandPalette.kind($0.agent).hasPrefix(Self.operatorKindPrefix) }
                guard !Task.isCancelled else { return }
                if cards != model.cards { model.cards = cards }
                if model.opened, let focus = model.focusCard {
                    if model.focusId == nil { model.focusId = focus.sessionId }
                    let view = await view(focus.sessionId)
                    guard !Task.isCancelled else { return }
                    if view != model.focused { model.focused = view }
                }
                model.settle()
                let pause = model.opened ? Timing.openRefresh : Timing.restingRefresh
                try? await Task.sleep(nanoseconds: UInt64(pause * Timing.nanosecondsPerSecond))
            }
        }
    }

    /// The side panel put up or taken down, from the header, the menu or the preview.
    @MainActor func showSide(_ on: Bool) {
        on ? side?.open() : side?.close(animated: true)
    }

    /// An exchange picked in the side panel, opened tall under the notch beside it.
    @MainActor private func showExchange(_ id: UUID) {
        guard !model.active else { return }
        model.picked = id
        openIsland()
    }

    /// The answer under the question opened up tall, or put back in its card.
    @MainActor func expandAnswer(_ on: Bool) {
        model.expanded = on
        model.settle()
    }

    /// The open island turned to one session up close, or back to all of them.
    @MainActor func showDetail(_ on: Bool) {
        lastActivity = Date()
        model.detail = on
        model.settle()
    }

    /// A pill was clicked: that session comes into focus and is read at once.
    @MainActor private func focus(_ sessionId: String) {
        lastActivity = Date()
        guard model.focusId != sessionId else { return }
        model.focusId = sessionId
        model.focused = nil
        refresh()
    }
}
