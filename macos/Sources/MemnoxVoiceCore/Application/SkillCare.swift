import Foundation

/// Skills that improve with use, as the runtime counts and suggests: each skill's uses, failures and refusals, its fix
/// backlog, and a suggested fix the runtime built by rule. Accepting goes through skill-put like any new version, so
/// one that reaches further waits for a signature on the island and nothing here grants anything.
public final class SkillCare: @unchecked Sendable {
    private let link: DaemonLink
    private let ids: RequestIds
    private let lock = NSLock()
    private var counted: [String: SkillStatsView] = [:]
    private var suggested: SkillCalibration?
    private var read = false
    private var busyWith: String?

    /// Told after anything here changed, on whatever thread that happened.
    public var changed: (@Sendable () -> Void)?

    public init(link: DaemonLink, ids: RequestIds = RequestIds()) {
        self.link = link
        self.ids = ids
    }

    public func stats(_ name: String) -> SkillStatsView? { lock.withLock { counted[name] } }
    /// The suggestion last built, for the skill it names.
    public var calibration: SkillCalibration? { lock.withLock { suggested } }
    /// Whether the runtime answered the counts at all; an older one does not, and the page leaves them out.
    public var answered: Bool { lock.withLock { read } }
    public var busy: String? { lock.withLock { busyWith } }

    public func refresh() async {
        let response = await ask(DaemonRequest(id: ids.next(), method: .skillStats))
        take(response)
        changed?()
    }

    /// One line added to the skill's backlog; the skill itself is not touched.
    public func note(_ name: String, _ typed: String) async -> SkillOutcome {
        guard let line = SkillCareLines.note(typed) else { return .failed("Say what to note.") }
        var request = DaemonRequest(id: ids.next(), method: .skillNote)
        request.skillName = name
        request.skillNote = line
        let response = await working(name) { await self.ask(request) }
        guard let response else { return .failed("The runtime is not answering.") }
        guard response.ok else { return .failed(response.error ?? "The runtime refused this.") }
        take(response)
        changed?()
        return .done("Noted for \(name).")
    }

    /// Asks the runtime for a suggested fix; nothing changes until Accept.
    public func calibrate(_ name: String) async -> SkillOutcome {
        var request = DaemonRequest(id: ids.next(), method: .skillCalibrate)
        request.skillName = name
        let response = await working(name) { await self.ask(request) }
        guard let response else { return .failed("The runtime is not answering.") }
        guard response.ok else { return .failed(response.error ?? "The runtime refused this.") }
        lock.withLock { suggested = response.skillCalibration }
        changed?()
        return response.skillCalibration == nil
            ? .done("Nothing noted and nothing failed, so there is no fix to suggest.")
            : .done("A fix is suggested for \(name).")
    }

    /// Sends the suggested version through skill-put, where the project it lives in is said so it lands there.
    public func accept(_ calibration: SkillCalibration, scope: SkillScope, project: String?) async -> SkillOutcome {
        var request = DaemonRequest(id: ids.next(), method: .skillPut)
        request.skillDraft = calibration.draft
        request.skillScope = scope.rawValue
        request.skillProject = project
        let response = await working(calibration.name) { await self.ask(request) }
        guard let response else { return .failed("The runtime is not answering.") }
        guard response.ok else { return .failed(response.error ?? "The runtime refused this.") }
        lock.withLock { suggested = nil }
        changed?()
        if let proposed = response.proposed { return .proposed(proposed) }
        return .done("\(calibration.name) \(calibration.draft.version) is in the hub now.")
    }

    public func dismissSuggestion() {
        lock.withLock { suggested = nil }
        changed?()
    }

    private func take(_ response: DaemonResponse?) {
        lock.withLock {
            guard let stats = response?.skillStats else { return }
            read = true
            counted = Dictionary(uniqueKeysWithValues: stats.map { ($0.name, $0) })
        }
    }

    private func working<T>(_ subject: String, _ body: () async -> T) async -> T {
        lock.withLock { busyWith = subject }
        changed?()
        let result = await body()
        lock.withLock { busyWith = nil }
        changed?()
        return result
    }

    private func ask(_ request: DaemonRequest) async -> DaemonResponse? {
        try? await link.request(request)
    }
}
