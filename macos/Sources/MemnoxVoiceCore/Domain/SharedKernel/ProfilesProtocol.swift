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

/// A profile as a form fills it in, the job fields each optional so an older form still fills one in.
public struct ProfileDraft: Encodable, Equatable, Sendable {
    public let name: String
    public let description: String?
    /// Skills Hub skills, by name.
    public let skills: [String]?
    /// MCP Hub servers, by name.
    public let mcpServers: [String]?
    public let rulePack: ProfileRulePack?
    public let purpose: String?
    public let role: String?
    public let responsibilities: [String]?
    public let instructions: String?
    /// Who answers for it; the agent never inherits that person's authority.
    public let responsiblePerson: String?
    public let projects: [String]?
    /// The template it was copied from, by id.
    public let templateOf: String?

    public init(name: String, description: String? = nil, skills: [String]? = nil, mcpServers: [String]? = nil,
                rulePack: ProfileRulePack? = nil, purpose: String? = nil, role: String? = nil, responsibilities: [String]? = nil,
                instructions: String? = nil, responsiblePerson: String? = nil, projects: [String]? = nil, templateOf: String? = nil) {
        self.name = name
        self.description = description
        self.skills = skills
        self.mcpServers = mcpServers
        self.rulePack = rulePack
        self.purpose = purpose
        self.role = role
        self.responsibilities = responsibilities
        self.instructions = instructions
        self.responsiblePerson = responsiblePerson
        self.projects = projects
        self.templateOf = templateOf
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
    /// The job; each absent from a runtime before jobs, read then as an empty one.
    public let purpose: String?
    public let role: String?
    public let responsibilities: [String]
    public let instructions: String?
    /// Who answers for it; on a view, the person at this machine when none was named.
    public let responsiblePerson: String?
    public let projects: [String]
    public let templateOf: String?
    /// The agent's own default, computed for an agent nobody bound and never stored.
    public let isDefault: Bool
    /// How it reaches the agents it works through; empty is a profile with no agent behind it.
    public let connections: [AgentConnection]
    /// The weakest level of its connections that are not gone, so one unguarded agent is never hidden.
    public let levels: CapabilityLevels

    public init(id: String, name: String, description: String? = nil, skills: [String] = [], mcpServers: [String] = [],
                rulePack: ProfilePackSummary? = nil, updatedAt: String, missing: [String] = [], purpose: String? = nil,
                role: String? = nil, responsibilities: [String] = [], instructions: String? = nil, responsiblePerson: String? = nil,
                projects: [String] = [], templateOf: String? = nil, isDefault: Bool = false, connections: [AgentConnection] = [],
                levels: CapabilityLevels = .outside) {
        self.id = id
        self.name = name
        self.description = description
        self.skills = skills
        self.mcpServers = mcpServers
        self.rulePack = rulePack
        self.updatedAt = updatedAt
        self.missing = missing
        self.purpose = purpose
        self.role = role
        self.responsibilities = responsibilities
        self.instructions = instructions
        self.responsiblePerson = responsiblePerson
        self.projects = projects
        self.templateOf = templateOf
        self.isDefault = isDefault
        self.connections = connections
        self.levels = levels
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, skills, mcpServers, rulePack, updatedAt, missing, purpose, role, responsibilities
        case instructions, responsiblePerson, projects, templateOf, isDefault, connections, levels
    }

    /// A runtime before jobs and connections sends none of them, which reads as a profile with no agent behind it.
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
        purpose = try values.decodeIfPresent(String.self, forKey: .purpose)
        role = try values.decodeIfPresent(String.self, forKey: .role)
        responsibilities = try values.decodeIfPresent([String].self, forKey: .responsibilities) ?? []
        instructions = try values.decodeIfPresent(String.self, forKey: .instructions)
        responsiblePerson = try values.decodeIfPresent(String.self, forKey: .responsiblePerson)
        projects = try values.decodeIfPresent([String].self, forKey: .projects) ?? []
        templateOf = try values.decodeIfPresent(String.self, forKey: .templateOf)
        isDefault = try values.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        connections = try values.decodeIfPresent([AgentConnection].self, forKey: .connections) ?? []
        levels = try values.decodeIfPresent(CapabilityLevels.self, forKey: .levels) ?? .outside
    }

    /// A profile with no agent behind it, which shows no activity and no numbers.
    public var hasAgent: Bool { !connections.isEmpty }
}

/// A job description with no agent behind it; using one copies its job, and every suggestion stays off until taken.
public struct ProfileTemplate: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let purpose: String
    public let role: String
    public let responsibilities: [String]
    /// Skills a person may add, by name only, never installed by the template.
    public let suggestedSkills: [String]
    /// Rules in plain words for a person to write as rules; none is ever applied by a template.
    public let suggestedRules: [String]
    /// Agent kinds the scan can find, so a template never names a connection nobody can make.
    public let suggestedConnections: [String]

    public init(id: String, name: String, purpose: String, role: String, responsibilities: [String] = [],
                suggestedSkills: [String] = [], suggestedRules: [String] = [], suggestedConnections: [String] = []) {
        self.id = id
        self.name = name
        self.purpose = purpose
        self.role = role
        self.responsibilities = responsibilities
        self.suggestedSkills = suggestedSkills
        self.suggestedRules = suggestedRules
        self.suggestedConnections = suggestedConnections
    }
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
