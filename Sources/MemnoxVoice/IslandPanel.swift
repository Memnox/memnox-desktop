import AppKit
import MetalKit
import MemnoxVoiceCore
import SwiftUI

/// What the island is showing. The small ones sit beside the notch; the rest open 640 wide below it.
enum IslandMode: Equatable {
    /// Nothing going on: the orb rests beside the notch, breathing, and a click starts listening.
    case peek
    /// Sessions working: the orb left of the notch, one dot per working session right of it.
    case compact
    /// Talking: the orb grown large below the notch, with what was heard or said under it.
    case voice
    /// Opened by the pointer: the session in focus, what it is doing, and every other session as a pill.
    case overview
    /// One session up close: what it did and the code it is writing.
    case session
    /// Opened by the pointer with nothing running.
    case empty
    /// An agent is waiting on the person, with the buttons to answer it.
    case held
    /// A session just finished, shown for a few seconds and then put away.
    case finished

    var isOpen: Bool { self != .peek && self != .compact }
}

/// A held call as the island shows it, taken from the daemon's event.
struct HeldCard: Equatable, Sendable {
    let subject: String
    let agent: String
    let who: String
    let what: String
    let why: String?
    let summary: String

    init(_ event: DaemonEvent) {
        subject = event.subject
        agent = event.agent
        who = event.agentName ?? event.agent
        what = event.what ?? event.summary
        why = event.why
        summary = event.summary
    }
}

/// A session that just finished, from the daemon's notice.
struct FinishedCard: Equatable, Sendable {
    let agent: String
    let who: String
    let summary: String
    let sessionId: String?
    let host: DisplayHost?

    init(_ event: DaemonEvent) {
        agent = event.agent
        who = event.agentName ?? event.agent
        summary = event.summary
        sessionId = event.sessionId
        host = event.host
    }
}

/// Where the notch is on this screen, or a small bar standing in for one on a Mac without it.
struct NotchGeometry: Equatable {
    let width: CGFloat
    let height: CGFloat
    let hasNotch: Bool

    static func of(_ screen: NSScreen) -> NotchGeometry {
        let top = screen.safeAreaInsets.top
        if top > 0, let left = screen.auxiliaryTopLeftArea?.width, let right = screen.auxiliaryTopRightArea?.width {
            return NotchGeometry(width: screen.frame.width - left - right, height: top, hasNotch: true)
        }
        let bar = screen.frame.maxY - screen.visibleFrame.maxY
        return NotchGeometry(width: 80, height: min(bar > 0 ? bar : NSStatusBar.system.thickness, 24), hasNotch: false)
    }
}

/// Everything the island draws, kept apart from the window so the view only reads it.
@MainActor
final class IslandModel: ObservableObject {
    @Published private(set) var mode: IslandMode = .peek
    @Published var state: VoiceState = .idle
    @Published var caption = ""
    @Published var held: HeldCard?
    @Published var finished: FinishedCard?
    /// Set while Touch ID is up for a button, so a second press cannot raise a second sheet.
    @Published var answering = false
    @Published var notch = NotchGeometry(width: 185, height: 32, hasNotch: true)
    @Published var hovering = false
    /// Every recent session, working ones first, and the one the open island is about.
    @Published var cards: [SessionCard] = []
    @Published var focusId: String?
    @Published var focused: SessionView?
    /// Whether the open island shows one session up close rather than all of them.
    @Published var detail = false
    /// Flipped on just after the island opens, so the pills arrive one after another.
    @Published var revealed = false
    /// From one down to nothing over the last ten seconds before the open island puts itself away.
    @Published var countdown: CGFloat?
    @Published var hops = 0
    @Published var shakes = 0

    var active = false
    var opened = false
    var answer: (String, HoldAnswer, String) -> Void = { _, _, _ in }
    var tapped: () -> Void = {}
    var openWindow: (String, DisplayHost?) -> Void = { _, _ in }
    var focus: (String) -> Void = { _ in }

    var working: [SessionCard] { cards.filter(\.isWorking) }

    var focusCard: SessionCard? { cards.first { $0.sessionId == focusId } ?? cards.first }

    /// The one place the mode is decided, so no two callers disagree about what is on screen.
    func settle() {
        let next: IslandMode
        if held != nil {
            next = .held
        } else if finished != nil {
            next = .finished
        } else if active {
            next = .voice
        } else if opened {
            next = cards.isEmpty ? .empty : detail && focused != nil ? .session : .overview
        } else {
            next = working.isEmpty ? .peek : .compact
        }
        guard next != mode else { return }
        let growing = Island.area(next, notch) > Island.area(mode, notch)
        withAnimation(Island.motion(growing: growing)) { mode = next }
        if next == .overview {
            revealed = false
            DispatchQueue.main.async { [weak self] in self?.revealed = true }
        }
    }

    func size(of mode: IslandMode) -> CGSize { Island.size(mode, notch) }
}

