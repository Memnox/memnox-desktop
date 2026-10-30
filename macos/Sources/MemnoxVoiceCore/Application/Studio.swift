import Foundation

/// How one press on the Policies, Activity or Agents page ended, said in a line above the page.
public enum StudioOutcome: Equatable, Sendable {
    /// Done at once: narrowing changes need no signature.
    case done(String)
    /// A change that lets agents do more waits on the island for the person's signature, by its proposal id.
    case proposed(String)
    case failed(String)
}

/// What trying an action came to: the runtime's verdict, or why there is none.
public enum RuleTryResult: Equatable, Sendable {
    case verdict(RuleVerdictView)
    case failed(String)
}

/// One request and its answer, or nil when the runtime did not answer at all; a runtime that went away is said by the
/// outcome, never thrown at a page.
private func ask(_ link: DaemonLink, _ request: DaemonRequest) async -> DaemonResponse? {
    try? await link.request(request)
}

private func outcome(_ response: DaemonResponse?, done: String) -> StudioOutcome {
    guard let response else { return .failed("The runtime is not answering.") }
    guard response.ok else { return .failed(response.error ?? "The runtime refused this.") }
    if let proposed = response.proposed { return .proposed(proposed) }
    return .done(done)
}

/// The rules in force and what could be let go next. It writes no rule: a rule the person builds is proposed, and goes
/// in force only when they sign it on the island.
public final class Studio: @unchecked Sendable {
    private let link: DaemonLink
    private let ids: RequestIds
    private let lock = NSLock()
    private var rulesView: PolicyRulesView?
    private var progressView: AutonomyProgress?
    private var failed = false
    private var working: String?

    /// Told after anything here changed, on whatever thread that happened.
    public var changed: (@Sendable () -> Void)?

    public init(link: DaemonLink, ids: RequestIds = RequestIds()) {
        self.link = link
        self.ids = ids
    }

    public var rules: PolicyRulesView? { lock.withLock { rulesView } }
    public var progress: AutonomyProgress? { lock.withLock { progressView } }
    /// The last read of the rules failed, so the page says so rather than drawing no rules.
    public var unreadable: Bool { lock.withLock { failed } }
    /// The rule, grant or pack a press is still working on, so its button can say so.
    public var busy: String? { lock.withLock { working } }

    /// What `busy` reads while a proposal or a pack is sent.
    public static let proposing = "propose"
    public static let importing = "pack"

    /// Reads the rules and the progress together; a runtime too old for progress still shows its rules.
    public func refresh() async {
        async let rules = ask(link, DaemonRequest(id: ids.next(), method: .rules))
        async let progress = ask(link, DaemonRequest(id: ids.next(), method: .progress))
        let (rulesRead, progressRead) = await (rules, progress)
        lock.withLock {
            failed = rulesRead?.ok != true
            if let view = rulesRead?.policyRules { rulesView = view }
            if let view = progressRead?.progress { progressView = view }
        }
        changed?()
    }

    public func propose(_ draft: RuleDraftInput) async -> StudioOutcome {
        var request = DaemonRequest(id: ids.next(), method: .rulePropose)
        request.ruleDraft = draft
        return await change(Self.proposing, request, done: "Proposed.")
    }

    public func remove(_ name: String) async -> StudioOutcome {
        var request = DaemonRequest(id: ids.next(), method: .ruleRemove)
        request.ruleName = name
        return await change(name, request, done: "\(name) is no longer in force.")
    }

    public func revoke(_ grantId: String) async -> StudioOutcome {
        var request = DaemonRequest(id: ids.next(), method: .autopilotRevoke)
        request.grantId = grantId
        return await change(grantId, request, done: "Taken back. Your agents ask about it again.")
    }

    /// Each rule in the pack becomes its own proposal, signed one at a time on the island.
    public func importPack(_ toml: String) async -> StudioOutcome {
        var request = DaemonRequest(id: ids.next(), method: .rulePackImport)
        request.rulePack = toml
        let response = await send(Self.importing, request)
        if let response, response.ok, let proposed = response.packProposed {
            let count = proposed.count
            return .done(count == 1 ? "1 rule waits for your signature on the island."
                : "\(count) rules wait for your signature on the island.")
        }
        return outcome(response, done: "Nothing in that file was a rule.")
    }

    /// Rules one action against the rules in force, recording and changing nothing.
    public func test(_ input: RuleTestInput) async -> RuleTryResult {
        var request = DaemonRequest(id: ids.next(), method: .ruleTest)
        request.ruleTest = input
        let response = await ask(link, request)
        if let verdict = response?.ruleVerdict { return .verdict(verdict) }
        return .failed(response?.error ?? "The runtime is not answering.")
    }

    /// The rules a person added here, as TOML text.
    public func exportToml() async -> String? {
        await ask(link, DaemonRequest(id: ids.next(), method: .rulesExport))?.rulesToml
    }

    private func change(_ subject: String, _ request: DaemonRequest, done: String) async -> StudioOutcome {
        let response = await send(subject, request)
        lock.withLock {
            if let view = response?.policyRules { rulesView = view }
            if let view = response?.progress { progressView = view }
        }
        changed?()
        return outcome(response, done: done)
    }

