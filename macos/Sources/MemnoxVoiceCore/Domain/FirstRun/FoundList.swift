import Foundation

/// One server or skill found in an agent's own folder, as a row the person can keep or leave out of an import.
public struct FoundItem: Equatable, Identifiable, Sendable {
    public enum Kind: String, Sendable {
        case server
        case skill
    }

    public let kind: Kind
    public let agent: String
    public let name: String
    /// The skill's id in the hub's found list; nil for a server, which is named by its agent and its name.
    public let skillId: String?

    /// Unique across both kinds, so one set of left out keys covers the whole list.
    public var id: String {
        switch kind {
        case .server: return "server:\(agent):\(name)"
        case .skill: return "skill:\(skillId ?? name)"
        }
    }
}

/// What one agent keeps, servers first, so a long list reads as a few agents rather than ninety lines.
public struct FoundGroup: Equatable, Identifiable, Sendable {
    public let agent: String
    public let items: [FoundItem]

    public var id: String { agent }
    public var servers: Int { items.filter { $0.kind == .server }.count }
    public var skills: Int { items.filter { $0.kind == .skill }.count }
}

/// Groups, filters and counts what the second step found, so a Mac with ninety skills shows a few agents with a few
/// rows each, a way to search, and Show all where there is more. Pure, so the view only draws what it is given.
public enum FoundList {
    /// The rows a group shows before Show all, enough to see what it holds without pushing the next agent away.
    public static let collapsed = 4

    /// Every agent's items that match the query, agents with the most first and ties by label, servers before skills.
    public static func groups(_ found: FoundToImport, matching query: String = "") -> [FoundGroup] {
        let wanted = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = all(found).filter { wanted.isEmpty || $0.name.localizedCaseInsensitiveContains(wanted) }
        let byAgent = Dictionary(grouping: items, by: \.agent)
        return byAgent.map { agent, items in
            let ordered = items.sorted { left, right in
                left.kind == right.kind ? left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending : left.kind == .server
            }
            return FoundGroup(agent: agent, items: ordered)
        }
        .sorted { left, right in
            left.items.count == right.items.count
                ? McpHubLines.agentLabel(left.agent) < McpHubLines.agentLabel(right.agent)
                : left.items.count > right.items.count
        }
    }

    /// The rows a group shows: a few until it is opened, every one once it is, or while a search narrows it.
    public static func shown(_ group: FoundGroup, expanded: Bool) -> [FoundItem] {
        expanded ? group.items : Array(group.items.prefix(collapsed))
    }

    /// "Show all 86", or nil when every row already shows.
    public static func showAll(_ group: FoundGroup, expanded: Bool) -> String? {
        expanded || group.items.count <= collapsed ? nil : "Show all \(group.items.count)"
    }

    /// "2 MCP servers and 86 skills", what one agent holds under its name.
    public static func holds(_ group: FoundGroup) -> String {
        let servers = counted(group.servers, "MCP server", "MCP servers")
        let skills = counted(group.skills, "skill", "skills")
        if group.servers == 0 { return skills }
        if group.skills == 0 { return servers }
        return "\(servers) and \(skills)"
    }

    /// What is left to import once the person left some out, in the shape the import already takes.
    public static func kept(_ found: FoundToImport, leaving out: Set<String>) -> FoundToImport {
        let servers = found.servers.filter { !out.contains(item($0).id) }
        let skills = found.skills.filter { !out.contains(item($0).id) }
        let agents = Set(servers.map(\.agent) + skills.map(\.agent))
        return FoundToImport(servers: servers, skills: skills, agents: agents.count)
    }

    /// "Import all 90", "Import 12 of 90", or "Nothing chosen" once every row is left out.
    public static func importTitle(kept: Int, of total: Int) -> String {
        if kept == 0 { return "Nothing chosen" }
        return kept == total ? "Import all \(total)" : "Import \(kept) of \(total)"
    }

    /// "Nothing matches notion", said in the list when a search finds no row.
    public static func noMatch(_ query: String) -> String {
        "Nothing matches \(query.trimmingCharacters(in: .whitespacesAndNewlines))."
    }

    static func all(_ found: FoundToImport) -> [FoundItem] {
        found.servers.map(item) + found.skills.map(item)
    }

    static func item(_ server: FoundToImport.Server) -> FoundItem {
        FoundItem(kind: .server, agent: server.agent, name: server.name, skillId: nil)
    }

    static func item(_ skill: FoundToImport.Skill) -> FoundItem {
        FoundItem(kind: .skill, agent: skill.agent, name: skill.name, skillId: skill.id)
    }

    private static func counted(_ count: Int, _ one: String, _ many: String) -> String {
        count == 1 ? "1 \(one)" : "\(count) \(many)"
    }
}