/// The measurements and timings the island is drawn and moved with, after Coucou's spec.
enum Island {
    static let width: CGFloat = 640
    /// The concave curve where the island meets the screen edge on either side.
    static let flare: CGFloat = 14
    static let voiceWidth: CGFloat = 440
    /// Big enough that the orb reads as the one thing on screen while you talk.
    static let voiceOrb: CGFloat = 150
    static let window = CGSize(width: width + 2 * flare + 40, height: 310 + 40)
    /// Long enough that passing the pointer across the menu bar never opens it.
    static let dwellResting: TimeInterval = 0.65
    static let dwellBusy: TimeInterval = 0.2
    /// Open and untouched this long, it puts itself away; the last ten seconds are shown as a shrinking line.
    static let idleClose: TimeInterval = 60
    static let countdownFrom: TimeInterval = 10
    /// How long a finished session stays up before the island folds back.
    static let finishedFor: UInt64 = 5_200_000_000

    static func size(_ mode: IslandMode, _ notch: NotchGeometry) -> CGSize {
        switch mode {
        case .peek: return CGSize(width: notch.width + 64, height: notch.height)
        case .compact: return CGSize(width: notch.width + 104, height: notch.height)
        case .voice: return CGSize(width: voiceWidth, height: top(notch) + 190)
        case .overview: return CGSize(width: width, height: 196)
        case .session: return CGSize(width: width, height: 256)
        case .empty: return CGSize(width: width, height: 150)
        case .held: return CGSize(width: width, height: 206)
        case .finished: return CGSize(width: width, height: 170)
        }
    }

    static func area(_ mode: IslandMode, _ notch: NotchGeometry) -> CGFloat {
        let size = size(mode, notch)
        return size.width * size.height
    }

    /// Where content starts below the notch row, which is also where the header sits.
    static func top(_ notch: NotchGeometry) -> CGFloat { max(36, notch.height + 4) }

    /// Growing overshoots a little, the way something springs out; shrinking settles with no bounce.
    static func motion(growing: Bool) -> Animation {
        growing ? .spring(response: 0.5, dampingFraction: 0.72) : .timingCurve(0.45, 0, 0.2, 1, duration: 0.34)
    }

    /// The orb's centre and diameter in each mode, so it travels and grows with the island as one piece.
    static func orb(_ mode: IslandMode, _ notch: NotchGeometry, hovering: Bool) -> (center: CGPoint, diameter: CGFloat) {
        let height = size(mode, notch).height
        let top = top(notch)
        let middle = top + (height - top - 10) / 2
        switch mode {
        case .peek: return (CGPoint(x: 19, y: notch.height / 2), hovering ? 22 : 18)
        case .compact: return (CGPoint(x: 27, y: notch.height / 2), hovering ? 23 : 20)
        case .voice: return (CGPoint(x: voiceWidth / 2, y: top + 92), voiceOrb)
        case .overview: return (CGPoint(x: 64, y: middle), 70)
        case .session: return (CGPoint(x: 46, y: top + 36), 44)
        case .empty: return (CGPoint(x: 70, y: middle), 62)
        case .held: return (CGPoint(x: 62, y: middle), 56)
        case .finished: return (CGPoint(x: 62, y: middle), 58)
        }
    }
}

/// The colours the island is painted in, after the card and veil values in Coucou's spec.
enum IslandPalette {
    static let card = Color(hex: 0x141518)
    static let primaryFill = Color(hex: 0xF5F6F8)
    static let primaryText = Color(hex: 0x0B0C0E)
    static let quiet = Color(hex: 0x5F646D)
    static let soft = Color(hex: 0xC9CDD4)
    static let red = Color(red: 244 / 255, green: 80 / 255, blue: 94 / 255)
    static let green = Color(red: 52 / 255, green: 211 / 255, blue: 153 / 255)
    static let amber = Color(red: 245 / 255, green: 165 / 255, blue: 36 / 255)
    static let indigo = Color(red: 99 / 255, green: 102 / 255, blue: 241 / 255)

    /// Each agent keeps one colour everywhere it appears; any other takes one of these by its name.
    private static let known: [String: UInt32] = [
        "claude-code": 0xD97757, "claude": 0xD97757, "claude-desktop": 0xD97757,
        "codex": 0x2DD4BF, "codex-cli": 0x2DD4BF, "cursor": 0xC0C4CC, "gemini": 0x8AB4F8,
        "antigravity": 0xE879F9, "hermes": 0xA78BFA, "openclaw": 0xF7B32B, "cline": 0x38BDF8,
    ]
    private static let others: [UInt32] = [0xF472B6, 0x34D399, 0xFB923C, 0x60A5FA, 0xE879F9]

    static func kind(_ agent: String?) -> String {
        let id = agent ?? ""
        return id.hasPrefix("agt_") ? String(id.dropFirst(4)) : id
    }

