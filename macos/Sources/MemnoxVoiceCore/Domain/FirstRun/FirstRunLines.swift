import Foundation

/// What a fresh Mac already has that Memnox can bring in: servers and skills each agent keeps on its own.
public struct FoundToImport: Equatable, Sendable {
    public struct Server: Equatable, Sendable {
        public let agent: String
        public let name: String
    }

    public struct Skill: Equatable, Sendable {
        public let id: String
        public let agent: String
        public let name: String
    }

    /// Servers named in one agent's config; a repository's own file is shared by several and stays where it is.
    public let servers: [Server]
    public let skills: [Skill]
    /// The agents that hold any of them, counted once each.
    public let agents: Int

    public var isEmpty: Bool { servers.isEmpty && skills.isEmpty }
}

/// The first run's three steps and what each says, the same as Windows and Linux say them in onboarding.ts and
/// setup-steps.ts. Counts, never a score.
public enum FirstRunLines {
    /// The three steps by name; the voice, its permissions and the phone come after them, each optional.
    public static let steps = ["Connect your agents", "Set up your workspace", "Choose your boundaries"]

    /// How far the bar is filled: a third, two thirds, then whole, and whole again for what is optional.
    public static func progress(step: Int, optional: Bool) -> Double {
        if optional { return 1 }
        return Double(step + 1) / Double(steps.count)
    }

    public static func found(servers: [McpHubEntryView], skills: [FoundSkillView]) -> FoundToImport {
        let importableServers = servers.compactMap { entry in entry.agent.map { FoundToImport.Server(agent: $0, name: entry.name) } }
        let importableSkills = skills.filter { !$0.imported }.map { FoundToImport.Skill(id: $0.id, agent: $0.agent, name: $0.name) }
        let agents = Set(importableServers.map(\.agent) + importableSkills.map(\.agent))
        return FoundToImport(servers: importableServers, skills: importableSkills, agents: agents.count)
    }

    /// "We found 3 MCP servers and 2 skills across 2 agents."
    public static func foundLine(_ found: FoundToImport) -> String {
        if found.isEmpty { return "Nothing to bring in: no agent here keeps MCP servers or skills of its own yet." }
        let servers = counted(found.servers.count, "MCP server", "MCP servers")
        let skills = counted(found.skills.count, "skill", "skills")
        return "We found \(servers) and \(skills) across \(counted(found.agents, "agent", "agents"))."
    }

    /// What one tap of Import brought in, and what it could not.
    public static func importedLine(_ imported: Int, failed: [String]) -> String {
        let brought = "Brought in \(imported), now set up once in Memnox."
        guard let first = failed.first else { return brought }
        return "\(brought) \(failed.count) could not be, and stay where they are: \(first)"
    }

    /// "Careful · 6 rules", as a pack is listed to choose from.
    public static func packTitle(_ pack: RulePackView) -> String {
        "\(pack.name) · \(counted(pack.ruleCount, "rule", "rules"))"
    }

    /// The agents found on this Mac, in a line, the unprotected ones said so.
    public static func agentsFound(_ agents: [AgentStanding]) -> String {
        agentsFound(count: agents.count, open: agents.filter { $0.agentStatus == .unprotected }.count)
    }

    public static func agentsFound(count: Int, open: Int) -> String {
        if count == 0 { return "No agent found yet. Install Claude Code, Codex, Cursor or another agent, then check again." }
        let found = "Found \(counted(count, "agent", "agents"))."
        return open == 0 ? "\(found) Every one passes your boundaries first." : "\(found) \(counted(open, "still runs", "still run")) outside Memnox until you protect it."
    }

    /// What one agent's row says under its name in the first step.
    public static func agentDetail(_ agent: AgentStanding) -> String {
        switch agent.agentStatus {
        case .unprotected: return "Runs outside Memnox until you protect it."
        case .paused: return "Paused. Nothing it asks for runs."
        default: return "Every action passes your boundaries first."
        }
    }

    private static func counted(_ count: Int, _ one: String, _ many: String) -> String {
        count == 1 ? "1 \(one)" : "\(count) \(many)"
    }
}
