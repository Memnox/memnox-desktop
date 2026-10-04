import Foundation
import MemnoxVoiceCore

/// Walks the island through every state on the real notch, with made up sessions and no daemon,
/// so it can be seen and judged. Started with `open -n build/Memnox.app --args --island-preview`.
@MainActor
final class IslandPreview {
    static let flag = "--island-preview"
    static var requested: Bool { CommandLine.arguments.contains(flag) }

    /// A made up voice level, so the orb and the waveform move as they would with somebody talking.
    /// Read by the renderer every frame on the main thread, and written only here, on the main actor.
    nonisolated(unsafe) static var level: Float = 0
    private let panel: IslandPanel
    private var tour: Task<Void, Never>?
    private var cards: [SessionCard] = []
    private var steps: [String] = []
    private var lines: [String] = []

    /// How long the tour holds each state, slow enough to judge one before the next arrives.
    private enum Tour {
        static let beforeSessions: TimeInterval = 3
        /// Long enough to look over a whole surface: the sessions, the detail, a held call.
        static let dwell: TimeInterval = 6
        static let betweenSteps: TimeInterval = 1.6
        static let beat: TimeInterval = 2
        static let beforeOrb: TimeInterval = 1.5
        static let listening: TimeInterval = 2.5
        static let answering: TimeInterval = 4
        static let afterDismiss: TimeInterval = 1
        static let finishedDwell: TimeInterval = 6.5
        /// About the pace a person speaks at, three words a second.
        static let perWord: TimeInterval = 0.33
        /// About the pace a brain streams at, a few words in each chunk.
        static let perChunk: TimeInterval = 0.12
    }

    /// The made up voice: a resting level with a slow and a fast wave over it.
    private enum Wave {
        static let base = 0.35
        static let slowAmplitude = 0.3
        static let slowRate = 9.0
        static let fastAmplitude = 0.25
        static let fastRate = 23.0
        /// About thirty frames a second, as often as the level is worth changing.
        static let frameSeconds: TimeInterval = 0.033
    }

    private static let nanosecondsPerSecond: TimeInterval = 1_000_000_000
    /// A step that ran a command reads "Ran ...", and shows as shell work rather than a file.
    private static let shellStepPrefix = "Ran"
    /// Each step's seconds, two digits, so the timestamps are valid ISO 8601.
    private static let secondsFormat = "%02d"

    init(panel: IslandPanel) {
        self.panel = panel
        // The buttons only put the card away here, since there is no real call to answer.
        panel.wire(answer: { [weak panel] card, _ in panel?.release(card.subject) }, tapped: {})
        panel.wireConversation(
            openAnswer: { _ in },
            answerDraft: { [weak panel] card, _ in panel?.draftAnswered(card, .answered) },
            answerRule: { [weak panel] card, _ in panel?.ruleAnswered(card, .answered) },
            askAgain: { _ in }
        )
        panel.wireSessions(
            list: { [weak self] in self?.cards ?? [] },
            view: { [weak self] id in self?.view(id) },
            open: { _, _ in }
        )
    }

    func start() {
        tour = Task { [weak self] in
            while !Task.isCancelled {
                await self?.once()
            }
        }
    }