    static func color(_ agent: String?) -> Color {
        let kind = kind(agent)
        if let hex = known[kind] { return Color(hex: hex) }
        let index = kind.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Color(hex: others[index % others.count])
    }
}

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
    private var clicks: Any?
    private var list: () async -> [SessionCard] = { [] }
    private var view: (String) async -> SessionView? = { _ in nil }

    init(loudness: @escaping () -> Float) {
        let model = IslandModel()
        self.model = model
        orb = MTKView(frame: NSRect(x: 0, y: 0, width: 64, height: 64), device: MTLCreateSystemDefaultDevice())
        orb.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        orb.preferredFramesPerSecond = 60
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
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        model.focus = { [weak self] session in self?.focus(session) }
        // Takes the first click, since the island never becomes the active window and would otherwise swallow it.
        let hosting = FirstClickHosting(rootView: IslandView(model: model, orb: orb, loudness: loudness))
        // The window keeps its own size, since the island grows inside it rather than with it.
        hosting.sizingOptions = []
        contentView = hosting
        place()
        orderFrontRegardless()
        // Polled rather than tracked, because the window is larger than the island and must let clicks past its shape.
        poll = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.follow() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.place() }
        }
        // A click anywhere else puts the open island away; clicks on the island itself are not global.
        clicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeIsland() }
        }
    }

    override var canBecomeKey: Bool { false }

    /// Not pushed below the menu bar, which is exactly where the island lives.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    /// The answer buttons and a tap on the resting orb, wired by the app delegate.
    @MainActor func wire(answer: @escaping (String, HoldAnswer, String) -> Void, tapped: @escaping () -> Void) {
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
            model.active = true
            model.settle()
        }
    }

    nonisolated func dismiss() {
        DispatchQueue.main.async { [self] in
            model.active = false
            model.caption = ""
            model.state = .idle
            renderer?.state = .idle
            model.settle()
        }
    }

    nonisolated func show(_ state: VoiceState, caption text: String) {
        DispatchQueue.main.async { [self] in
            renderer?.state = state
            model.state = state
            if !text.isEmpty || state == .idle { model.caption = text }
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
        ).insetBy(dx: -6, dy: -6)
        let mouse = NSEvent.mouseLocation
        let over = shape.contains(mouse)
        if ignoresMouseEvents == over { ignoresMouseEvents = !over }
        let now = Date()
        if over, mouse != lastMouse { lastActivity = now }
        lastMouse = mouse

        let small = model.mode == .peek || model.mode == .compact
        let hovering = over && small
        if hovering != model.hovering {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.6)) { model.hovering = hovering }
        }
        if hovering, !model.active {
            let since = hoverSince ?? now
            hoverSince = since
            let dwell = model.mode == .peek ? Island.dwellResting : Island.dwellBusy
            if now.timeIntervalSince(since) >= dwell { openIsland() }
        } else {
            hoverSince = nil
        }

        guard model.opened, [.overview, .session, .empty].contains(model.mode) else {
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
                let cards = await list().filter { !IslandPalette.kind($0.agent).hasPrefix("memnox") }
                guard !Task.isCancelled else { return }
                if cards != model.cards { model.cards = cards }
                if model.opened, let focus = model.focusCard {
                    if model.focusId == nil { model.focusId = focus.sessionId }
                    let view = await view(focus.sessionId)
                    guard !Task.isCancelled else { return }
                    if view != model.focused { model.focused = view }
                }
                model.settle()
                try? await Task.sleep(nanoseconds: model.opened ? 2_000_000_000 : 5_000_000_000)
            }
        }
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

/// The island: a black shape that flows out of the screen's top edge, the orb, and the content of the mode.
private struct IslandView: View {
    @ObservedObject var model: IslandModel
    let orb: MTKView
    let loudness: () -> Float

    var body: some View {
        let notch = model.notch
        let size = model.size(of: model.mode)
        let orbAt = Island.orb(model.mode, notch, hovering: model.hovering)
        let canvas = orbAt.diameter / 0.62
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                NotchShape(flare: Island.flare, bottomRadius: model.mode.isOpen ? 30 : 14)
                    .fill(Color.black)
                    .shadow(color: .black.opacity(model.mode.isOpen ? 0.45 : 0.2), radius: 18, y: 8)
                ZStack(alignment: .topLeading) {
                    if model.mode.isOpen {
                        Header(model: model)
                            .transition(.opacity.animation(.easeOut(duration: 0.25).delay(0.3)))
                    }
                    content
                        .id(model.mode)
                        .transition(.islandContent)
                    // One orb throughout, positioned rather than swapped, so it travels and grows with the island.
                    OrbSurface(view: orb)
                        .frame(width: canvas, height: canvas)
                        .position(orbAt.center)
                        .allowsHitTesting(false)
                    if let countdown = model.countdown {
                        Capsule()
                            .fill(Color.white.opacity(0.35))
                            .frame(width: 160 * countdown, height: 2)
                            .position(x: size.width / 2, y: size.height - 4)
                            .animation(.linear(duration: 0.2), value: countdown)
                    }
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .padding(.leading, Island.flare)
            }
            .frame(width: size.width + 2 * Island.flare, height: size.height, alignment: .topLeading)
            .modifier(Shake(times: CGFloat(model.shakes)))
            .modifier(Hop(times: CGFloat(model.hops)))
            .animation(.easeInOut(duration: 0.5), value: model.hops)
            .animation(.linear(duration: 0.42), value: model.shakes)
            Spacer(minLength: 0)
        }
        .frame(width: Island.window.width, height: Island.window.height, alignment: .top)
    }

    @ViewBuilder private var content: some View {
        switch model.mode {
        case .peek:
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { model.tapped() }
        case .compact:
            Compact(model: model, loudness: loudness)
        case .voice:
            VoiceCard(model: model)
        case .overview:
            Overview(model: model)
        case .session:
            if let session = model.focused { SessionDetail(model: model, session: session) }
        case .empty:
            Empty(model: model)
        case .held:
            if let held = model.held { Held(model: model, card: held) }
        case .finished:
            if let finished = model.finished { Finished(model: model, card: finished) }
        }
    }
}

