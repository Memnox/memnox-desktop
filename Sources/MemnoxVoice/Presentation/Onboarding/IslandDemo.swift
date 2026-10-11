import AppKit
import MetalKit
import MemnoxVoiceCore
import SwiftUI

/// The real island, its view, its model and its particle orb, played through what it does with made up sessions and
/// no daemon, so a first run shows the product rather than a picture of it. It drives the model the way `IslandPanel`
/// does and never answers anything: its buttons only move the tour along.
@MainActor
final class IslandDemo: ObservableObject {
    /// What the demo plays; one tour now, kept as a type so another can be added without changing callers.
    enum Tour {
        /// Every part in turn: sessions, answering, a rule, a reply in their own tools, catching up.
        case highlights
    }

    /// The part the highlights tour is playing now, so the step beside it can light the same one.
    @Published private(set) var chapter: Highlight?

    let model = IslandModel()
    let orb: MTKView
    private let renderer: OrbRenderer?
    private let level = Level()
    private var running: Task<Void, Never>?
    private var steps: [String] = []
    private var lines: [String] = []

    /// The voice level the orb and the waveform read every frame, written here as somebody would talk.
    private final class Level: @unchecked Sendable {
        var value: Float = 0
    }

    private enum Pace {
        static let short: TimeInterval = 1.2
        static let beat: TimeInterval = 2
        static let dwell: TimeInterval = 4.5
        static let perWord: TimeInterval = 0.3
        static let perChunk: TimeInterval = 0.12
        static let betweenSteps: TimeInterval = 1.3
        static let frame: TimeInterval = 0.033
        static let wordsPerChunk = 3
    }

    private enum Wave {
        static let base = 0.35
        static let slow = (amplitude: 0.3, rate: 9.0)
        static let fast = (amplitude: 0.25, rate: 23.0)
    }

    /// The notch of a 14 inch MacBook Pro, so the island is drawn the size it is on the real screen.
    static let notch = NotchGeometry(width: 185, height: 32, hasNotch: true)

    init() {
        orb = MTKView(frame: NSRect(x: 0, y: 0, width: 64, height: 64), device: MTLCreateSystemDefaultDevice())
        orb.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        orb.preferredFramesPerSecond = 60
        orb.wantsLayer = true
        orb.layer?.isOpaque = false
        renderer = OrbRenderer(view: orb)
        let level = level
        renderer?.loudness = { level.value }
        orb.delegate = renderer
        model.notch = Self.notch
        model.liveWords = true
        // The buttons on the demo's cards only move it along; nothing here can answer a real call.
        model.answer = { [weak self] card, _ in self?.release(card.subject) }
        model.answerRule = { [weak self] _, _ in self?.clearRule() }
    }

    var loudness: () -> Float {
        let level = level
        return { level.value }
    }

