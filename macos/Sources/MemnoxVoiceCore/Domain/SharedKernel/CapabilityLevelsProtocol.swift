import Foundation

// Connections and capability levels on the wire, mirrored from the runtime's agents/agent-connection.ts and
// discovery/capability-levels.ts. Every level is computed by the daemon from what holds an agent and what was proved;
// this app only shows it and never works one out.

/// How sure Memnox is of one thing an agent does, strongest first.
public enum CapabilityLevel: String, CaseIterable, Codable, Sendable {
    /// A seam in front of it refused a planted test.
    case enforced
    /// Something is in front of it with no test passed.
    case mediated
    /// The agent asks Memnox and could act without asking.
    case advisory
    /// Seen in the record with nothing in front of it.
    case observed
    /// No evidence at all; not named `none`, which an optional level would read as nil.
    case noEvidence = "none"
}

/// The seams enforcement is broken down by, each the surface a proof names.
public enum EnforcementSeam: String, CaseIterable, Codable, Sendable {
    case shell
    case filesystem
    case git
    case network
    case browser
    case mcp
}

/// The strategy's seven capabilities, enforcement by seam.
public struct CapabilityLevels: Decodable, Equatable, Sendable {
    public let context: CapabilityLevel
    public let instructions: CapabilityLevel
    public let tools: CapabilityLevel
    public let activity: CapabilityLevel
    public let coordination: CapabilityLevel
    public let approval: CapabilityLevel
    /// By seam name; a seam this app does not know yet is kept and shown under its own name.
    public let enforcement: [String: CapabilityLevel]

    public init(context: CapabilityLevel, instructions: CapabilityLevel, tools: CapabilityLevel, activity: CapabilityLevel,
                coordination: CapabilityLevel, approval: CapabilityLevel, enforcement: [String: CapabilityLevel]) {
        self.context = context
        self.instructions = instructions
        self.tools = tools
        self.activity = activity
        self.coordination = coordination
        self.approval = approval
        self.enforcement = enforcement
    }

    private enum CodingKeys: String, CodingKey {
        case context, instructions, tools, activity, coordination, approval, enforcement
    }

    /// A level this app does not know yet reads as the weakest, so nothing is ever shown surer than the daemon said.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        func level(_ key: CodingKeys) throws -> CapabilityLevel {
            CapabilityLevel(rawValue: try values.decode(String.self, forKey: key)) ?? .noEvidence
        }
        context = try level(.context)
        instructions = try level(.instructions)
        tools = try level(.tools)
        activity = try level(.activity)
        coordination = try level(.coordination)
        approval = try level(.approval)
        let seams = try values.decodeIfPresent([String: String].self, forKey: .enforcement) ?? [:]
        enforcement = seams.mapValues { CapabilityLevel(rawValue: $0) ?? .noEvidence }
    }

    /// Every capability at none, which is what a profile with no agent behind it shows.
    public static let outside = CapabilityLevels(
        context: .noEvidence, instructions: .noEvidence, tools: .noEvidence, activity: .noEvidence, coordination: .noEvidence,
        approval: .noEvidence,
        enforcement: Dictionary(uniqueKeysWithValues: EnforcementSeam.allCases.map { ($0.rawValue, CapabilityLevel.noEvidence) }))
}

/// How Memnox reaches an agent, read off what this machine can see in front of it.
public enum ConnectionKind: String, CaseIterable, Sendable {
    case runtimeHook = "runtime_hook"
    case runtimeMcpProxy = "runtime_mcp_proxy"
    case guardWrapper = "guard"
    case gateway
    case mcp
    case observed
}

/// What a kind of connection can do: hold calls before they run, be asked, or only see.
public enum Mediation: String, CaseIterable, Sendable {
    case interposed
    case advisory
    case observed
}

public enum ConnectionStatus: String, CaseIterable, Sendable {
    /// A session of it is working now.
    case live
    /// Found on the last scan with nothing running.
    case idle
    /// Bound once and not found any more.
    case gone
}

/// One way Memnox reaches an agent, kept apart from the job it does.
public struct AgentConnection: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let profileId: String
    public let kind: String
    public let agentKind: String?
    /// The ledger key, `agt_<kind>`, which a binding never changes.
    public let agentId: String?
    public let mediation: String
    public let firstSeen: String
    public let lastSeen: String
    public let status: String
    /// How sure Memnox is of each capability through this connection.
    public let levels: CapabilityLevels?

    public init(id: String, profileId: String, kind: String, agentKind: String? = nil, agentId: String? = nil,
                mediation: String, firstSeen: String, lastSeen: String, status: String, levels: CapabilityLevels? = nil) {
        self.id = id
        self.profileId = profileId
        self.kind = kind
        self.agentKind = agentKind
        self.agentId = agentId
        self.mediation = mediation
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.status = status
        self.levels = levels
    }

    public var connectionKind: ConnectionKind? { ConnectionKind(rawValue: kind) }
    public var mediationKind: Mediation? { Mediation(rawValue: mediation) }
    public var connectionStatus: ConnectionStatus? { ConnectionStatus(rawValue: status) }
}