/// The row along the notch while the island is open: where you are on the left, how many are working on the right.
private struct Header: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        let count = model.working.count
        HStack(spacing: 4) {
            Tab(symbol: "square.grid.2x2", on: model.mode == .overview || model.mode == .empty) {
                model.detail = false
                model.settle()
            }
            if model.mode == .session {
                Tab(symbol: "chevron.left", on: false) {
                    model.detail = false
                    model.settle()
                }
            }
            Tab(symbol: "waveform", on: model.mode == .voice) { model.tapped() }
            Spacer(minLength: model.notch.width + 16)
            Text(count == 1 ? "1 working" : "\(count) working")
                .font(Memnox.sans(12.5, .medium))
                .foregroundStyle(Color.white.opacity(0.55))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: count)
                .padding(.trailing, 18)
        }
        .padding(.leading, 12)
        .frame(height: model.notch.height)
    }
}

/// A round icon tab in the header, filled when it is where you are.
private struct Tab: View {
    let symbol: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(on ? Color.white : Color.white.opacity(0.5))
                .frame(width: 30, height: 24)
                .background(Capsule().fill(Color.white.opacity(on ? 0.12 : 0)))
        }
        .buttonStyle(Pressable())
    }
}

/// Beside the notch with sessions working or the voice listening: the orb left, and on the right
/// a waveform for the voice or one dot per working session.
private struct Compact: View {
    @ObservedObject var model: IslandModel
    let loudness: () -> Float

    var body: some View {
        let height = model.notch.height
        ZStack(alignment: .trailing) {
            Color.clear
            if model.active {
                Waveform(loudness: loudness, state: model.state)
                    .frame(width: 36, height: 16)
                    .padding(.trailing, 14)
            } else {
                Logos(cards: Array(model.working.prefix(3)))
                    .frame(height: height)
                    .padding(.trailing, 12)
            }
        }
        .frame(height: height)
        .contentShape(Rectangle())
        .onTapGesture { model.tapped() }
    }
}

/// The working agents' logos, overlapping like faces in a doorway, so a glance says who is busy.
private struct Logos: View {
    let cards: [SessionCard]

    var body: some View {
        HStack(spacing: -5) {
            ForEach(cards, id: \.sessionId) { card in
                Logo(card: card, size: 16)
                    .overlay(Circle().strokeBorder(Color.black, lineWidth: 1.5))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: cards.map(\.sessionId))
    }
}

/// Talking: the big orb alone with a soft light behind it. Nothing is written under it, since what was
/// said is heard, and reading it back on screen only repeats it.
private struct VoiceCard: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        let top = Island.top(model.notch)
        ZStack(alignment: .top) {
            // The orb draws additively, so a dim pool of its own blue behind it reads as the glow off a light.
            RadialGradient(
                colors: [glow.opacity(model.state == .idle ? 0.12 : 0.28), .clear],
                center: .center, startRadius: 0, endRadius: Island.voiceOrb * 0.95
            )
            .frame(width: Island.voiceOrb * 2, height: Island.voiceOrb * 2)
            .position(x: Island.voiceWidth / 2, y: top + 92)
            .animation(.easeInOut(duration: 0.5), value: model.state)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { model.tapped() }
    }

    private var glow: Color { model.state == .needsYou ? Memnox.Palette.sky : Memnox.Palette.primary }
}