    private func send(_ subject: String, _ request: DaemonRequest) async -> DaemonResponse? {
        lock.withLock { working = subject }
        changed?()
        let response = await ask(link, request)
        lock.withLock { working = nil }
        changed?()
        return response
    }
}

/// What the agents did, newest first, a page at a time, and why any one of it was decided as it was.
public final class Activity: @unchecked Sendable {
    private let link: DaemonLink
    private let ids: RequestIds
    private let lock = NSLock()
    private var rowsRead: [ActivityRow] = []
    private var cursor: String?
    private var filterNow = ActivityFilter()
    private var failed = false
    private var reading = false
    private var opened: DecisionView?
    /// Bumped on every new filter, so a page asked for under an older one is dropped rather than mixed in.
    private var generation = 0

    /// Told after anything here changed, on whatever thread that happened.
    public var changed: (@Sendable () -> Void)?

    public init(link: DaemonLink, ids: RequestIds = RequestIds()) {
        self.link = link
        self.ids = ids
    }

    public var rows: [ActivityRow] { lock.withLock { rowsRead } }
    public var filter: ActivityFilter { lock.withLock { filterNow } }
    public var more: Bool { lock.withLock { cursor != nil } }
    public var loading: Bool { lock.withLock { reading } }
    public var unreadable: Bool { lock.withLock { failed } }
    public var decision: DecisionView? { lock.withLock { opened } }

    /// Reads from the newest again under this filter.
    public func show(_ filter: ActivityFilter) async {
        let mine: Int = lock.withLock {
            filterNow = filter
            rowsRead = []
            cursor = nil
            generation += 1
            return generation
        }
        await page(mine)
    }

    public func readOn() async {
        let mine: Int? = lock.withLock { cursor == nil ? nil : generation }
        if let mine { await page(mine) }
    }

    public func open(_ id: String) async {
        var request = DaemonRequest(id: ids.next(), method: .decision)
        request.decisionId = id
        let response = await ask(link, request)
        lock.withLock { opened = response?.decision }
        changed?()
    }

    public func close() {
        lock.withLock { opened = nil }
        changed?()
    }

    /// The signed record of what the filter holds, as `memnox verify` checks it.
    public func exportBundle() async -> String? {
        var request = DaemonRequest(id: ids.next(), method: .activityExport)
        request.activityFilter = filter
        return await ask(link, request)?.activityBundle
    }

    private func page(_ mine: Int) async {
        var request = DaemonRequest(id: ids.next(), method: .activity)
        let after: String? = lock.withLock {
            reading = true
            request.activityFilter = filterNow
            return cursor
        }
        request.activityCursor = after
        changed?()
        let response = await ask(link, request)
        lock.withLock {
            guard mine == generation else { return }
            reading = false
            failed = response?.ok != true
            if let page = response?.activity {
                rowsRead += page.rows
                cursor = page.nextCursor
            }
        }
        changed?()
    }
}

/// The agents on this computer as the runtime sees them, and pausing or resuming one.
public final class Agents: @unchecked Sendable {
    private let link: DaemonLink
    private let ids: RequestIds
    private let lock = NSLock()
    private var view: [AgentStanding]?
    private var failed = false
    private var working: String?

    /// Told after anything here changed, on whatever thread that happened.
    public var changed: (@Sendable () -> Void)?

    public init(link: DaemonLink, ids: RequestIds = RequestIds()) {
        self.link = link
        self.ids = ids
    }

    public var agents: [AgentStanding]? { lock.withLock { view } }
    public var unreadable: Bool { lock.withLock { failed } }
    /// The agent or session a press is still working on, so its button can say so.
    public var busy: String? { lock.withLock { working } }

    public func refresh() async {
        let response = await ask(link, DaemonRequest(id: ids.next(), method: .agents))
        lock.withLock {
            failed = response?.ok != true
            if let agents = response?.agentsView { view = agents }
        }
        changed?()
    }

    /// Holds the agent at once, since that only narrows.
    public func pause(_ kind: String) async -> StudioOutcome {
        var request = DaemonRequest(id: ids.next(), method: .agentPause)
        request.agentKind = kind
        return await change(kind, request, done: "Paused. Nothing it tries runs until you resume it.")
    }

    /// Gives the agent back its reach, which the runtime passes on for a signature.
    public func resume(_ kind: String) async -> StudioOutcome {
        var request = DaemonRequest(id: ids.next(), method: .agentResume)
        request.agentKind = kind
        return await change(kind, request, done: "Resumed.")
    }

    public func stopSession(_ sessionId: String) async -> StudioOutcome {
        var request = DaemonRequest(id: ids.next(), method: .sessionStop)
        request.sessionId = sessionId
        return await change(sessionId, request, done: "Stopped. The session waits until you let it carry on.")
    }

    private func change(_ subject: String, _ request: DaemonRequest, done: String) async -> StudioOutcome {
        lock.withLock { working = subject }
        changed?()
        let response = await ask(link, request)
        lock.withLock {
            working = nil
            if let agents = response?.agentsView { view = agents }
        }
        changed?()
        return outcome(response, done: done)
    }
}
