import Foundation

/// The top bar's two pickers, the workspace switcher and the scope selector, with the words both say. Neither decides
/// anything: the switcher narrows what the window shows to one project, and the selector shows the organization's read
/// only items beside the person's own, or either alone, once Memnox Cloud hands any down. Mirrors `shell-lines.ts`.
public enum ShellLines {
    /// Where the chosen project is remembered between openings, by its id.
    public static let currentProjectKey = "memnox.project.current"
    public static let allProjects = "All projects"
    public static let switcherLabel = "Current project"

    /// The project the person picked, or nil for every project, also when the one remembered is gone.
    public static func currentProject(_ projects: [ProjectView]?, saved: String?) -> ProjectView? {
        guard let saved, !saved.isEmpty, let projects else { return nil }
        return projects.first { $0.id == saved }
    }

    /// Whether a folder sits inside the project, the project's own folder included.
    public static func inside(_ folder: String, project path: String) -> Bool {
        var root = path
        while root.hasSuffix("/") || root.hasSuffix("\\") { root.removeLast() }
        if folder == root { return true }
        return folder.hasPrefix(root + "/") || folder.hasPrefix(root + "\\")
    }

    /// The projects shown under Workspaces: the one picked, or all of them.
    public static func projectsShown(_ projects: [ProjectView], current: ProjectView?) -> [ProjectView] {
        guard let current else { return projects }
        return projects.filter { $0.id == current.id }
    }

    /// The skills shown for a project: the person's own everywhere, and those written into this project's folder.
    public static func skillsShown(_ skills: [SkillView], current: ProjectView?) -> [SkillView] {
        guard let current else { return skills }
        return skills.filter { skill in skill.project.map { inside($0, project: current.path) } ?? true }
    }

    /// The folder a launch or open form starts on: the current project's when one is picked and offered, else the form's own first.
    public static func preselectedFolder(_ offered: [String], current: ProjectView?, fallback: String) -> String {
        guard let current else { return fallback }
        return offered.first { $0 == current.path } ?? fallback
    }

    /// The folders a launch or open form offers, with the current project's first so the form starts on it.
    public static func withCurrent(_ folders: [FolderPick], current: ProjectView?) -> [FolderPick] {
        guard let current else { return folders }
        return [FolderPick(path: current.path, name: current.name)] + folders.filter { $0.path != current.path }
    }

    /// Where the chosen scope is remembered between openings, under a new name since All joined the choices.
    public static let scopeKey = "memnox.scope.shown"
    /// Where the two choice selector remembered it, read once so an earlier choice of Organization is kept.
    public static let legacyScopeKey = "memnox.scope.current"
    public static let scopeLabel = "Scope"

    /// The line over the organization's items, so read only is said before anybody tries an edit.
    public static let organizationReadOnly = "Your organization set these up in Memnox Cloud, so they are read only here."
    public static let noOrganizationItems = "Your organization has not handed down anything of this kind."

    /// Whether the runtime handed down anything of an organization's, which only a Cloud connection does; the selector shows only then.
    public static func hasOrganization(servers: [McpHubServerView] = [], skills: [SkillView] = [], rules: [PolicyRuleView] = []) -> Bool {
        servers.contains { $0.scope == McpScope.organization.rawValue }
            || skills.contains { $0.scope == ShownScope.organization.rawValue }
            || rules.contains { $0.source == RuleSource.workspace.rawValue }
    }

    /// A remembered scope stands only while there is an organization to show; anything else, or nothing remembered, is All.
    public static func shownScope(saved: String?, connected: Bool) -> ShownScope {
        guard connected, let saved, let scope = ShownScope(rawValue: saved) else { return .all }
        return scope
    }

    /// The scope the two choice selector remembered, as the three choices name it: Organization stays, and Personal
    /// becomes All, since Personal was where everybody started and it hid the organization's items by mistake.
    public static func migratedScope(_ legacy: String?) -> ShownScope? {
        legacy == ShownScope.organization.rawValue ? .organization : nil
    }

    /// The items a list shows under the chosen scope: every one under All, else told apart by whether each is the organization's.
    public static func inScope<T>(_ items: [T], _ scope: ShownScope, organizations: (T) -> Bool) -> [T] {
        if scope == .all { return items }
        return items.filter { organizations($0) == (scope == .organization) }
    }

    /// What a destination's number key says in the palette: Command and the digit on the Mac, Ctrl and the digit elsewhere.
    public static func shortcutWords(_ key: String, mac: Bool) -> String {
        mac ? "\u{2318}\(key)" : "Ctrl \(key)"
    }
}

/// All shows both mixed, each with its chip; Personal is what this computer keeps; Organization is what Memnox Cloud
/// hands down, read only here.
public enum ShownScope: String, CaseIterable, Sendable {
    case all
    case personal
    case organization

    public var title: String {
        switch self {
        case .all: "All"
        case .personal: "Personal"
        case .organization: "Organization"
        }
    }
}
