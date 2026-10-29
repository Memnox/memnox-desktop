import Foundation

/// How one press on the hub ended, said in a line under it.
public enum McpHubOutcome: Equatable, Sendable {
    /// Done at once: narrowing changes, imports and syncs need no signature.
    case done(String)
    /// A widening change waits on the island for the person's signature, by its proposal id.
    case proposed(String)
    case failed(String)
}

/// The MCP Hub as the runtime keeps it: servers set up once, given to the agents the person chose. It holds no rule:
/// the runtime writes every config, and a change that gives an agent more waits for a signature on the island.
public final class McpHub: @unchecked Sendable {
    private let link: DaemonLink
    private let ids: RequestIds
    private let lock = NSLock()
    private var view: McpHubView?
    private var failed = false
    private var tests: [String: McpServerHealth] = [:]
    private var presses: [String: McpPress] = [:]
    /// Proposals this hub raised and still waits on, by id, each with how to tell from a hub that it was written.
    private var awaiting: [String: Awaited] = [:]
    /// Agents chosen while adding a server that is not signed yet, given once the hub holds it.
    private var pendingGives: [String: [String]] = [:]

    private struct Awaited {
        let subject: String
        let landed: @Sendable (McpHubView) -> Bool
        let done: String
    }

    /// Told after anything here changed, on whatever thread that happened.
    public var changed: (@Sendable () -> Void)?

    public init(link: DaemonLink, ids: RequestIds = RequestIds()) {
        self.link = link
        self.ids = ids
    }

    public var hub: McpHubView? { lock.withLock { view } }

    /// The last read failed, so the page says so rather than drawing an empty hub.
    public var unreadable: Bool { lock.withLock { failed } }

    /// The server, the server and agent, or the secret a press is still working on, so its button can say so.
    public var busy: String? {
        lock.withLock { presses.first { $0.value == .working }?.key }
    }

    /// Where the last press on one server, pair or found line stands, for its own row to say.
    public func press(_ subject: String) -> McpPress? {
        lock.withLock { presses[subject] }
    }

    /// Forgets what a row says, once the person has read it and moves on.
    public func clear(_ subject: String) {
        lock.withLock {
            if presses[subject] != .working { presses[subject] = nil }
        }
        changed?()
    }

    /// A test run here, newer than the one the view carries.
    public func testOf(_ server: String) -> McpServerHealth? {
        lock.withLock { tests[server] }
    }

    public func refresh() async {
        let response = await ask(DaemonRequest(id: ids.next(), method: .mcpHub))
        lock.withLock {
            failed = response?.ok != true
            if let hub = response?.mcpHub { see(hub) }
        }
        changed?()
        await giveWhatWaits()
    }

    /// The daemon said a proposal stopped waiting, signed, declined or run out; the hub is read again to say which.
    public func settled(_ proposal: String) async {
        guard lock.withLock({ awaiting[proposal] != nil }) else { return }
        await refresh()
        let unsigned = lock.withLock { () -> Bool in
            guard let left = awaiting.removeValue(forKey: proposal) else { return false }
            presses[left.subject] = .failed(McpHubLines.notSigned)
            pendingGives[left.subject] = nil
            return true
        }
        if unsigned { changed?() }
    }

    /// Remembers who a new server is for, since giving it can only be asked once it is signed into the hub.
    public func giveOnceAdded(_ server: String, agents: [String]) {
        guard !agents.isEmpty else { return }
        lock.withLock { pendingGives[server] = agents }
    }

    /// A newer hub, and every awaited proposal it shows written is said done. Called with the lock held.
    private func see(_ hub: McpHubView) {
        view = hub
        for (id, each) in awaiting where each.landed(hub) {
            awaiting[id] = nil
            presses[each.subject] = .done(each.done)
        }
    }

    private func giveWhatWaits() async {
        let ready: [(String, [String])] = lock.withLock {
            let names = Set(view?.servers.map(\.name) ?? [])
            // A server being replaced is in the hub already, so its agents wait for the replacement to be signed.
            let signing = Set(awaiting.values.map(\.subject))
            let due = pendingGives.filter { names.contains($0.key) && !signing.contains($0.key) }
            for server in due.keys { pendingGives[server] = nil }
            return due.sorted { $0.key < $1.key }
        }
        for (server, agents) in ready {
            for agent in agents { _ = await assign(server, agent: agent, on: true) }
        }
    }

    /// Adds a server, and gives it to `agents` once the person has signed it in, one signature each.
    public func putServer(_ server: HubServer, giveTo agents: [String] = []) async -> McpHubOutcome {
        var request = DaemonRequest(id: ids.next(), method: .mcpServerPut)
        request.mcpServer = server
        // Remembered before asking, so a signature quicker than this answer still finds who it is for.
        giveOnceAdded(server.name, agents: agents)
        let name = server.name
        let outcome = await change(name, request, done: "\(name) is in the hub.") { hub in
            hub.servers.contains { $0.name == name }
        }
        if case .failed = outcome { lock.withLock { pendingGives[name] = nil } }
        await giveWhatWaits()
        return outcome
    }

