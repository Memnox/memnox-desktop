import Foundation

/// Whose an item is, as the scope chip on every rule, server, skill, profile and memory item says it: the person's
/// own, one project's, one agent's, or the organization's once Memnox Cloud is connected. The chip is grey and always
/// carries its word, since the scope is never told by colour alone. Mirrors `scope-lines.ts`.
public enum ScopeKind: String, CaseIterable, Sendable {
    case personal
    case project
    case agent
    case organization

    public var word: String {
        switch self {
        case .personal: "Personal"
        case .project: "Project"
        case .agent: "Agent"
        case .organization: "Organization"
        }
    }

    /// What the chip says to a screen reader, where the word alone could be read as a heading.
    public var label: String { "Scope: \(word)" }
}

public enum ScopeLines {
    /// A rule's scope: the organization's when the workspace published it, then one agent, then one folder, else the person's.
    public static func rule(_ rule: PolicyRuleView) -> ScopeKind {
        if rule.source == RuleSource.workspace.rawValue { return .organization }
        if !(rule.match.agents ?? []).isEmpty { return .agent }
        if !(rule.match.workingDirectories ?? []).isEmpty { return .project }
        return .personal
    }

    /// A server's scope: the organization's, one project's when it is given only inside repositories, else the person's.
    public static func server(_ server: McpHubServerView) -> ScopeKind {
        if server.scope == McpScope.organization.rawValue { return .organization }
        let projectOnly = server.agents.isEmpty && !(server.projects ?? []).isEmpty
        return projectOnly ? .project : .personal
    }

    public static func skill(_ skill: SkillView) -> ScopeKind {
        ScopeKind(rawValue: skill.scope) ?? .personal
    }

    /// Memory kept nowhere is still the person's to see, so it reads as personal.
    public static func memory(_ item: MemoryItemView) -> ScopeKind {
        item.scope == MemoryScope.project.rawValue ? .project : .personal
    }

    public static func project(_ project: ProjectView) -> ScopeKind {
        project.scope == ProjectScope.organization.rawValue ? .organization : .project
    }

    /// A profile is a bundle the person made on this machine, so it is always theirs.
    public static let profile: ScopeKind = .personal
}