    func play(_ tour: Tour) {
        running?.cancel()
        running = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.reset()
                await self.once(tour)
            }
        }
    }

    func stop() {
        running?.cancel()
        running = nil
        chapter = nil
    }

    private func once(_ tour: Tour) async {
        switch tour {
        case .highlights: await highlights()
        }
    }

    // MARK: Tours

    private func asking() async {
        model.cards = Self.sessions
        model.settle()
        await pause(Pace.beat)
        hold(Self.heldCall)
        await pause(Pace.dwell)
        model.pressed = Self.heldCall?.subject
        model.answering = true
        renderer?.react(.allowed)
        await pause(Pace.short)
        release(Self.heldCall?.subject ?? "")
        await pause(Pace.beat)
        if let done = Self.done {
            model.finished = FinishedCard(done)
            model.settle()
            model.hops += 1
            renderer?.react(.burst)
            await pause(Pace.dwell)
            model.finished = nil
            model.settle()
        }
        await pause(Pace.short)
    }

    private func sessionsTour() async {
        model.cards = Self.sessions
        model.settle()
        await pause(Pace.short)
        model.opened = true
        model.focusId = Self.sessions.first?.sessionId
        model.focused = view()
        model.settle()
        await pause(Pace.dwell)
        model.detail = true
        model.settle()
        for (step, change) in zip(Self.allSteps, Self.allLines) {
            steps.append(step)
            lines.append(contentsOf: change)
            model.focused = view()
            await pause(Pace.betweenSteps)
        }
        await pause(Pace.beat)
        model.detail = false
        model.settle()
        await pause(Pace.beat)
        model.opened = false
        model.settle()
        await pause(Pace.short)
    }

    private func highlights() async {
        chapter = .sessions
        await sessionsTour()
        chapter = .answer
        await asking()
        chapter = .rule
        await sayRule()
        chapter = .tools
        await replyAsThem()
        chapter = .catchUp
        await catchUp()
    }

    /// The rule half of the talking tour: said, drawn as its card, and kept.
    private func sayRule() async {
        model.cards = Self.sessions
        present()
        show(.listening)
        model.ruling = true
        model.settle()
        await say(Self.ruleSaid)
        model.ruling = false
        asked(Self.ruleSaid)
        show(.thinking)
        await pause(Pace.short)
        model.rule = RuleCard(subject: Self.ruleSubject, draft: Self.rule)
        model.ruleScope = Self.rule.suggestedScope?.id
        model.settle()
        await pause(Pace.dwell)
        clearRule()
        renderer?.react(.settle)
        replied()
        dismiss()
        await pause(Pace.short)
    }

    /// Asked out loud, GitHub's icon under the notch, signed in once, then the comment drawn as GitHub draws it and sent.
    private func replyAsThem() async {
        model.cards = Self.sessions
        present()
        show(.listening)
        await say(Self.replySaid)
        asked(Self.replySaid)
        show(.thinking)
        await pause(Pace.short)
        model.signIns = [Self.githubSignIn]
        show(.speaking)
        await stream("Tap GitHub to let me use it, once.")
        replied()
        await pause(Pace.dwell)
        model.signIns = []
        model.signedIn = SignedInCard(notice: Self.signedInGitHub)
        model.settle()
        await pause(Pace.beat)
        model.signedIn = nil
        for draft in Self.drafts where !Task.isCancelled {
            model.work = WorkCard(subject: Self.workSubject, draft: draft)
            model.settle()
            await pause(Pace.dwell)
            model.sending = true
            await pause(Pace.short)
            model.work = nil
            model.sending = false
            renderer?.react(.allowed)
            model.settle()
            await pause(Pace.short)
        }
        dismiss()
        await pause(Pace.short)
    }

    private func catchUp() async {
        model.cards = Self.sessions
        present()
        show(.listening)
        await say(Self.catchUpSaid)
        asked(Self.catchUpSaid)
        show(.thinking)
        await pause(Pace.short)
        show(.speaking)
        await stream(Self.catchUpAnswer)
        replied()
        await talk(for: Pace.beat)
        dismiss()
        await pause(Pace.beat)
    }

    // MARK: Driving the model as IslandPanel does

    private func reset() {
        steps = []
        lines = []
        model.waiting = WaitingCalls<HeldCard>()
        model.pressed = nil
        model.answering = false
        model.finished = nil
        model.rule = nil
        model.ruling = false
        model.work = nil
        model.signIns = []
        model.signedIn = nil
        model.sending = false
        model.opened = false
        model.detail = false
        model.focused = nil
        model.history = History()
        model.cards = []
        dismiss()
    }

    private func present() {
        model.talkingSince = Date()
        model.active = true
        model.settle()
    }

    private func dismiss() {
        model.active = false
        model.caption = ""
        model.heard = ""
        model.talkingSince = nil
        model.state = .idle
        renderer?.state = .idle
        model.settle()
    }

    private func show(_ state: VoiceState) {
        renderer?.state = state
        model.state = state
        if state == .listening { model.heard = "" }
        model.settle()
    }

    private func asked(_ words: String) {
        model.history.ask(words, at: Date())
        model.heard = ""
        model.settle()
    }

    private func replied() {
        model.history.end(at: Date(), failure: nil)
        model.settle()
    }

    private func hold(_ event: DaemonEvent?) {
        guard let event else { return }
        let card = HeldCard(event)
        model.waiting.add(card, subject: card.subject, machine: card.machine)
        renderer?.waiting = true
        model.settle()
    }

    private func release(_ subject: String) {
        _ = model.waiting.remove(subject)
        model.pressed = nil
        model.answering = false
        renderer?.waiting = !model.waiting.isEmpty
        model.settle()
    }

    private func clearRule() {
        model.rule = nil
        model.ruleScope = nil
        model.settle()
    }

    /// Words arriving one at a time, as the recognizer hands them over, with the voice level moving under them.
    private func say(_ sentence: String) async {
        var heard: [Substring] = []
        for word in sentence.split(separator: " ") where !Task.isCancelled {
            heard.append(word)
            model.heard = heard.joined(separator: " ")
            model.settle()
            await talk(for: Pace.perWord)
        }
    }

    /// The answer streamed a few words at a time, as the brain's chunks arrive.
    private func stream(_ answer: String) async {
        let words = answer.split(separator: " ", omittingEmptySubsequences: false)
        var index = 0
        while index < words.count, !Task.isCancelled {
            let chunk = words[index..<min(index + Pace.wordsPerChunk, words.count)].joined(separator: " ")
            index += Pace.wordsPerChunk
            model.history.reply(index < words.count ? chunk + " " : chunk)
            await talk(for: Pace.perChunk)
        }
    }

    private func talk(for seconds: TimeInterval) async {
        let start = Date()
        while Date().timeIntervalSince(start) < seconds, !Task.isCancelled {
            let t = Date().timeIntervalSinceReferenceDate
            level.value = Float(Wave.base + Wave.slow.amplitude * sin(t * Wave.slow.rate) + Wave.fast.amplitude * sin(t * Wave.fast.rate))
            await pause(Pace.frame)
        }
        level.value = 0
    }

    private func pause(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// The session in focus as the daemon would describe it, with the steps and lines shown so far.
    private func view() -> SessionView? {
        guard let card = Self.sessions.first else { return nil }
        let stepJSON = steps.enumerated().map { index, text in
            #"{"at":"2026-10-03T12:00:\#(String(format: "%02d", index))Z","surface":"\#(text.hasPrefix("Ran") ? StepSurface.shell.rawValue : StepSurface.filesystem.rawValue)","text":"\#(text)"}"#
        }.joined(separator: ",")
        let lineJSON = lines.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }.joined(separator: ",")
        let excerpt = lines.isEmpty ? "" : #","excerpt":{"path":"src/billing/invoice.ts","lines":[\#(lineJSON)]}"#
        let json = #"{"sessionId":"\#(card.sessionId)","agent":"\#(card.agent ?? "")","agentName":"\#(card.agentName)","task":"add VAT to invoices","state":"working","thinking":true,"repository":"shop","waitingOnYou":0,"helpers":[],"steps":[\#(stepJSON)],"files":[{"path":"src/billing/invoice.ts","added":3,"removed":1}]\#(excerpt)}"#
        return try? JSONDecoder().decode(SessionView.self, from: Data(json.utf8))
    }

    // MARK: The made up product, the same as the island preview's

    private static let sessions: [SessionCard] = [
        SessionCard(sessionId: "ses_shop", agent: "claude-code", agentName: "Claude Code", task: "add VAT to invoices",
                    state: SessionState.working.rawValue, thinking: true, repository: "shop"),
        SessionCard(sessionId: "ses_api", agent: "codex-cli", agentName: "Codex", task: "fix the flaky test",
                    state: SessionState.working.rawValue, thinking: true, repository: "api"),
        SessionCard(sessionId: "ses_site", agent: "cursor", agentName: "Cursor", task: "landing copy",
                    state: SessionState.open.rawValue, repository: "site"),
    ]

    private static let allSteps = [
        "Read src/billing/types.ts", "Edited src/billing/invoice.ts", "Ran npm test", "Edited src/billing/invoice.ts",
    ]

    private static let allLines: [[String]] = [
        [], ["-const TVA = 0.2", "+const TVA = 0.196"], [],
        ["+export function total(items: Item[]) {", "+  const sum = items.reduce((s, i) => s + i.price, 0)", "+  return sum * (1 + TVA)", "+}"],
    ]

    private static let ruleSubject = "prp_onboarding"
    private static let ruleSaid = "Never let any agent push to main without asking me first"

    private static let rule = RuleDraft(
        summary: "ask git.push on main", effect: RuleEffect.ask.rawValue, action: "git.push", branches: ["main"],
        reason: "pushes to main go through the person first",
        scopes: [
            RuleScope(id: RuleScopeKind.machine.rawValue, kind: RuleScopeKind.machine.rawValue, label: "This Mac"),
            RuleScope(id: "repository-1", kind: RuleScopeKind.repository.rawValue, label: "shop", folder: "/Users/me/shop", suggested: true),
            RuleScope(id: RuleScopeKind.team.rawValue, kind: RuleScopeKind.team.rawValue, label: "The team"),
        ]
    )

    private static let replySaid = "Reply on pull request 412 on GitHub, fixed in the last push"
    private static let catchUpSaid = "What did my agents do while I was out"
    private static let catchUpAnswer = "Codex fixed the flaky checkout test and the suite passes. Claude is still adding VAT in shop, waiting on nobody."
    private static let workSubject = "prp_onboarding_work"
    private static let githubSignIn = ToolSignIn(toolkit: "github", url: "https://example.com/github")
    private static let mine = AccountCheck.matched.rawValue

    private static let signedInGitHub = SignedInNotice(
        toolkit: "github", account: WorkAccount(key: "42", handle: "you", check: mine)
    )

    /// The reply asked for, then a Slack DM, so the preview shows the draft drawn the way each tool draws it.
    private static let drafts: [WorkDraft] = [
        WorkDraft(
            toolkit: "github", tool: "GITHUB_CREATE_A_REVIEW_COMMENT_FOR_A_PULL_REQUEST", kind: WorkDraftKind.comment.rawValue,
            account: WorkAccount(key: "42", handle: "you", check: mine), where: "acme/shop#412",
            body: "Fixed in the last push: the total now includes VAT."
        ),
        WorkDraft(
            toolkit: "slack", tool: "SLACK_SEND_MESSAGE", kind: WorkDraftKind.message.rawValue,
            account: WorkAccount(key: "U1", handle: "you", check: mine), to: ["Sara"],
            body: "The VAT fix is in review, link in the thread."
        ),
    ]

    private static let heldCall: DaemonEvent? = event(
        #"{"kind":"held","subject":"apr_onboarding","agent":"claude-code","agentName":"Claude Code","summary":"push to main","what":"git push origin main","why":"wants to push to main","at":"2026-10-03T12:00:00Z"}"#
    )

    private static let done: DaemonEvent? = event(
        #"{"kind":"notice","notice":"finished","subject":"ses_api","agent":"codex-cli","agentName":"Codex","summary":"The flaky checkout test is fixed and the suite passes.","sessionId":"ses_api","at":"2026-10-03T12:05:00Z"}"#
    )

    private static func event(_ json: String) -> DaemonEvent? {
        try? JSONDecoder().decode(DaemonEvent.self, from: Data(json.utf8))
    }
}

