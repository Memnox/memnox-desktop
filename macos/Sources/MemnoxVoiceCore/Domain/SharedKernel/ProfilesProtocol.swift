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

/// A profile as a form fills it in.
public struct ProfileDraft: Encodable, Equatable, Sendable {
    public let name: String
    public let description: String?
    /// Skills Hub skills, by name.
    public let skills: [String]?
    /// MCP Hub servers, by name.
    public let mcpServers: [String]?
    public let rulePack: ProfileRulePack?

    public init(name: String, description: String? = nil, skills: [String]? = nil, mcpServers: [String]? = nil,
                rulePack: ProfileRulePack? = nil) {
        self.name = name
        self.description = description
        self.skills = skills
        self.mcpServers = mcpServers
        self.rulePack = rulePack
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

    public init(id: String, name: String, description: String? = nil, skills: [String] = [], mcpServers: [String] = [],
                rulePack: ProfilePackSummary? = nil, updatedAt: String, missing: [String] = []) {
        self.id = id
        self.name = name
        self.description = description
        self.skills = skills
        self.mcpServers = mcpServers
        self.rulePack = rulePack
        self.updatedAt = updatedAt
        self.missing = missing
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