/// Every session at a glance: the one in focus on the left with what it is doing, the rest as pills.
private struct Overview: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        HStack(spacing: 10) {
            IslandCard(veil: veil) {
                VStack(alignment: .leading, spacing: 2) {
                    if let card = model.focusCard {
                        HStack(spacing: 7) {
                            Circle().fill(IslandPalette.color(card.agent)).frame(width: 8, height: 8)
                            Text(card.title)
                                .font(Memnox.sans(14, .semibold))
                                .foregroundStyle(Color.white)
                                .lineLimit(1)
                        }
                        Text(card.subtitle)
                            .font(Memnox.sans(12))
                            .foregroundStyle(Color.white.opacity(0.45))
                            .lineLimit(1)
                            .padding(.leading, 15)
                        StepRoll(steps: meaningful(model.focused?.steps ?? []), thinking: card.thinking)
                    }
                }
                .padding(.leading, 102)
                .padding(.trailing, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(width: 322)
            .contentShape(RoundedRectangle(cornerRadius: 20))
            .onTapGesture {
                model.detail = true
                model.settle()
            }
            .help("See what it is changing")
            IslandCard(veil: nil) {
                VStack(spacing: 2) {
                    ForEach(Array(model.cards.prefix(4).enumerated()), id: \.element.sessionId) { index, card in
                        SessionRow(
                            card: card,
                            focused: card.sessionId == model.focusCard?.sessionId,
                            preview: { model.focus(card.sessionId) },
                            open: { model.openWindow(card.sessionId, card.host) }
                        )
                        .opacity(model.revealed ? 1 : 0)
                        .offset(y: model.revealed ? 0 : 6)
                        .animation(
                            .spring(response: 0.42, dampingFraction: 0.8).delay(0.22 + Double(index) * 0.035),
                            value: model.revealed
                        )
                    }
                    Spacer(minLength: 0)
                }
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .inset(model.notch)
    }

    private var veil: Color? {
        guard let card = model.focusCard else { return nil }
        if (model.focused?.waitingOnYou ?? 0) > 0 { return IslandPalette.amber.opacity(0.42) }
        return card.isWorking ? IslandPalette.color(card.agent).opacity(0.32) : nil
    }
}

/// The last few things a session did, the newest bright and shimmering while it works, rolling up as more arrive.
private struct StepRoll: View {
    let steps: [SessionViewStep]
    let thinking: Bool

    var body: some View {
        let shown = Array(steps.suffix(3))
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.at) { index, step in
                let current = index == shown.count - 1
                HStack(spacing: 9) {
                    Image(systemName: stepIcon(step))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(stepTint(step, current: current))
                        .frame(width: 14)
                    if current && thinking {
                        Shimmer(text: stepText(step))
                    } else {
                        Text(stepText(step))
                            .font(Memnox.sans(current ? 14 : 13, current ? .medium : .regular))
                            .foregroundStyle(current ? IslandPalette.soft : IslandPalette.quiet)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(height: 30)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if shown.isEmpty {
                Text(thinking ? "Thinking" : "Nothing done yet")
                    .font(Memnox.sans(13))
                    .foregroundStyle(IslandPalette.quiet)
                    .frame(height: 30)
            }
        }
        .frame(height: 96, alignment: .bottom)
        .clipped()
        .mask(
            LinearGradient(
                stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.28), .init(color: .black, location: 1)],
                startPoint: .top, endPoint: .bottom
            )
        )
        .animation(.timingCurve(0.3, 0.9, 0.3, 1, duration: 0.45), value: shown.map(\.at))
    }
}

/// A line whose brightness sweeps across it, the way a task in progress reads at a glance.
private struct Shimmer: View {
    let text: String

    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.2) / 2.2
            Text(text)
                .font(Memnox.sans(14, .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.45), location: max(0, phase - 0.25)),
                            .init(color: Color.white, location: phase),
                            .init(color: Color.white.opacity(0.45), location: min(1, phase + 0.25)),
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
        }
    }
}

/// One session in the list: its logo, what it is on, which agent and how lately, and whether it is working.
/// Resting the pointer on it shows it on the left; clicking it goes to its own window.
private struct SessionRow: View {
    let card: SessionCard
    let focused: Bool
    let preview: () -> Void
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Logo(card: card, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(card.title)
                        .font(Memnox.sans(12.5, .semibold))
                        .foregroundStyle(Color.white.opacity(focused ? 1 : 0.85))
                        .lineLimit(1)
                    Text(card.subtitle)
                        .font(Memnox.sans(11))
                        .foregroundStyle(Color.white.opacity(0.4))
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if focused {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .transition(.opacity.combined(with: .scale(scale: 0.6)))
                } else if card.isWorking {
                    Circle().fill(Memnox.Palette.sky).frame(width: 7, height: 7).modifier(Pulse())
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(focused ? 0.08 : 0)))
            .contentShape(RoundedRectangle(cornerRadius: 11))
            .animation(.easeOut(duration: 0.15), value: focused)
        }
        .buttonStyle(Pressable())
        .onHover { inside in if inside { preview() } }
        .help("Go to this session")
    }
}

/// An agent's logo in a disc of its own colour.
private struct Logo: View {
    let card: SessionCard
    let size: CGFloat

    var body: some View {
        AgentLogo(kind: IslandPalette.kind(card.agent), name: card.agentName)
            .frame(width: size * 0.56, height: size * 0.56)
            .frame(width: size, height: size)
            .background(Circle().fill(IslandPalette.color(card.agent)))
    }
}

/// One session up close: who it is and what it did on the left, the code it is writing on the right.
private struct SessionDetail: View {
    @ObservedObject var model: IslandModel
    let session: SessionView

