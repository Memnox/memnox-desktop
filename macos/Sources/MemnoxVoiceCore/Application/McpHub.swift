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
    private var busyWith: String?
    /// Agents chosen while adding a server that is not signed yet, given once the hub holds it.
    private var pendingGives: [String: [String]] = [:]

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
    public var busy: String? { lock.withLock { busyWith } }

    /// A test run here, newer than the one the view carries.
    public func testOf(_ server: String) -> McpServerHealth? {
        lock.withLock { tests[server] }
    }

    public func refresh() async {
        let response = await ask(DaemonRequest(id: ids.next(), method: .mcpHub))
        lock.withLock {
            failed = response?.ok != true
            if let hub = response?.mcpHub { view = hub }
        }
        changed?()
        await giveWhatWaits()
    }

    /// Remembers who a new server is for, since giving it can only be asked once it is signed into the hub.
    public func giveOnceAdded(_ server: String, agents: [String]) {
        guard !agents.isEmpty else { return }
        lock.withLock { pendingGives[server] = agents }
    }

    private func giveWhatWaits() async {
        let ready: [(String, [String])] = lock.withLock {
            let names = Set(view?.servers.map(\.name) ?? [])
            let due = pendingGives.filter { names.contains($0.key) }
            for server in due.keys { pendingGives[server] = nil }
            return due.sorted { $0.key < $1.key }
        }
        for (server, agents) in ready {
            for agent in agents { _ = await assign(server, agent: agent, on: true) }
        }
    }

    public func putServer(_ server: HubServer) async -> McpHubOutcome {
        var request = DaemonRequest(id: ids.next(), method: .mcpServerPut)
        request.mcpServer = server
        return await change(server.name, request)
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
        let note = on ? "\(server) is now given to \(agent)." : "\(agent) no longer has \(server)."
        return await change(Self.pair(server, agent), request, done: note)
    }

    public func importServer(agent: String, server: String) async -> McpHubOutcome {
        var request = DaemonRequest(id: ids.next(), method: .mcpImport)
        request.mcpServerName = server
        request.mcpAgent = agent
        return await change(server, request, done: "\(server) is in the hub now, governed for \(agent).")
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
            end()
            return .failed(Self.failure(response))
        }
        lock.withLock {
            busyWith = nil
            if let health = response.mcpHealth { tests[server] = health }
            if let hub = response.mcpHub { view = hub }
        }
        changed?()
        return .done(response.mcpHealth?.healthState == .healthy ? "\(server) answered." : "\(server) did not answer.")
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

    private func change(_ subject: String, _ request: DaemonRequest, done: String = "Done.") async -> McpHubOutcome {
        begin(subject)
        let response = await ask(request)
        guard let response, response.ok else {
            end()
            return .failed(Self.failure(response))
        }
        lock.withLock {
            busyWith = nil
            if let hub = response.mcpHub { view = hub }
        }
        changed?()
        if let proposed = response.proposed { return .proposed(proposed) }
        if let synced = response.mcpSynced { return .done(McpHubLines.synced(synced)) }
        return .done(done)
    }

    private func begin(_ subject: String) {
        lock.withLock { busyWith = subject }
        changed?()
    }

    private func end() {
        lock.withLock { busyWith = nil }
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
