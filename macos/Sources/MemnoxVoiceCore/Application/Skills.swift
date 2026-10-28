import Foundation

/// How one press on the Skills Hub ended: done at once, waiting for a signature on the island, or refused.
public enum SkillOutcome: Equatable, Sendable {
    case done(String)
    case proposed(String)
    case failed(String)
}

/// What a Continue in the assign sheet came to, counted so one line says it.
public struct AssignResults: Equatable, Sendable {
    public var proposed = 0
    public var done = 0
    public var failed: [String] = []

    public init(proposed: Int = 0, done: Int = 0, failed: [String] = []) {
        self.proposed = proposed
        self.done = done
        self.failed = failed
    }
}

/// The Skills Hub as the runtime keeps it: skills kept once and written into each agent's own format. It holds no
/// rule: giving a skill to an agent, or accepting a folder that reaches further, waits for a signature on the island.
public final class SkillsHub: @unchecked Sendable {
    private let link: DaemonLink
    private let ids: RequestIds
    private let lock = NSLock()
    private var view: SkillsHubView?
    private var failed = false
    private var busyWith: String?

    /// Told after anything here changed, on whatever thread that happened.
    public var changed: (@Sendable () -> Void)?

    public init(link: DaemonLink, ids: RequestIds = RequestIds()) {
        self.link = link
        self.ids = ids
    }

    public var hub: SkillsHubView? { lock.withLock { view } }

    /// The last read failed, so the page says so rather than drawing an empty hub.
    public var unreadable: Bool { lock.withLock { failed } }

    /// The skill a press is still working on, so its controls can say so.
    public var busy: String? { lock.withLock { busyWith } }

    /// What `busy` reads while a sync runs.
    public static let syncing = "sync"

    public func refresh() async {
        let response = await ask(DaemonRequest(id: ids.next(), method: .skillsHub))
        lock.withLock {
            failed = response?.ok != true
            if let hub = response?.skillsHub { view = hub }
        }
        changed?()
    }

    public func enable(_ name: String) async -> SkillOutcome {
        await change(name, named(.skillEnable, name), done: "\(name) is handed back to the agents it was given to.")
    }

    public func disable(_ name: String) async -> SkillOutcome {
        await change(name, named(.skillDisable, name), done: "\(name) was taken out of every agent. Its assignments are kept for later.")
    }

    public func accept(_ name: String) async -> SkillOutcome {
        await change(name, named(.skillAccept, name), done: "\(name) is accepted as it is now.")
    }

    /// Takes a personal skill out of the hub and every agent at once, its kept versions with it, since that only narrows.
    public func remove(_ name: String) async -> SkillOutcome {
        await change(name, named(.skillRemove, name), done: "\(name) was taken out of the hub and every agent, its kept versions with it.")
    }

    public func rollback(_ name: String, to version: String) async -> SkillOutcome {
        var request = named(.skillRollback, name)
        request.skillVersion = version
        return await change(name, request, done: "\(name) is back on \(version).")
    }

    public func assign(_ name: String, agent: String, on: Bool) async -> SkillOutcome {
        var request = named(.skillAssign, name)
        request.skillAgent = agent
        request.skillOn = on
        return await change(name, request, done: on ? "\(name) is now given to \(agent)." : "\(agent) no longer has \(name).")
    }

    /// Takes away at once and gives one signature each, sending only what differs from the agents it has now.
    public func assign(_ name: String, to chosen: Set<String>) async -> AssignResults {
        let current = hub?.skills.first { $0.name == name }?.agents ?? []
        let changes = SkillsLines.assignmentChanges(current: current, chosen: chosen)
        var results = AssignResults()
        let sends = changes.take.map { ($0, false) } + changes.give.map { ($0, true) }
        for (agent, on) in sends {
            switch await assign(name, agent: agent, on: on) {
            case .proposed: results.proposed += 1
            case .done: results.done += 1
            case .failed(let why): results.failed.append(why)
            }
        }
        return results
    }

    public func importFound(id: String, name: String) async -> SkillOutcome {
        var request = DaemonRequest(id: ids.next(), method: .skillImport)
        request.skillFoundId = id
        return await change(name, request, done: "\(name) is in the hub now.")
    }

    /// Imports each found skill in turn, one request each so the runtime rules on every one, telling `progress` how many
    /// have answered so far.
    public func importAll(_ found: [FoundSkillView], progress: @Sendable (Int) async -> Void = { _ in }) async -> ImportResults {
        var results = ImportResults()
        for (index, each) in found.enumerated() {
            switch await importFound(id: each.id, name: each.name) {
            case .done: results.done += 1
            case .proposed: results.proposed += 1
            case .failed(let why): results.failed.append(why)
            }
            await progress(index + 1)
        }
        return results
    }

    public func put(_ draft: SkillDraft) async -> SkillOutcome {
        var request = DaemonRequest(id: ids.next(), method: .skillPut)
        request.skillDraft = draft
        request.skillScope = SkillScope.personal.rawValue
        return await change(draft.name, request, done: "\(draft.name) is in the hub now.")
    }

    public func sync() async -> SkillOutcome {
        await change(Self.syncing, DaemonRequest(id: ids.next(), method: .skillSync), done: "Synced.", saysSync: true)
    }

    private func named(_ method: DaemonMethod, _ name: String) -> DaemonRequest {
        var request = DaemonRequest(id: ids.next(), method: method)
        request.skillName = name
        return request
    }

    private func change(_ subject: String, _ request: DaemonRequest, done: String, saysSync: Bool = false) async -> SkillOutcome {
        lock.withLock { busyWith = subject }
        changed?()
        let response = await ask(request)
        lock.withLock {
            busyWith = nil
            if let hub = response?.skillsHub { view = hub }
        }
        changed?()
        guard let response else { return .failed("The runtime is not answering.") }
        guard response.ok else { return .failed(response.error ?? "The runtime refused this.") }
        if let proposed = response.proposed { return .proposed(proposed) }
        if saysSync, let synced = response.skillsSynced { return .done(SkillsLines.synced(synced)) }
        return .done(done)
    }

    /// A runtime that went away is said by `unreadable` and the outcome, never thrown at the page.
    private func ask(_ request: DaemonRequest) async -> DaemonResponse? {
        try? await link.request(request)
    }
}
