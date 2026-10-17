import AppKit
import MetalKit
import MemnoxVoiceCore
import SwiftUI

/// The face Memnox puts on screen: an island that grows out of the notch, holding the orb, the
/// sessions, the voice's caption and, for a held call, the answer buttons. It never takes focus
/// from the editor underneath, and lets every click outside its own shape through.
final class IslandPanel: NSPanel, Face {
    private let model: IslandModel
    /// Read only, so a window can answer a held call through the notch's own signed path.
    var islandModel: IslandModel { model }
    private let orb: MTKView
    private let renderer: OrbRenderer?
    private var poll: Timer?
    private var hoverSince: Date?
    private var lastActivity = Date()
    private var lastMouse = NSPoint.zero
    private var refresher: Task<Void, Never>?
    private var finishing: Task<Void, Never>?
    /// Takes a card down once it has said who answered its call elsewhere.
    private var settling: Task<Void, Never>?
    /// Clears a pick's error from the question card after a moment.
    private var questionFailing: Task<Void, Never>?
    /// Clears the drive state when its grant runs out, in case no notice says it stopped.
    private var driveEnd: Task<Void, Never>?
    private var phoneEnd: Task<Void, Never>?
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
        // Dark in every look the person picks, because the island grows out of the black hardware notch and must match it.
        appearance = NSAppearance(named: .darkAqua)
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
        NotificationCenter.default.addObserver(forName: IslandScreens.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.place()
                self?.side?.place()
            }
        }
        // A click anywhere else puts the open island away; clicks on the island itself are not global.
        clicks = EventMonitor.global([.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeIsland() }
        }
    }

    /// Only while a draft is up, so its words can be typed into and the island never takes keys otherwise.
    override var canBecomeKey: Bool { model.work != nil }

    /// Not pushed below the menu bar, which is exactly where the island lives.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    /// The answer buttons and a tap on the resting orb, wired by the app delegate.
    @MainActor func wire(
        answer: @escaping (HeldCard, HoldAnswer) -> Void,
        answerQuestion: @escaping (AgentQuestionCard, Int, String) -> Void,
        tapped: @escaping () -> Void
    ) {
        model.answer = answer
        model.answerQuestion = answerQuestion
        model.tapped = tapped
    }

    /// An agent asked in its own picker: the island opens on its choices; one with nothing to pick stays spoken only.
    nonisolated func question(_ event: DaemonEvent) {
        guard let card = AgentQuestionCard(event) else { return }
        DispatchQueue.main.async { [self] in
            place()
            model.question = card
            model.ticked = []
            model.questionError = nil
            model.settle()
        }
    }

    /// A pick went through: the card moves on to the next question, or goes once every question has its answer.
    nonisolated func questionAnswered(_ card: AgentQuestionCard, number: Int, answer: String, _ outcome: HeldOutcome) {
        DispatchQueue.main.async { [self] in
            guard model.question?.subject == card.subject else { return }
            switch outcome {
            case .answered, .answeredElsewhere:
                let moved = card.answering(number, with: answer)
                model.question = moved.next == nil ? nil : moved
                model.ticked = []
                model.questionError = nil
            case .cancelled: break
            case .failed(let why):
                model.questionError = why
                model.shakes += 1
                questionFailing?.cancel()
                questionFailing = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: Island.settledFor)
                    guard !Task.isCancelled else { return }
                    self?.model.questionError = nil
                }
            }
            model.settle()
        }
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

    /// Opens a session's live window from its detail, putting the island away first so the window is in front.
    @MainActor func wireLive(_ live: @escaping (String, DisplayHost?) -> Void) {
        model.watchLive = { [weak self] session, host in
            self?.closeIsland()
            live(session, host)
        }
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

    /// The agents and apps the grid's tools page shows, the same list the menu and Settings read.
    @MainActor func useTools(_ tools: ToolsModel) {
        model.tools = tools
    }

    /// What the grid's tiles and the round buttons do beyond the island, wired by the app delegate.
    @MainActor func wireLauncher(sayRule: @escaping () -> Void, copyWhatHappened: @escaping () -> Void,
                                 openSettings: @escaping (SettingsPage?) -> Void) {
        model.sayRule = { [weak self] in
            self?.closeIsland()
            sayRule()
        }
        model.copyWhatHappened = copyWhatHappened
        model.openSettings = { [weak self] page in
            self?.closeIsland()
            openSettings(page)
        }
    }

    /// What a button on an answer or a draft does, wired by the app delegate.
    @MainActor func wireConversation(
        openAnswer: @escaping (Exchange) -> Void,
        answerDraft: @escaping (DraftCard, Bool) -> Void,
        answerWork: @escaping (WorkCard, Bool) -> Void,
        openSignIn: @escaping (ToolSignIn) -> Void,
        notMine: @escaping (SignedInCard) -> Void,
        answerRule: @escaping (RuleCard, RuleScope?) -> Void,
        askAgain: @escaping (String) -> Void,
        ask: @escaping (String) -> Void
    ) {
        model.openAnswer = openAnswer
        model.answerDraft = answerDraft
        model.answerWork = answerWork
        model.openSignIn = openSignIn
        model.notMine = notMine
        model.answerRule = answerRule
        model.askAgain = askAgain
        model.ask = ask
    }

    /// Control and Option held or let go: the island says it is taking down a rule while they are held.
    nonisolated func ruling(_ on: Bool) {
        DispatchQueue.main.async { [self] in
            withAnimation(.snappy) { model.ruling = on }
            model.settle()
        }
    }

    /// Dictation began or ended: the island says it is typing into the app in front, with what to say.
    nonisolated func dictating(_ hint: String?) {
        DispatchQueue.main.async { [self] in
            withAnimation(.snappy) { model.dictating = hint }
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
            // Answered first elsewhere is answered all the same, so the card goes either way.
            case .answered, .answeredElsewhere:
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
            model.dictating = nil
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

    /// A phone started or stopped driving this Mac: the state stays up for the whole grant and goes at its time.
    nonisolated func driven(_ grant: DriveGrant?) {
        DispatchQueue.main.async { [self] in
            driveEnd?.cancel()
            withAnimation(.snappy) { model.driving = grant }
            guard let grant else { return }
            let wait = max(0, grant.until.timeIntervalSinceNow)
            driveEnd = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(wait * Timing.nanosecondsPerSecond))
                guard !Task.isCancelled, let self, self.model.driving == grant else { return }
                withAnimation(.snappy) { self.model.driving = nil }
            }
        }
    }

    /// A phone took the voice or gave it back: the state stays up while it holds it, so the Mac's silence has a reason.
    nonisolated func voiceOn(_ phone: PhoneVoice?) {
        DispatchQueue.main.async { [self] in
            withAnimation(.snappy) { model.voiceOn = phone }
        }
    }

    /// A phone's turn as it stands: shown like the person's own, with no sound, and put away a moment after it ends.
    nonisolated func phone(_ turn: PhoneExchange) {
        DispatchQueue.main.async { [self] in
            phoneEnd?.cancel()
            place()
            model.phone = turn
            model.settle()
            guard !turn.isAnswering else { return }
            phoneEnd = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: Island.phoneTurnFor)
                guard !Task.isCancelled, let self, self.model.phone?.id == turn.id else { return }
                self.model.phone = nil
                self.model.settle()
            }
        }
    }

    /// What an action was seen to leave behind, kept beside the answer it belongs to.
    nonisolated func proof(_ proof: Proof) {
        DispatchQueue.main.async { [self] in model.history.prove(proof) }
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
            case .answered, .answeredElsewhere:
                guard model.draft?.subject == card.subject else { return }
                model.draft = nil
                model.settle()
            case .cancelled: break
            case .failed: model.shakes += 1
            }
        }
    }

    /// Something about to go out in the person's name: the island opens on its card until it is sent or closed.
    nonisolated func work(subject: String, _ draft: WorkDraft) {
        let card = WorkCard(subject: subject, draft: draft)
        DispatchQueue.main.async { [self] in
            place()
            model.work = card
            model.sending = false
            model.settle()
        }
    }

    /// A Send or a close ended: the card stays up when Touch ID was cancelled, and shakes when it did not go through.
    nonisolated func workAnswered(_ card: WorkCard, _ outcome: HeldOutcome) {
        DispatchQueue.main.async { [self] in
            model.sending = false
            switch outcome {
            case .answered, .answeredElsewhere:
                guard model.work?.subject == card.subject else { return }
                model.work = nil
                model.settle()
            case .cancelled: break
            case .failed: model.shakes += 1
            }
        }
    }

    /// The tools still to sign in to. The person just asked for something one of them does, so each sign in opens in
    /// the browser at once rather than waiting as an icon over their tabs; only one that cannot open, one opened a
    /// moment ago, or one asked for from a phone, which is not at this screen, stays as an icon under the notch.
    nonisolated func signIns(_ tools: [ToolSignIn]) {
        DispatchQueue.main.async { [self] in
            withAnimation(.snappy) { model.signIns = tools }
            guard model.driving == nil else { return }
            let now = Date()
            openedSignIns = openedSignIns.filter { now.timeIntervalSince($0.value) < Self.signInReopenAfter }
            for tool in tools where openedSignIns[tool.toolkit] == nil {
                openedSignIns[tool.toolkit] = now
                // Removes the icon once the browser has it, and leaves it where the browser would not.
                model.openSignIn(tool)
            }
        }
    }

    /// When each tool's sign in was last opened by itself, so a list sent again never opens the same page twice.
    @MainActor private var openedSignIns: [String: Date] = [:]
    /// Long enough to sign in once; after it, asking again opens the page again.
    private nonisolated static let signInReopenAfter: TimeInterval = 120

    /// How long a sign in known to be theirs stays under the notch: long enough to read whose account it is.
    private nonisolated static let signedInShown: TimeInterval = 3
    /// Longer where nothing ties the account to them yet, so there is time to see the name and press Not me.
    private nonisolated static let unverifiedShown: TimeInterval = 8

    /// A sign in finished: its icon goes, the pill says whose account it reached, and what was asked carries on.
    /// One that never finished leaves its icon for another tap, and the voice says why.
    nonisolated func signedIn(_ notice: SignedInNotice) {
        DispatchQueue.main.async { [self] in
            guard notice.finished else { return }
            let card = SignedInCard(notice: notice)
            withAnimation(.snappy) {
                model.signIns.removeAll { $0.toolkit == notice.toolkit }
                model.signedIn = card
            }
            if let resume = notice.resume { model.askAgain(resume) }
            let shown = card.unverified ? Self.unverifiedShown : Self.signedInShown
            DispatchQueue.main.asyncAfter(deadline: .now() + shown) { [self] in
                guard model.signedIn == card else { return }
                withAnimation(.snappy) { model.signedIn = nil }
            }
        }
    }

    /// Not me was pressed, so the pill goes at once and a fresh sign in takes its place.
    @MainActor func signedInDismissed(_ card: SignedInCard) {
        guard model.signedIn == card else { return }
        withAnimation(.snappy) { model.signedIn = nil }
    }

    /// A tool's sign in was opened, so its icon leaves the notch.
    @MainActor func signingIn(_ tool: ToolSignIn) {
        withAnimation(.snappy) { model.signIns.removeAll { $0.toolkit == tool.toolkit } }
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
    nonisolated func hold(_ event: DaemonEvent, server: String? = nil) {
        hold(card: HeldCard(event, server: server))
    }

    /// A held call already made into a card, such as one a teammate's agent raised that the workspace routed here.
    /// It joins any already waiting; the card on screen stays while one is being answered or was stepped to.
    nonisolated func hold(card: HeldCard) {
        DispatchQueue.main.async { [self] in
            place()
            model.waiting.add(card, subject: card.subject, machine: card.machine, keepShown: model.answering || model.settledNote != nil)
            renderer?.waiting = true
            model.settle()
        }
    }

    /// The call stopped waiting, so its card goes and the next one waiting comes up. `note` says who answered it
    /// elsewhere, shown on its card for a moment first; a call answered from this Mac's own buttons never shows one.
    nonisolated func release(_ subject: String, note: String? = nil) {
        DispatchQueue.main.async { [self] in
            // A draft withdrawn by voice or run out settles too, and its card goes; one being sent is left to its answer.
            if model.work?.subject == subject, !model.sending {
                model.work = nil
                model.settle()
            }
            // Answered here, by voice or in the agent's own picker, or run out: the question has nothing left to ask.
            if model.question?.subject == subject {
                model.question = nil
                model.ticked = []
                model.questionError = nil
                model.settle()
            }
            if let note, model.held?.subject == subject, model.pressed != subject {
                model.settledNote = note
                model.answering = false
                settling?.cancel()
                settling = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: Island.settledFor)
                    guard !Task.isCancelled else { return }
                    self?.drop(subject)
                }
                return
            }
            if model.held?.subject == subject { settling?.cancel() }
            drop(subject)
        }
    }

    /// Takes a call off the island at once, with whatever note its card was showing.
    private func drop(_ subject: String) {
        let wasShown = model.held?.subject == subject
        guard model.waiting.remove(subject) else { return }
        if wasShown {
            model.settledNote = nil
            model.answering = false
        }
        if model.pressed == subject { model.pressed = nil }
        renderer?.waiting = !model.waiting.isEmpty
        model.settle()
    }

    /// A button press ended: the call stays up when Touch ID was cancelled or the answer failed.
    nonisolated func answered(_ subject: String, _ outcome: HeldOutcome) {
        DispatchQueue.main.async { [self] in
            model.answering = false
            switch outcome {
            case .answered: release(subject)
            case .answeredElsewhere(let first):
                // Somebody got there first, so the card says how it was settled before it goes.
                model.pressed = nil
                release(subject, note: SettledLine.line(answer: first.word, by: nil, on: nil))
            case .cancelled, .failed:
                model.pressed = nil
                if case .failed = outcome { model.shakes += 1 }
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

    /// The orb's gesture at an answer, from the conversation.
    nonisolated func react(_ reaction: Reaction) {
        react(reaction, session: nil)
    }

    /// The orb's gesture at something an agent did, and a stumble on that session's logo when it went wrong.
    nonisolated func react(_ reaction: Reaction, session: String?) {
        DispatchQueue.main.async { [self] in
            renderer?.react(reaction)
            guard reaction == .stumble, let session else { return }
            model.stumbling.insert(session)
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: Island.stumbleFor)
                self?.model.stumbling.remove(session)
            }
        }
    }

    /// A shake, for something refused or paused.
    nonisolated func shake() {
        DispatchQueue.main.async { [self] in model.shakes += 1 }
    }

    /// Pinned to the top centre of the screen chosen in Settings, the one with the notch unless the person chose another.
    @MainActor private func place() {
        guard let screen = IslandScreens.host(open: isOpen) else { return }
        let notch = NotchGeometry.of(screen)
        if model.notch != notch { model.notch = notch }
        let origin = NSPoint(x: screen.frame.midX - Island.window.width / 2, y: screen.frame.maxY - Island.window.height)
        let placed = NSRect(origin: origin, size: Island.window)
        if frame != placed { setFrame(placed, display: false) }
    }

    /// Showing something, or with the side panel out, so following the pointer waits rather than moving it away.
    @MainActor private var isOpen: Bool {
        model.active || model.sideOpen || !(model.mode == .peek || model.mode == .compact)
    }

    /// Every frame: lets clicks through outside the island, opens it on a dwell, and closes it after a minute untouched.
    @MainActor private func follow() {
        // Only a pointer that left the island's screen costs a look at the screens, so following it stays cheap.
        if IslandScreens.choice == .pointer, !isOpen, let here = IslandScreens.current,
           !IslandScreens.holds(NSEvent.mouseLocation, here) {
            place()
            side?.place()
        }
        let size = model.size(of: model.mode)
        let shape = NSRect(
            x: frame.midX - size.width / 2 - Island.flare, y: frame.maxY - size.height,
            width: size.width + 2 * Island.flare, height: size.height
        ).insetBy(dx: -Layout.pointerSlop, dy: -Layout.pointerSlop)
        let mouse = NSEvent.mouseLocation
        let over = shape.contains(mouse)
        // The sign in icons and the signed in pill hang under the island and take clicks too, but never open it.
        let below = model.clickableBelow
        let overBelow = below.height > 0 && NSRect(
            x: frame.minX + below.minX, y: frame.maxY - below.maxY, width: below.width, height: below.height
        ).insetBy(dx: -Layout.pointerSlop, dy: -Layout.pointerSlop).contains(mouse)
        // The round buttons either side of the open island take clicks too, over their column only.
        let satellites = model.showsSatellites && NSRect(
            x: shape.minX - NotchMetrics.satelliteReach, y: frame.maxY - Island.satelliteColumn(model.notch),
            width: shape.width + 2 * NotchMetrics.satelliteReach, height: Island.satelliteColumn(model.notch)
        ).contains(mouse)
        let clickable = over || overBelow || satellites
        if ignoresMouseEvents == clickable { ignoresMouseEvents = !clickable }
        let now = Date()
        if clickable, mouse != lastMouse { lastActivity = now }
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
        model.launcher = false
        model.launcherTools = false
        model.pickedTool = nil
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