    public func removeServer(_ name: String) async -> McpHubOutcome {
        var request = DaemonRequest(id: ids.next(), method: .mcpServerRemove)
        request.mcpServerName = name
        return await change(name, request, done: "\(name) was removed from every agent.")
    }

    public func assign(_ server: String, agent: String, on: Bool) async -> McpHubOutcome {
        var request = DaemonRequest(id: ids.next(), method: .mcpAssign)
        request.mcpServerName = server
        request.mcpAgent = agent
        request.mcpOn = on
        let label = McpHubLines.agentLabel(agent)
        let note = on ? "\(label) has \(server) now." : "\(label) no longer has \(server)."
        return await change(Self.pair(server, agent), request, done: note) { hub in
            let reach = hub.servers.first { $0.name == server }.map { McpHubLines.reach($0, agent: agent) }
            return (reach == .everywhere) == on
        }
    }

    public func importServer(agent: String, server: String) async -> McpHubOutcome {
        var request = DaemonRequest(id: ids.next(), method: .mcpImport)
        request.mcpServerName = server
        request.mcpAgent = agent
        let done = "\(server) is in the hub now, governed for \(McpHubLines.agentLabel(agent))."
        return await change(Self.found(server, agent), request, done: done)
    }

    public func sync() async -> McpHubOutcome {
        await change(Self.syncing, DaemonRequest(id: ids.next(), method: .mcpSync))
    }

    public func test(_ server: String) async -> McpHubOutcome {
        var request = DaemonRequest(id: ids.next(), method: .mcpTest)
        request.mcpServerName = server
        begin(server)
        let response = await ask(request)
        guard let response, response.ok else {
            let why = Self.failure(response)
            settle(server, .failed(why))
            return .failed(why)
        }
        let line = response.mcpHealth?.healthState == .healthy ? "\(server) answered." : "\(server) did not answer."
        lock.withLock {
            presses[server] = .done(line)
            if let health = response.mcpHealth { tests[server] = health }
            if let hub = response.mcpHub { see(hub) }
        }
        changed?()
        return .done(line)
    }

    /// The value goes straight to the runtime over this Mac's own socket, and nothing here keeps a copy.
    public func setSecret(_ name: String, value: String) async -> McpHubOutcome {
        var request = DaemonRequest(id: ids.next(), method: .mcpSecretSet)
        request.mcpSecret = name
        request.mcpSecretValue = value
        return await change(name, request, done: "\(name) is kept by this computer now.")
    }

    public func removeSecret(_ name: String) async -> McpHubOutcome {
        var request = DaemonRequest(id: ids.next(), method: .mcpSecretRemove)
        request.mcpSecret = name
        return await change(name, request, done: "\(name) was removed from this computer.")
    }

    /// What `busy` reads while a sync runs.
    public static let syncing = "sync"

    /// What `busy` reads while one server is given to or taken from one agent.
    public static func pair(_ server: String, _ agent: String) -> String { "\(server)/\(agent)" }

    /// What a press on one found line is kept under, apart from a hub server of the same name.
    public static func found(_ server: String, _ agent: String) -> String { "found/\(agent)/\(server)" }

    /// One press: the runtime's answer kept for its row, and a proposal remembered until a hub shows it written.
    private func change(_ subject: String, _ request: DaemonRequest, done: String = "Done.",
                        landed: (@Sendable (McpHubView) -> Bool)? = nil) async -> McpHubOutcome {
        begin(subject)
        let response = await ask(request)
        guard let response, response.ok else {
            let why = Self.failure(response)
            settle(subject, .failed(why))
            return .failed(why)
        }
        let outcome: McpHubOutcome
        if let proposed = response.proposed {
            outcome = .proposed(proposed)
        } else if let synced = response.mcpSynced {
            outcome = .done(McpHubLines.synced(synced))
        } else {
            outcome = .done(done)
        }
        lock.withLock {
            if case .proposed(let id) = outcome {
                presses[subject] = .waiting(response.outcome)
                if let landed { awaiting[id] = Awaited(subject: subject, landed: landed, done: done) }
            } else if case .done(let line) = outcome {
                presses[subject] = .done(line)
            }
            if let hub = response.mcpHub { see(hub) }
        }
        changed?()
        return outcome
    }

    private func begin(_ subject: String) {
        lock.withLock { presses[subject] = .working }
        changed?()
    }

    private func settle(_ subject: String, _ press: McpPress) {
        lock.withLock { presses[subject] = press }
        changed?()
    }

    /// A runtime that went away is said by `unreadable` and the outcome, never thrown at the page.
    private func ask(_ request: DaemonRequest) async -> DaemonResponse? {
        try? await link.request(request)
    }

    private static func failure(_ response: DaemonResponse?) -> String {
        guard let response else { return "The runtime is not answering." }
        return response.error ?? "The runtime refused this."
    }
}