    var body: some View {
        HStack(spacing: 10) {
            IslandCard(veil: session.thinking ? IslandPalette.color(session.agent).opacity(0.3) : nil) {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 66)
                    Text(session.agentName)
                        .font(Memnox.sans(15, .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    Text(session.task ?? session.repository ?? session.state)
                        .font(Memnox.sans(12))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .lineLimit(1)
                        .padding(.bottom, 10)
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(meaningful(session.steps).suffix(4).reversed().enumerated()), id: \.offset) { index, step in
                            StepLine(step: step, latest: index == 0, working: index == 0 && session.thinking)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(width: 220)
            .contentShape(RoundedRectangle(cornerRadius: 20))
            .onTapGesture {
                if let card = model.focusCard { model.openWindow(card.sessionId, card.host) }
            }
            .help("Open this session")
            CodePanel(session: session)
        }
        .inset(model.notch)
    }
}

/// One thing the session did, for the detail card's list.
private struct StepLine: View {
    let step: SessionViewStep
    let latest: Bool
    let working: Bool

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if working {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: stepIcon(step))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(stepTint(step, current: latest))
                }
            }
            .frame(width: 14)
            Text(stepText(step))
                .font(Memnox.sans(12, latest ? .semibold : .regular))
                .foregroundStyle(latest ? Color.white : IslandPalette.quiet)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

/// The file the session changed most, as an editor tab and its changed lines; the files alone when no lines can be read.
private struct CodePanel: View {
    let session: SessionView

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let excerpt = session.excerpt {
                tab(excerpt.path)
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(excerpt.lines.prefix(10).enumerated()), id: \.offset) { index, line in
                        CodeLine(number: index + 1, line: line)
                    }
                }
                .padding(.vertical, 8)
                .animation(.easeOut(duration: 0.25), value: excerpt.lines)
            } else if !session.files.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(session.files.prefix(6).enumerated()), id: \.offset) { _, file in
                        HStack(spacing: 8) {
                            Text(name(file.path)).font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Color.white).lineLimit(1)
                            Spacer(minLength: 8)
                            counts(file.added, file.removed)
                        }
                    }
                }
                .padding(16)
            } else {
                Text("Nothing changed yet")
                    .font(Memnox.sans(13))
                    .foregroundStyle(IslandPalette.quiet)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(hex: 0x0D0E10)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.035), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func tab(_ path: String) -> some View {
        HStack(spacing: 8) {
            Text(kind(path))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 3).fill(Memnox.Palette.primary))
            Text(name(path)).font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white)
            Spacer(minLength: 8)
            Text(path).font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.3))
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(Color.white.opacity(0.03))
    }

    private func counts(_ added: Int?, _ removed: Int?) -> some View {
        HStack(spacing: 6) {
            if let added { Text("+\(added)").foregroundStyle(IslandPalette.green) }
            if let removed { Text("\u{2212}\(removed)").foregroundStyle(IslandPalette.red) }
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
    }

    private func name(_ path: String) -> String { (path as NSString).lastPathComponent }

    /// The extension as a badge, the way an editor tab marks a file's language.
    private func kind(_ path: String) -> String {
        let ext = (path as NSString).pathExtension
        return ext.isEmpty ? "TXT" : String(ext.prefix(3)).uppercased()
    }
}

/// One changed line with a gutter number: green for what it added, red for what it took out.
private struct CodeLine: View {
    let number: Int
    let line: String

    var body: some View {
        let added = line.hasPrefix("+")
        let tint = added ? IslandPalette.green : IslandPalette.red
        HStack(spacing: 12) {
            Text("\(number)")
                .foregroundStyle(Color.white.opacity(0.2))
                .frame(width: 18, alignment: .trailing)
            Text(String(line.dropFirst()))
                .foregroundStyle(added ? IslandPalette.soft : Color.white.opacity(0.4))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.09))
        .overlay(alignment: .leading) { Rectangle().fill(tint.opacity(0.7)).frame(width: 2) }
    }
}

/// Opened with nothing running.
private struct Empty: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        IslandCard(veil: IslandPalette.indigo.opacity(0.25)) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Nothing is running right now.")
                    .font(Memnox.sans(15, .medium))
                    .foregroundStyle(Color.white)
                Button { model.tapped() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform")
                        Text("Talk to Memnox")
                    }
                }
                .buttonStyle(IslandButton(primary: true))
            }
            .padding(.leading, 112)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .inset(model.notch)
    }
}

/// The held call: who is waiting, the command, and the three answers it takes.
private struct Held: View {
    @ObservedObject var model: IslandModel
    let card: HeldCard

    var body: some View {
        IslandCard(veil: IslandPalette.amber.opacity(0.42)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Circle().fill(IslandPalette.color(card.agent)).frame(width: 8, height: 8).modifier(Pulse())
                    Text(card.who).font(Memnox.sans(14, .semibold)).foregroundStyle(Color.white)
                    Text(card.why ?? "is waiting on you")
                        .font(Memnox.sans(13))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .lineLimit(1)
                }
                Text(card.what)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                HStack(spacing: 8) {
                    Button("Deny") { press(.deny) }.buttonStyle(IslandButton(primary: false))
                    Button { press(.session) } label: { touchID("Allow this session") }
                        .buttonStyle(IslandButton(primary: false))
                    Button { press(.once) } label: { touchID("Allow once") }
                        .buttonStyle(IslandButton(primary: true))
                }
                .disabled(model.answering)
                .opacity(model.answering ? 0.55 : 1)
            }
            .padding(.leading, 98)
            .padding(.trailing, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .inset(model.notch)
    }

    private func press(_ answer: HoldAnswer) {
        model.answering = answer != .deny
        model.answer(card.subject, answer, card.summary)
    }

    /// Every allow is signed, so the button says so before it is pressed.
    private func touchID(_ title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "touchid").font(.system(size: 12, weight: .medium))
            Text(title)
        }
    }
}

