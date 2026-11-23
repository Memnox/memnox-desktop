import Foundation

// Profiles on the wire, mirrored from the runtime's daemon/profiles.ts: one named bundle of Skills Hub skills, MCP Hub
// servers and a rule pack. Applying one to an agent and a project raises the signed proposals each piece raises alone.

/// A rule pack as a profile carries it: its name and its TOML, imported as any pack is.
public struct ProfileRulePack: Encodable, Equatable, Sendable {
    public let name: String
    public let toml: String

    public init(name: String, toml: String) {
        self.name = name
        self.toml = toml
    }
}

/// A profile as a form fills it in, the role and who answers each optional so an older form still fills one in.
public struct ProfileDraft: Encodable, Equatable, Sendable {
    public let name: String
    public let description: String?
    /// Skills Hub skills, by name.
    public let skills: [String]?
    /// MCP Hub servers, by name.
    public let mcpServers: [String]?
    public let rulePack: ProfileRulePack?
    public let role: String?
    /// Who answers for it; the agent never inherits that person's authority.
    public let responsiblePerson: String?
    public let projects: [String]?

    public init(name: String, description: String? = nil, skills: [String]? = nil, mcpServers: [String]? = nil,
                rulePack: ProfileRulePack? = nil, role: String? = nil, responsiblePerson: String? = nil, projects: [String]? = nil) {
        self.name = name
        self.description = description
        self.skills = skills
        self.mcpServers = mcpServers
        self.rulePack = rulePack
        self.role = role
        self.responsiblePerson = responsiblePerson
        self.projects = projects
    }
}

/// The pack's name and how many rules it holds, never its text.
public struct ProfilePackSummary: Decodable, Equatable, Sendable {
    public let name: String
    public let rules: Int

    public init(name: String, rules: Int) {
        self.name = name
        self.rules = rules
    }
}

public struct ProfileView: Decodable, Equatable, Identifiable, Sendable {
    /// The name made safe for a file, which every method names the profile by too.
    public let id: String
    public let name: String
    public let description: String?
    public let skills: [String]
    public let mcpServers: [String]
    public let rulePack: ProfilePackSummary?
    public let updatedAt: String
    /// Names the hubs no longer hold, or a pack that no longer loads, each in a sentence.
    public let missing: [String]
    /// The role a rule's `roles:` matches; absent from a runtime before roles.
    public let role: String?
    /// Who answers for it; on a view, the person at this machine when none was named.
    public let responsiblePerson: String?
    public let projects: [String]
    /// The agent's own default, computed for an agent nobody bound and never stored.
    public let isDefault: Bool
    /// How it reaches the agents it works through; empty is a profile with no agent behind it.
    public let connections: [AgentConnection]
    /// The weakest level of its connections that are not gone, so one unguarded agent is never hidden.
    public let levels: CapabilityLevels

    public init(id: String, name: String, description: String? = nil, skills: [String] = [], mcpServers: [String] = [],
                rulePack: ProfilePackSummary? = nil, updatedAt: String, missing: [String] = [],
                role: String? = nil, responsiblePerson: String? = nil, projects: [String] = [], isDefault: Bool = false, connections: [AgentConnection] = [],
                levels: CapabilityLevels = .outside) {
        self.id = id
        self.name = name
        self.description = description
        self.skills = skills
        self.mcpServers = mcpServers
        self.rulePack = rulePack
        self.updatedAt = updatedAt
        self.missing = missing
        self.role = role
        self.responsiblePerson = responsiblePerson
        self.projects = projects
        self.isDefault = isDefault
        self.connections = connections
        self.levels = levels
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, skills, mcpServers, rulePack, updatedAt, missing, role, responsiblePerson, projects
        case isDefault, connections, levels
    }

    /// A runtime before roles and connections sends none of them, which reads as a profile with no agent behind it.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        description = try values.decodeIfPresent(String.self, forKey: .description)
        skills = try values.decodeIfPresent([String].self, forKey: .skills) ?? []
        mcpServers = try values.decodeIfPresent([String].self, forKey: .mcpServers) ?? []
        rulePack = try values.decodeIfPresent(ProfilePackSummary.self, forKey: .rulePack)
        updatedAt = try values.decode(String.self, forKey: .updatedAt)
        missing = try values.decodeIfPresent([String].self, forKey: .missing) ?? []
        role = try values.decodeIfPresent(String.self, forKey: .role)
        responsiblePerson = try values.decodeIfPresent(String.self, forKey: .responsiblePerson)
        projects = try values.decodeIfPresent([String].self, forKey: .projects) ?? []
        isDefault = try values.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        connections = try values.decodeIfPresent([AgentConnection].self, forKey: .connections) ?? []
        levels = try values.decodeIfPresent(CapabilityLevels.self, forKey: .levels) ?? .outside
    }

    /// A profile with no agent behind it, which shows no activity and no numbers.
    public var hasAgent: Bool { !connections.isEmpty }
}

/// What applying a profile raised, so a screen says it in a line and opens the cards.
public struct ProfileApplied: Decodable, Equatable, Sendable {
    public let profile: String
    public let agent: String
    public let project: String?
    /// Proposal ids, one per server, skill and rule, each signed on its own.
    public let proposed: [String]
    /// Already given to that agent, so nothing was raised for them.
    public let already: [String]
    /// Not raised, each with why.
    public let skipped: [String]

    public init(profile: String, agent: String, project: String? = nil, proposed: [String] = [], already: [String] = [],
                skipped: [String] = []) {
        self.profile = profile
        self.agent = agent
        self.project = project
        self.proposed = proposed
        self.already = already
        self.skipped = skipped
    }
}
