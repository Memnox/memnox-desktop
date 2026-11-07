import Foundation

// The MCP Hub on the wire, mirrored from the runtime's daemon/mcp-hub.ts and mcp/registry.ts. No answer here ever
// carries a secret's value back, only whether one is held.

/// How a server is reached, as the runtime's HUB_TRANSPORT names it.
public enum HubTransport: String, Sendable {
    case stdio
    case http
}

/// Who set a server up, as the runtime's MCP_SCOPE names it.
public enum McpScope: String, Sendable {
    case personal
    /// Given by the organization; never edited, removed or reassigned on this machine.
    case organization
}

/// What the last test of a server found, as the runtime's MCP_HEALTH names it.
public enum McpHealthState: String, Sendable {
    case unknown
    case healthy
    case error
}

/// A server as the Add form fills it, sent as `mcpServer`: plain variables by value, secrets by name only.
public struct HubServer: Encodable, Equatable, Sendable {
    public let name: String
    public let description: String?
    public let transport: String
    /// On stdio: the server's own launch line, which the hub puts behind the proxy.
    public let command: String?
    public let args: [String]?
    /// On http: where the server answers.
    public let url: String?
    /// On http: sent with every request; a credential is written as `memnox-secret:<name>` and resolved by the proxy.
    public let headers: [String: String]?
    public let env: [String: String]
    /// Variable name to secret name: only a reference reaches an agent's config, the value stays in the OS store.
    public let secrets: [String: String]

    public init(name: String, description: String? = nil, transport: HubTransport, command: String? = nil,
                args: [String]? = nil, url: String? = nil, headers: [String: String]? = nil,
                env: [String: String] = [:], secrets: [String: String] = [:]) {
        self.name = name
        self.description = description
        self.transport = transport.rawValue
        self.command = command
        self.args = args
        self.url = url
        self.headers = headers
        self.env = env
        self.secrets = secrets
    }
}

public struct McpToolSummary: Decodable, Equatable, Sendable {
    public let name: String
    public let description: String?
}

/// What the last test found, kept until the next one.
public struct McpServerHealth: Decodable, Equatable, Sendable {
    public let state: String
    public let checkedAt: String?
    public let error: String?
    public let tools: [McpToolSummary]?

    /// The state as a known case, or nil for one this app does not know yet.
    public var healthState: McpHealthState? { McpHealthState(rawValue: state) }
}

public struct McpHubServerView: Decodable, Equatable, Identifiable, Sendable {
    public let name: String
    /// personal or organization; absent from a runtime before organizations, which reads as personal.
    public let scope: String?
    public let description: String?
    public let transport: String
    public let command: String?
    public let args: [String]?
    public let url: String?
    /// Plain variables by name only, so a value pasted where a secret belonged is never read back.
    public let envNames: [String]
    /// On http: the headers sent, by name only, for the same reason.
    public let headerNames: [String]?
    /// Behind the proxy, so every call is ruled on and recorded.
    public let governed: Bool
    public let toolCount: Int
    public let tools: [McpToolSummary]?
    public let health: McpServerHealth
    public let agents: [String]
    /// The agents given it in one repository only, each with that repository; absent from an older runtime.
    public let projects: [McpProjectAssignment]?
    /// Each secret the server names, and whether the OS store holds it. Never the value.
    public let secretsHeld: [String: Bool]
    public let callsThisWeek: Int

    public var id: String { name }
    public var hubTransport: HubTransport? { HubTransport(rawValue: transport) }
    public var mcpScope: McpScope? { scope.flatMap(McpScope.init(rawValue:)) }

    /// The repositories one agent was given this server in, in the order the hub holds them.
    public func projects(of agent: String) -> [String] {
        (projects ?? []).filter { $0.agent == agent }.map(\.project)
    }
}

/// One agent given a server in one repository, by its absolute path.
public struct McpProjectAssignment: Decodable, Equatable, Sendable {
    public let agent: String
    public let project: String
}

/// An agent with an MCP config on this machine, and where it lives.
public struct McpHubAgentView: Decodable, Equatable, Sendable {
    public let agent: String
    public let path: String
}

/// One server line in one agent's config that the hub did not write, or that it wrote and a person changed.
public struct McpHubEntryView: Decodable, Equatable, Sendable {
    /// Absent for a file several agents share, such as a repository's own.
    public let agent: String?
    public let path: String
    public let name: String
    /// On drifted: edited or removed.
    public let kind: String?
    /// On skipped: why it was not written.
    public let reason: String?
}

public struct McpHubView: Decodable, Equatable, Sendable {
    public let servers: [McpHubServerView]
    public let agents: [McpHubAgentView]
    public let found: [McpHubEntryView]
    public let drifted: [McpHubEntryView]
    public let skipped: [McpHubEntryView]
}

/// What a sync changed, counted per kind, so a screen says it in a line.
public struct McpSyncSummary: Decodable, Equatable, Sendable {
    public let added: Int
    public let updated: Int
    public let removed: Int
    /// Configs the sync wrote, each backed up first.
    public let files: [String]

    public init(added: Int, updated: Int, removed: Int, files: [String]) {
        self.added = added
        self.updated = updated
        self.removed = removed
        self.files = files
    }
}