/// A session that just finished, with its summary and a way back to it.
private struct Finished: View {
    @ObservedObject var model: IslandModel
    let card: FinishedCard

    var body: some View {
        IslandCard(veil: IslandPalette.green.opacity(0.5)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(IslandPalette.green)
                    Text(card.who).font(Memnox.sans(14, .semibold)).foregroundStyle(Color.white)
                    Text("finished").font(Memnox.sans(13)).foregroundStyle(Color.white.opacity(0.5))
                }
                Text(card.summary)
                    .font(Memnox.sans(13))
                    .foregroundStyle(IslandPalette.soft)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if let session = card.sessionId {
                        Button("Open") { model.openWindow(session, card.host) }.buttonStyle(IslandButton(primary: false))
                    }
                    Button("OK") {
                        model.finished = nil
                        model.settle()
                    }
                    .buttonStyle(IslandButton(primary: true))
                }
            }
            .padding(.leading, 98)
            .padding(.trailing, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .inset(model.notch)
    }
}

/// A dark card inside the open island, with a glow rising from its bottom edge in the colour of what is happening.
struct IslandCard<Content: View>: View {
    let veil: Color?
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        content
            .background(
                shape.fill(IslandPalette.card)
                    .overlay {
                        // A fixed reach rather than one measured, since measuring inside a panel's own sizing pass crashed it.
                        if let veil {
                            RadialGradient(
                                colors: [veil, veil.opacity(0)],
                                center: UnitPoint(x: 0.5, y: 1.3),
                                startRadius: 0,
                                endRadius: 360
                            )
                            .transition(.opacity)
                        }
                    }
                    .clipShape(shape)
                    .animation(.easeInOut(duration: 0.4), value: veil)
            )
            .overlay(shape.strokeBorder(Color.white.opacity(0.035), lineWidth: 1))
    }
}

private extension View {
    /// The content area of an open island: below the header, ten in from the other three sides.
    func inset(_ notch: NotchGeometry) -> some View {
        padding(.top, Island.top(notch))
            .padding([.horizontal, .bottom], 10)
    }
}

extension Color {
    /// The colour lifted a quarter of the way to white, so a label reads on its own tint.
    var liftedTowardWhite: Color {
        let base = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return Color(
            red: base.redComponent + (1 - base.redComponent) * 0.25,
            green: base.greenComponent + (1 - base.greenComponent) * 0.25,
            blue: base.blueComponent + (1 - base.blueComponent) * 0.25
        )
    }
}

private extension SessionCard {
    var isWorking: Bool { state == "working" || thinking }

    /// What it is on, which is what tells two sessions of the same agent apart.
    var title: String { task ?? repository ?? agentName }

    /// The agent, where it is if the title did not say, and how lately it did anything.
    var subtitle: String {
        var parts: [String] = []
        if title != agentName { parts.append(agentName) }
        if let repository, repository != title { parts.append(repository) }
        parts.append(isWorking ? "working" : ago(lastActive) ?? state)
        return parts.joined(separator: " \u{00B7} ")
    }
}

/// How long ago, the way a person says it.
private func ago(_ iso: String?) -> String? {
    guard let iso else { return nil }
    let precise = ISO8601DateFormatter()
    precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = precise.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return nil }
    let minutes = Int(Date().timeIntervalSince(date) / 60)
    if minutes < 1 { return "just now" }
    if minutes < 60 { return "\(minutes) min ago" }
    if minutes < 24 * 60 { return "\(minutes / 60) h ago" }
    return "\(minutes / (24 * 60)) d ago"
}

/// The steps worth reading: what it changed and ran, leaving out the hosts it called unless that is all
/// it did, and one line for the same thing done several times running.
private func meaningful(_ steps: [SessionViewStep]) -> [SessionViewStep] {
    let work = steps.filter { $0.surface != "network" }
    var kept: [SessionViewStep] = []
    for step in work.isEmpty ? steps : work {
        if let last = kept.last, stepText(last) == stepText(step) { kept.removeLast() }
        kept.append(step)
    }
    return kept
}

/// A step as a line: a host it called by its own name, and anything else as the runtime wrote it.
private func stepText(_ step: SessionViewStep) -> String {
    guard step.surface == "network", let target = step.text.split(separator: " ").last else {
        // A full path says nothing a glance can use; its last part is the file or folder.
        return step.text.split(separator: " ", omittingEmptySubsequences: false).map { word in
            word.contains("/") ? (String(word) as NSString).lastPathComponent : String(word)
        }.joined(separator: " ")
    }
    let bare = target.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
    let host = bare.split(separator: "/").first.map(String.init) ?? bare
    let labels = host.split(separator: ".")
    let site = labels.count > 2 ? labels.suffix(2).joined(separator: ".") : host
    return "Reached \(site)"
}

private func stepIcon(_ step: SessionViewStep) -> String {
    if step.refused == true { return "hand.raised" }
    if step.failed == true { return "xmark.circle" }
    switch step.surface {
    case "filesystem": return step.text.hasPrefix("Read") ? "doc.text" : "pencil"
    case "shell": return "apple.terminal"
    case "git": return "arrow.triangle.branch"
    case "network": return "globe"
    case "mcp": return "puzzlepiece"
    default: return "circle"
    }
}