/// The real island view over the demo's model, at the size it has on the screen.
struct IslandDemoView: View {
    @ObservedObject var demo: IslandDemo

    var body: some View {
        IslandView(model: demo.model, orb: demo.orb, loudness: demo.loudness)
            .frame(width: Island.window.width, height: Island.window.height, alignment: .top)
            .environment(\.colorScheme, .dark)
    }
}

/// Hosts a SwiftUI design at its own size and scales it down to fit, in AppKit, so a Metal view inside it scales with
/// the rest rather than drawing at full size where SwiftUI's own scaling would leave it.
struct DesignFit<Content: View>: NSViewRepresentable {
    let size: CGSize
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> FitView {
        FitView(host: NSHostingView(rootView: AnyView(content())), design: size)
    }

    func updateNSView(_ view: FitView, context: Context) {
        view.host.rootView = AnyView(content())
    }

    // The room offered, never the design's own size, which would push the window's layout past its edge.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: FitView, context: Context) -> CGSize? {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? size.width
        let height = proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? size.height
        return CGSize(width: width, height: height)
    }

    /// Lays its one subview out at the design size and sets its bounds so it draws scaled to fit, centred.
    final class FitView: NSView {
        let host: NSHostingView<AnyView>
        private let scaler = NSView()
        private let design: CGSize

        init(host: NSHostingView<AnyView>, design: CGSize) {
            self.host = host
            self.design = design
            super.init(frame: .zero)
            host.sizingOptions = []
            scaler.addSubview(host)
            addSubview(scaler)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        // The picture is to look at, so clicks go to whatever is behind it.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }

        override func layout() {
            super.layout()
            let scale = min(bounds.width / design.width, bounds.height / design.height)
            guard scale > 0, scale.isFinite else { return }
            let fitted = CGSize(width: design.width * scale, height: design.height * scale)
            scaler.frame = CGRect(x: (bounds.width - fitted.width) / 2, y: (bounds.height - fitted.height) / 2,
                                  width: fitted.width, height: fitted.height)
            scaler.bounds = CGRect(origin: .zero, size: design)
            host.frame = CGRect(origin: .zero, size: design)
        }
    }
}
