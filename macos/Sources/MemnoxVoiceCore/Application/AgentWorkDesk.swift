import Foundation

/// How a press on agent work ended, said in a line above the page.
public enum WorkOutcome: Equatable, Sendable {
    case done(String)
    case failed(String)
}

/// Agent work as the daemon keeps it: issues in a tracker a person pointed a profile's agent at. Starting, stopping,
/// closing and answering a handoff are unsigned steers, since each only points or stops an agent; the daemon decides.
public final class AgentWorkDesk: @unchecked Sendable {
    private let link: DaemonLink
    private let ids: RequestIds
    private let lock = NSLock()
    private var list: [AgentWork]?
    private var failed = false
    private var busyWith: String?

    /// Told after anything here changed, on whatever thread that happened.
    public var changed: (@Sendable () -> Void)?

    public init(link: DaemonLink, ids: RequestIds = RequestIds()) {
        self.link = link
        self.ids = ids
    }

    /// Newest change first, as the daemon sends it.
    public var work: [AgentWork]? { lock.withLock { list } }
    public var unreadable: Bool { lock.withLock { failed } }
    /// The work or handoff a press is still working on, so its controls can say so.
    public var busy: String? { lock.withLock { busyWith } }

    public func refresh() async {
        let response = await ask(DaemonRequest(id: ids.next(), method: .agentWork))
        lock.withLock {
            failed = response?.ok != true
            if let work = response?.agentWork { list = work }
        }
        changed?()
    }

    /// A work event's piece of work, put in place of the one it replaces and moved to the top, with no read.
    public func heard(_ changed: AgentWork) {
        lock.withLock {
            guard let kept = list else { return }
            list = [changed] + kept.filter { $0.id != changed.id }
        }
        self.changed?()
    }

    /// Points a profile's agent at an issue: a key such as LIN-123, or the issue's link.
    public func start(profile: String, target: String, tracker: Tracker? = nil, title: String? = nil,
                      project: String? = nil) async -> WorkOutcome {
        var request = DaemonRequest(id: ids.next(), method: .workStart)
        request.workProfile = profile
        request.workTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
        request.workTracker = tracker?.rawValue
        request.workTitle = AgentWorkLines.filled(title)
        request.workProject = AgentWorkLines.filled(project)
        return await change(target, request) { _ in AgentWorkLines.started(target) }
    }

    public func stop(_ id: String) async -> WorkOutcome {
        var request = DaemonRequest(id: ids.next(), method: .workStop)
        request.workId = id
        return await change(id, request) { _ in "Stopped. The agent is told to put it down." }
    }

    /// Closes it as done, which is the person's word once they checked what the agent claimed.
    public func close(_ id: String) async -> WorkOutcome {
        var request = DaemonRequest(id: ids.next(), method: .workClose)
        request.workId = id
        return await change(id, request) { _ in "Closed as done." }
    }

    public func answer(_ handoff: String, _ word: HandoffAnswerWord) async -> WorkOutcome {
        var request = DaemonRequest(id: ids.next(), method: .handoffAnswer)
        request.handoffId = handoff
        request.handoffAnswer = word.rawValue
        return await change(handoff, request) { _ in AgentWorkLines.answered(word) }
    }

    private func change(_ subject: String, _ request: DaemonRequest, done: (DaemonResponse) -> String) async -> WorkOutcome {
        lock.withLock { busyWith = subject }
        changed?()
        let response = await ask(request)
        lock.withLock {
            busyWith = nil
            if let work = response?.agentWork { list = work }
        }
        changed?()
        guard let response else { return .failed("The runtime is not answering.") }
        guard response.ok else { return .failed(response.error ?? "The runtime refused this.") }
        return .done(done(response))
    }

    /// A runtime that went away is said by `unreadable` and the outcome, never thrown at the page.
    private func ask(_ request: DaemonRequest) async -> DaemonResponse? {
        try? await link.request(request)
    }
}