    private func once() async {
        cards = []
        steps = []
        lines = []
        await pause(Tour.beforeSessions)
        cards = Self.sessions
        await pause(Tour.dwell)
        panel.openIsland()
        for (step, line) in zip(Self.allSteps, Self.allLines) {
            steps.append(step)
            lines.append(contentsOf: line)
            await pause(Tour.betweenSteps)
        }
        panel.showDetail(true)
        await pause(Tour.dwell)
        panel.showDetail(false)
        await pause(Tour.beat)
        panel.closeIsland()
        await pause(Tour.beforeOrb)
        panel.present()
        panel.show(.listening, caption: "")
        await talk(for: Tour.listening)
        await say(Self.question)
        panel.asked(Self.question)
        panel.show(.thinking, caption: "reading sessions")
        await pause(Tour.beat)
        panel.show(.speaking, caption: "")
        await stream(Self.answer)
        panel.replied(failure: nil)
        await talk(for: Tour.answering)
        panel.expandAnswer(true)
        await pause(Tour.dwell)
        panel.expandAnswer(false)
        await pause(Tour.beat)
        panel.show(.listening, caption: "")
        await say(Self.followUp)
        panel.asked(Self.followUp)
        panel.show(.thinking, caption: "reading mail")
        await pause(Tour.beat)
        panel.draft(subject: Self.draftSubject, Self.mail)
        await stream("I drafted the reply to Sam with the link. Send it when it reads right.")
        panel.replied(failure: nil)
        await talk(for: Tour.answering)
        panel.draftAnswered(DraftCard(subject: Self.draftSubject, draft: Self.mail), .answered)
        await pause(Tour.beat)
        panel.show(.listening, caption: "")
        panel.ruling(true)
        await pause(Tour.beat)
        await say(Self.ruleSaid)
        panel.ruling(false)
        panel.asked(Self.ruleSaid)
        panel.show(.thinking, caption: "reading status")
        await pause(Tour.beat)
        await stream("Agents will ask you before any push to main. Should that hold on the whole Mac, or only in shop?")
        panel.replied(failure: nil)
        panel.rule(subject: Self.ruleSubject, Self.rule)
        await talk(for: Tour.answering)
        await pause(Tour.dwell)
        panel.ruleAnswered(RuleCard(subject: Self.ruleSubject, draft: Self.rule), .answered)
        if let heldCall = Self.heldCall {
            panel.hold(heldCall)
            await pause(Tour.dwell)
            panel.release(heldCall.subject)
        }
        panel.dismiss()
        await pause(Tour.afterDismiss)
        panel.asked("Is the api build green")
        panel.replied(failure: "Memnox could not be reached on this Mac")
        panel.showSide(true)
        await pause(Tour.dwell)
        panel.showSide(false)
        await pause(Tour.afterDismiss)
        if let done = Self.done {
            panel.finished(done)
            await pause(Tour.finishedDwell)
        }
        panel.shake()
        await pause(Tour.beat)
    }