private func stepTint(_ step: SessionViewStep, current: Bool) -> Color {
    if step.refused == true { return IslandPalette.amber }
    if step.failed == true { return IslandPalette.red }
    return current ? Color.white : IslandPalette.quiet
}

/// How content leaves and arrives: out quickly with a blur, in a moment later once the island has started to grow.
private struct ContentFade: ViewModifier {
    let shown: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .blur(radius: shown ? 0 : 8)
            .scaleEffect(shown ? 1 : 0.97)
    }
}

extension AnyTransition {
    /// Coucou's timing: out in 160 ms, in over 300 ms after a 160 ms wait.
    static var islandContent: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: ContentFade(shown: false), identity: ContentFade(shown: true))
                .animation(.easeOut(duration: 0.3).delay(0.16)),
            removal: .modifier(active: ContentFade(shown: false), identity: ContentFade(shown: true))
                .animation(.easeIn(duration: 0.16))
        )
    }
}

/// A pill button: white for the answer that lets something happen, a faint fill for the rest; it gives a little when pressed.
struct IslandButton: ButtonStyle {
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Memnox.sans(12.5, .medium))
            .foregroundStyle(primary ? IslandPalette.primaryText : Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(primary ? IslandPalette.primaryFill : Color.white.opacity(configuration.isPressed ? 0.15 : 0.09)))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// The press for anything clickable that is not a labelled button.
private struct Pressable: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// The notch's own outline grown downward: square along the top, flowing out into the screen edge at
/// either side with a concave curve, and rounded at the bottom.
struct NotchShape: Shape {
    var flare: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(flare, bottomRadius) }
        set {
            flare = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let r = min(bottomRadius, max(0, (rect.height - flare) / 2), max(0, (rect.width - 2 * flare) / 2))
        let left = rect.minX + flare
        let right = rect.maxX - flare
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: left, y: rect.minY + flare), control: CGPoint(x: left, y: rect.minY))
        path.addLine(to: CGPoint(x: left, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: left + r, y: rect.maxY), control: CGPoint(x: left, y: rect.maxY))
        path.addLine(to: CGPoint(x: right - r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: right, y: rect.maxY - r), control: CGPoint(x: right, y: rect.maxY))
        path.addLine(to: CGPoint(x: right, y: rect.minY + flare))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: right, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// The Metal orb, hosted as it is so the renderer keeps drawing at whatever size the island gives it.
private struct OrbSurface: NSViewRepresentable {
    let view: MTKView
    func makeNSView(context: Context) -> MTKView { view }
    func updateNSView(_ nsView: MTKView, context: Context) {}
}

/// Seven bars that move with the voice in or out, and rest low when neither is speaking.
private struct Waveform: View {
    let loudness: () -> Float
    let state: VoiceState
    @StateObject private var levels = Levels()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            let values = levels.next(at: timeline.date, heard: live ? loudness() : 0.05)
            HStack(alignment: .center, spacing: 3) {
                ForEach(values.indices, id: \.self) { index in
                    Capsule()
                        .fill(Memnox.Palette.sky.opacity(0.45 + Double(values[index]) * 0.55))
                        .frame(width: 3, height: 4 + CGFloat(values[index]) * 12)
                }
            }
        }
    }

    private var live: Bool { state == .listening || state == .speaking }
}

/// The waveform's recent levels, kept outside the view so redrawing never resets them.
@MainActor
private final class Levels: ObservableObject {
    private var history = [Float](repeating: 0.05, count: 7)
    private var last = Date.distantPast

    func next(at moment: Date, heard: Float) -> [Float] {
        if moment.timeIntervalSince(last) >= 1.0 / 30 {
            last = moment
            history.removeFirst()
            history.append(min(max(heard, 0.05), 1))
        }
        return history
    }
}

/// A side to side shake that dies away, played once each time the count goes up.
private struct Shake: GeometryEffect {
    var times: CGFloat
    var animatableData: CGFloat {
        get { times }
        set { times = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let progress = times - floor(times)
        let offset = sin(progress * .pi * 6) * 9 * (1 - progress)
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}

/// A little swell and back, played once each time the count goes up, hung from the top edge.
private struct Hop: GeometryEffect {
    var times: CGFloat
    var animatableData: CGFloat {
        get { times }
        set { times = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let progress = times - floor(times)
        let lift = sin(progress * .pi) * 0.05
        let scale = CGAffineTransform(translationX: size.width / 2, y: 0)
            .scaledBy(x: 1 + lift, y: 1 + lift)
            .translatedBy(x: -size.width / 2, y: 0)
        return ProjectionTransform(scale)
    }
}

/// A slow breath on the held call's dot, so the eye finds what is waiting.
private struct Pulse: ViewModifier {
    func body(content: Content) -> some View {
        TimelineView(.animation) { timeline in
            let breath = (sin(timeline.date.timeIntervalSinceReferenceDate * .pi / 0.9) + 1) / 2
            content
                .scaleEffect(1 + 0.35 * breath)
                .opacity(1 - 0.4 * breath)
        }
    }
}
