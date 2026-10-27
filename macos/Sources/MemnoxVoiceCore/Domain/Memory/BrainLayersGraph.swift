import Foundation

// The brain's other layers folded into the local graph: the skills an agent is given, drawn at the core, the rules in
// force and standing permissions that run without the person, ringing it, and the MCP servers beside the apps around
// it. **Every line is still a field on a record**: a skill names the servers it needs and the agents it is given to, and
// nothing here is guessed from words.

/// One skill as the brain draws it: the hub's own, or one found in an agent's folder and not brought in yet.
public struct LocalSkill: Equatable, Sendable {
    public let name: String
    public let description: String?
    /// The agents it is given to, said in its details.
    public let agents: [String]
    /// The MCP servers it calls, each joined to the server's tile.
    public let servers: [String]
    /// When the hub last changed it, as the runtime writes a time.
    public let updatedAt: String?
    /// Where its SKILL.md is on this Mac, nil for a hub skill whose instructions came over the wire.
    public let path: String?

    public init(name: String, description: String? = nil, agents: [String] = [], servers: [String] = [], updatedAt: String? = nil,
                path: String? = nil) {
        self.name = name
        self.description = description
        self.agents = agents
        self.servers = servers
        self.updatedAt = updatedAt
        self.path = path
    }

    public init(_ skill: SkillView) {
        self.init(name: skill.name, description: skill.description, agents: skill.agents, servers: skill.mcpServers,
                  updatedAt: skill.updatedAt)
    }

    public init(_ found: FoundSkillView) {
        self.init(name: found.name, description: found.grant, agents: [found.agent], path: SkillSearch.instructionsFile(found))
    }
}

/// One rule in force or standing permission, said in its own sentence with what it does.
public struct LocalStanding: Equatable, Sendable {
    public let name: String
    public let sentence: String
    public let effect: String
    public let decidedAt: String?
    public let file: String?

    public init(name: String, sentence: String, effect: String, decidedAt: String? = nil, file: String? = nil) {
        self.name = name
        self.sentence = sentence
        self.effect = effect
        self.decidedAt = decidedAt
        self.file = file
    }

    public init(_ rule: PolicyRuleView) {
        self.init(name: rule.name, sentence: rule.sentence, effect: rule.effect, decidedAt: rule.decidedAt, file: rule.file)
    }
}

/// One MCP server the hub holds, drawn as an application tile.
public struct LocalServer: Equatable, Sendable {
    public let name: String
    public let detail: String?
    public let agents: [String]

    public init(name: String, detail: String? = nil, agents: [String] = []) {
        self.name = name
        self.detail = detail
        self.agents = agents
    }

    public init(_ server: McpHubServerView) {
        self.init(name: server.name, detail: server.description, agents: server.agents)
    }
}

extension LocalGraphs {
    public static func skillId(_ name: String) -> String { "skill:\(name)" }
    public static func standingId(_ name: String) -> String { "standing:\(name)" }
    public static func serverId(_ name: String) -> String { "mcp:\(name)" }

    /// The skills, the rules in force and the servers, each drawn once, a hub skill standing over a found one of its name.
    static func addLayers(_ inputs: LocalGraphInputs, name: (String?) -> String?, into graph: inout Building) {
        for server in inputs.servers.sorted(by: { $0.name < $1.name }) {
            let id = serverId(server.name)
            graph.add(round(id, server.name, .app, detail: server.detail))
            for agent in server.agents { graph.use(id, by: name(agent)) }
        }
        for skill in inputs.skills {
            let id = skillId(skill.name)
            var node = round(id, skill.name, .skill, detail: trimmed(skill.description))
            node.at = skill.updatedAt
            graph.add(node)
            for agent in skill.agents { graph.use(id, by: name(agent)) }
            for server in skill.servers { graph.link(id, serverId(server), .reads) }
        }
        for standing in inputs.standings.sorted(by: { $0.name < $1.name }) {
            var node = round(standingId(standing.name), standing.sentence, .standing, detail: standing.effect)
            node.at = standing.decidedAt
            graph.add(node)
        }
    }

    /// What a found entry is when it is a skill rather than a persona, as the runtime writes it.
    public static let foundSkill = "skill"

    /// The skills the brain draws: every one the hub keeps, and each skill an agent's folder holds that the hub has not
    /// brought in under that name, once.
    public static func skills(_ hub: SkillsHubView?) -> [LocalSkill] {
        guard let hub else { return [] }
        var names = Set(hub.skills.map(\.name))
        var drawn = hub.skills.map(LocalSkill.init)
        for found in hub.found.sorted(by: { $0.id < $1.id }) where found.kind == foundSkill && !found.imported {
            guard names.insert(found.name).inserted else { continue }
            drawn.append(LocalSkill(found))
        }
        return drawn
    }

    /// A skill's file on this Mac, where the skill came from an agent's folder.
    public static func skillPath(_ inputs: [LocalSkill], _ id: String) -> String? {
        inputs.first { skillId($0.name) == id }?.path
    }
}