    private func view(_ id: String) -> SessionView? {
        guard let card = cards.first(where: { $0.sessionId == id }) else { return nil }
        let stepJSON = steps.enumerated().map { index, text in
            #"{"at":"2026-10-03T12:00:\#(String(format: Self.secondsFormat, index))Z","surface":"\#(text.hasPrefix(Self.shellStepPrefix) ? StepSurface.shell.rawValue : StepSurface.filesystem.rawValue)","text":"\#(text)"}"#
        }.joined(separator: ",")
        let lineJSON = lines.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }.joined(separator: ",")
        let excerpt = lines.isEmpty ? "" : #","excerpt":{"path":"src/billing/invoice.ts","lines":[\#(lineJSON)]}"#
        let json = #"{"sessionId":"\#(id)","agent":"\#(card.agent ?? "")","agentName":"\#(card.agentName)","task":"add VAT to invoices","state":"working","thinking":true,"repository":"shop","waitingOnYou":0,"helpers":[],"steps":[\#(stepJSON)],"files":[{"path":"src/billing/invoice.ts","added":3,"removed":1}]\#(excerpt)}"#
        return try? JSONDecoder().decode(SessionView.self, from: Data(json.utf8))
    }

    private func talk(for seconds: Double) async {
        let start = Date()
        while Date().timeIntervalSince(start) < seconds, !Task.isCancelled {
            let t = Date().timeIntervalSinceReferenceDate
            Self.level = Float(Wave.base + Wave.slowAmplitude * sin(t * Wave.slowRate) + Wave.fastAmplitude * sin(t * Wave.fastRate))
            try? await Task.sleep(nanoseconds: UInt64(Wave.frameSeconds * Self.nanosecondsPerSecond))
        }
        Self.level = 0
    }

    /// The question said a word at a time, the way the recognizer hands it over.
    private func say(_ sentence: String) async {
        var heard: [Substring] = []
        for word in sentence.split(separator: " ") {
            heard.append(word)
            panel.hearing(heard.joined(separator: " "))
            await talk(for: Tour.perWord)
        }
    }

    /// The answer streamed in a few words at a time, the way the brain's chunks arrive.
    private func stream(_ answer: String) async {
        let words = answer.split(separator: " ", omittingEmptySubsequences: false)
        var index = 0
        while index < words.count, !Task.isCancelled {
            let chunk = words[index..<min(index + Self.wordsPerChunk, words.count)].joined(separator: " ")
            index += Self.wordsPerChunk
            panel.replying(index < words.count ? chunk + " " : chunk)
            await pause(Tour.perChunk)
        }
    }

    private static let wordsPerChunk = 3

    private static let question = "Give me an update on what is in the shop repository, with the file tree"
    private static let followUp = "Reply to Sam with the link to the new site"
    private static let draftSubject = "drf_preview"
    private static let ruleSubject = "prp_preview"
    private static let ruleSaid = "Never let any agent push to main without asking me first"

    private static let rule = RuleDraft(
        summary: "ask git.push on main", effect: RuleEffect.ask.rawValue, action: "git.push", branches: ["main"],
        reason: "pushes to main go through the person first",
        scopes: [
            RuleScope(id: RuleScopeKind.machine.rawValue, kind: RuleScopeKind.machine.rawValue, label: "This Mac"),
            RuleScope(id: "repository-1", kind: RuleScopeKind.repository.rawValue, label: "shop", folder: "/Users/me/Documents/shop", suggested: true),
            RuleScope(id: "repository-2", kind: RuleScopeKind.repository.rawValue, label: "api", folder: "/Users/me/Documents/api"),
        ]
    )

    private static let answer = """
    ## The shop repository
    It is a **TypeScript** store on Bun, with Prisma for the database and Stripe for payments.

    - `src/billing/` holds the invoice total, where Claude is adding VAT
    - `src/cart/` holds the basket and its tests
    - `prisma/` holds the schema and four migrations

    ```
    shop/
    ├── src/
    │   ├── billing/invoice.ts
    │   └── cart/cart.ts
    └── prisma/schema.prisma
    ```

    Two files changed so far and the tests pass.
    """

    private static let mail = MailDraft(
        service: MailService.gmail.rawValue, mode: DraftMode.reply.rawValue, to: ["sam@example.com"],
        subject: "Re: The new site", body: "Hi Sam,\n\nHere is the link to the new site, built and deployed this morning:\nhttps://example.com\n\nBest regards", thread: 1
    )

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * Self.nanosecondsPerSecond))
    }

    private static let sessions: [SessionCard] = [
        SessionCard(sessionId: "ses_shop", agent: "claude-code", agentName: "Claude Code", task: "add VAT to invoices", state: SessionState.working.rawValue, thinking: true, repository: "shop"),
        SessionCard(sessionId: "ses_api", agent: "codex-cli", agentName: "Codex", task: "fix the flaky test", state: SessionState.working.rawValue, thinking: true, repository: "api"),
        SessionCard(sessionId: "ses_site", agent: "cursor", agentName: "Cursor", task: "landing copy", state: SessionState.open.rawValue, repository: "site"),
    ]

    private static let allSteps = [
        "Read src/billing/types.ts", "Edited src/billing/invoice.ts", "Ran npm test", "Edited src/billing/invoice.ts",
    ]

    private static let allLines: [[String]] = [
        [], ["-const TVA = 0.2", "+const TVA = 0.196"], [],
        ["+export function total(items: Item[]) {", "+  const sum = items.reduce((s, i) => s + i.price, 0)", "+  return sum * (1 + TVA)", "+}"],
    ]

    /// A held call shaped like the daemon's, so the card is drawn from the same fields a real one has.
    private static let heldCall: DaemonEvent? = event(
        #"{"kind":"held","subject":"apr_preview","agent":"claude-code","agentName":"Claude Code","summary":"push to main","what":"git push origin main","why":"wants to push to main","at":"2026-10-03T12:00:00Z"}"#
    )

    private static let done: DaemonEvent? = event(
        #"{"kind":"notice","notice":"finished","subject":"ses_api","agent":"codex-cli","agentName":"Codex","summary":"The flaky checkout test is fixed and the suite passes.","sessionId":"ses_api","at":"2026-10-03T12:05:00Z"}"#
    )

    /// A fixture that no longer decodes skips its step rather than crashing the preview.
    private static func event(_ json: String) -> DaemonEvent? {
        try? JSONDecoder().decode(DaemonEvent.self, from: Data(json.utf8))
    }
}
