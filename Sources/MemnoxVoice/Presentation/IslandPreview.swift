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
        static let asking: TimeInterval = 2
        static let answering: TimeInterval = 4
        static let afterDismiss: TimeInterval = 1
        static let finishedDwell: TimeInterval = 6.5
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
        panel.wire(answer: { [weak panel] subject, _, _ in panel?.release(subject) }, tapped: {})
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
        panel.show(.listening, caption: "what is Claude doing in shop")
        await talk(for: Tour.asking)
        panel.show(.thinking, caption: "Looking")
        await pause(Tour.beat)
        panel.show(.speaking, caption: "It is adding VAT to the invoice total, two files so far, and the tests pass.")
        await talk(for: Tour.answering)
        panel.show(.speaking, caption: "")
        if let heldCall = Self.heldCall {
            panel.hold(heldCall)
            await pause(Tour.dwell)
            panel.release(heldCall.subject)
        }
        panel.dismiss()
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
