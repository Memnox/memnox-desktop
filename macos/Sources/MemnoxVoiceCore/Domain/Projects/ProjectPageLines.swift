import Foundation

/// What kind of tool a project lives in, so a repository reads as one kind among the notes, docs and apps.
public enum ProjectToolKind: String, CaseIterable, Sendable {
    case app
    case notes
    case docs
    case instructions
    case memoryService
    case repository
    case folder

    public var word: String {
        switch self {
        case .app: "Connected app"
        case .notes: "Notes"
        case .docs: "Docs"
        case .instructions: "Instruction files"
        case .memoryService: "Memory service"
        case .repository: "Repository"
        case .folder: "Folder on this Mac"
        }
    }
}

/// One tool a project lives in, as its Tools page lists it.
public struct ProjectTool: Equatable, Sendable {
    public let kind: ProjectToolKind
    public let name: String
    public let caption: String
    /// The MCP server it is, which the project's own manifest can take out again; nil for anything else.
    public let server: String?

    public init(kind: ProjectToolKind, name: String, caption: String, server: String? = nil) {
        self.kind = kind
        self.name = name
        self.caption = caption
        self.server = server
    }
}

/// One step of Get it ready on a project's Overview, and the page that does it.
public struct ProjectReadyStep: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let done: Bool
    public let page: ProjectPage
}

/// One part of the Overview's What its AI can use: the agents, the skills or the apps, with the names it has and what
/// the word means where it has none, so nobody needs to know what a skill or an MCP server is.
public struct ProjectCanUsePart: Equatable, Identifiable, Sendable {
    public let kind: ProjectCanUseKind
    public let title: String
    public let names: [String]
    /// Said in place of the names while there are none.
    public let empty: String
    /// What the word means, said under an empty part.
    public let what: String
    /// The page that holds the whole of it, one of the project's own or a page every project shares.
    public let target: ProjectCanUseTarget

    public var id: String { kind.rawValue }
    /// Agents are named rather than counted, as the cloud's card leaves their count off.
    public var counted: Bool { kind != .agents }
}

/// Where a part of What its AI can use opens: a page of the project, or a page every project shares.
public enum ProjectCanUseTarget: Equatable, Sendable {
    case page(ProjectPage)
    case shared(SidebarRowId)

    public var title: String {
        switch self {
        case .page(let page): page.title
        case .shared(let row): row.title
        }
    }
}

/// The three parts of What its AI can use, in the cloud's order.
public enum ProjectCanUseKind: String, Sendable {
    case agents
    case skills
    case apps
}

/// The words of a project's own pages, opened from Projects, written for one person on this Mac and, once it is
/// joined to a workspace, in the words Memnox Cloud uses for the same thing.
public enum ProjectPageLines {
    /// Memnox Cloud's projects, where people, channels and tickets are added to one.
    public static let cloudProjects = "https://app.memnox.com/projects"
    public static let openInCloud = "Open in Memnox Cloud"
    /// How many lately learned facts the Overview shows, the newest.
    public static let learnedShown = 3

    /// The project in Memnox Cloud where the organization shares it, else every project there.
    public static func cloudLink(_ project: ProjectView) -> URL? {
        guard let id = project.sharedBy?.id, !id.isEmpty,
              let segment = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return URL(string: cloudProjects) }
        return URL(string: "\(cloudProjects)/\(segment)")
    }

    /// What it is for, in the organization's own words, else the mission open in it; nil says nothing yet.
    public static func description(_ project: ProjectView) -> String? {
        if let description = project.sharedBy?.description, !description.isEmpty { return description }
        return project.openMissions.first?.statement
    }

    /// Whether a memory item or source names this project, by any of the ways the runtime keeps a project.
    public static func belongs(_ value: String?, to project: ProjectView) -> Bool {
        guard let value, !value.isEmpty else { return false }
        let names = [project.id, project.path, project.name, project.sharedBy?.id].compactMap { $0 }.filter { !$0.isEmpty }
        return names.contains(value)
    }

    /// The facts learned in this project, newest first, for its Memory page and the Overview's few.
    public static func learned(_ items: [MemoryItemView], in project: ProjectView) -> [MemoryItemView] {
        items.filter { belongs($0.project, to: project) }.sorted { $0.createdAt > $1.createdAt }
    }

    /// The tools it lives in: the notes, docs and apps first, the repository or folder last, since code is one kind
    /// of tool among many.
    public static func tools(_ project: ProjectView, sources: [MemorySourceView]) -> [ProjectTool] {
        let read = sources.filter { belongs($0.project, to: project) }.map { source in
            ProjectTool(kind: kind(of: source), name: source.name, caption: source.location)
        }
        let servers = project.sharedBy.map { $0.servers.map { ProjectTool(kind: .app, name: $0, caption: "From your organization") } }
            ?? project.servers.map { grant in
                ProjectTool(kind: .app, name: grant.name, caption: ProjectLines.grantLine(grant, of: project.agents.count), server: grant.name)
            }
        var place: [ProjectTool] = []
        if let repository = project.sharedBy?.repository, !repository.isEmpty {
            place.append(ProjectTool(kind: .repository, name: repository, caption: "Shared by your organization"))
        }
        if !project.path.isEmpty {
            place.append(ProjectTool(kind: .folder, name: (project.path as NSString).lastPathComponent, caption: project.path))
        }
        return read + servers + place
    }

    /// The chips along a project's card: whether its AI keeps memory from it. A count of tools is left off with the
    /// Tools page, since no page lists them now.
    public static func chips(_ project: ProjectView, sources: [MemorySourceView]) -> [String] {
        let memory = project.sharedBy?.memory ?? project.memoryScope
        return [memory.isEmpty || memory == "none" ? "No memory" : "Memory"]
    }

    /// Get it ready, while the project is still empty: what its AI may do. Adding tools is left off for now with the
    /// Tools page, and who else works on it is a team's question answered in Memnox Cloud.
    public static func readySteps(_ project: ProjectView, sources: [MemorySourceView], rulesHere: Int) -> [ProjectReadyStep] {
        let rules = rulesHere + (project.rules.inForce ? project.rules.count : 0)
        return [
            ProjectReadyStep(title: "Choose what its AI may do", detail: "What goes ahead, what asks you first, and what never happens.",
                             done: rules > 0, page: .rules),
        ]
    }

    /// The checklist stands while the project has no rules of its own, and goes once one is set.
    public static func showsChecklist(_ steps: [ProjectReadyStep]) -> Bool {
        !steps.contains { $0.done }
    }

    /// The manifest with one MCP server put in or taken out, everything else kept as it is.
    public static func draft(of project: ProjectView, adding server: String) -> ProjectDraft {
        withServers(project, project.servers.map(\.name).filter { $0 != server } + [server])
    }

    public static func draft(of project: ProjectView, removing server: String) -> ProjectDraft {
        withServers(project, project.servers.map(\.name).filter { $0 != server })
    }

    /// The manifest under a new name, everything else kept; nil for a name left empty or unchanged.
    public static func draft(of project: ProjectView, renamed name: String) -> ProjectDraft? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != project.name else { return nil }
        let base = ProjectLines.draft(of: project)
        return ProjectDraft(name: trimmed, instructions: base.instructions, servers: base.servers, skills: base.skills,
                            agents: base.agents, policy: base.policy, memory: base.memory)
    }

    /// Said where Remove would be on a project of this Mac's own, since the runtime has no call that removes one yet.
    public static let removeLine = "Removing a project is not something this Mac can do yet."
    /// Whether a project's pages show its people, which only a Mac joined to a workspace or a project the
    /// organization shares has; the desktop otherwise belongs to one person.
    public static func showsTeam(_ project: ProjectView, joined: Bool) -> Bool {
        joined || project.sharedBy != nil
    }

    /// The Overview's heading for who works on it, as Memnox Cloud's Overview names the same tile.
    public static let teamTitle = "People and agents"

    public static let canUseTitle = "What its AI can use"
    public static let canUseNote = "The AI agents on this project, what they know how to do, and the apps they can reach."
    /// How many names a part shows before the rest are a count.
    public static let canUseShown = 3

    /// What its AI can use, as Memnox Cloud's Overview says it: its agents, its skills and its apps. Alone on this Mac
    /// nothing speaks of people or a team; joined, the words are the cloud's own.
    public static func canUse(_ project: ProjectView, joined: Bool) -> [ProjectCanUsePart] {
        let team = showsTeam(project, joined: joined)
        let skills = unique(project.skills.map(\.name) + (project.sharedBy?.skills ?? []))
        let apps = unique(project.servers.map(\.name) + (project.sharedBy?.servers ?? []))
        return [
            ProjectCanUsePart(kind: .agents, title: "AI agents", names: project.agents.map(McpHubLines.agentLabel),
                              empty: team ? "Any AI agent its people use" : "Any AI agent you use",
                              what: "Such as Claude Code, Cursor or Codex.", target: .page(.agents)),
            ProjectCanUsePart(kind: .skills, title: "Skills", names: skills, empty: "None yet.",
                              what: team ? "Written know how its AI follows, such as how your team reviews work or writes an update."
                                  : "Written know how its AI follows, such as how you review work or write an update.",
                              target: .shared(.skills)),
            ProjectCanUsePart(kind: .apps, title: "Apps", names: apps, empty: "None yet.",
                              what: "Tools its AI can reach and act in, such as Linear, a database or a design tool.",
                              target: .shared(.connectors)),
        ]
    }

    /// "and 2 more", said under the names a part shows.
    public static func moreLine(_ part: ProjectCanUsePart) -> String? {
        let rest = part.names.count - canUseShown
        return rest > 0 ? "and \(rest) more" : nil
    }

    /// Said under Your team: who shares the project, else that it is still only this person's.
    public static func teamLine(_ project: ProjectView) -> String {
        if let organization = project.sharedBy {
            return "Your organization shares this project as \(organization.name), so the people on it and their agents work under the same rules. Who is on it is changed in Memnox Cloud."
        }
        return "Only you work in this project. Share it in Memnox Cloud and your team\u{2019}s agents work in it under the same rules as yours."
    }

    public static let shareTitle = "Share with your team"

    /// Said on Tools once this Mac is joined to a workspace, for the team's tools only the cloud links.
    public static let cloudToolsLine = "Channels, meetings and tickets are linked to a project in Memnox Cloud."
    /// Said where a project the organization shares would offer a change.
    public static let sharedLine = "Your organization keeps this project, so it is changed in Memnox Cloud."

    // The words of a project's own pages and the Projects list, pinned the same in shared/tauri-core's project-sidebar.ts.

    /// Said under the name while there is no description to say.
    public static let noDescription = "No description yet."
    public static let readyTitle = "Get it ready"
    public static let learnedTitle = "Learned lately"
    public static let learnedEmpty = "Nothing learned here yet. As its AI works in the tools it lives in, what it learns shows here."
    public static let learnedMore = "Everything it learned"
    public static let folderTitle = "Folder"

    /// Under the agents on the Agents page, beside the badge that opens the shared AI agents page.
    public static let agentsSharedLine = "AI agents are set up once for every project on this computer. This page shows the ones that work here and what this project gives each."
    public static let noAgents = "No agent has worked here yet, and the project names none."
    public static let givenTitle = "Given this project"
    public static let seenTitle = "Seen here, not named"

    public static let rulesHereTitle = "Rules that hold here"
    public static let rulesHereEmpty = "No rule names this project, so the rules of this computer decide here."
    public static let rulesLink = "Choose what agents may do in Protection settings"
    public static let itsAgentsTitle = "Its agents"
    public static let skillsCarriedTitle = "Skills it carries"
    public static let noSkillsGiven = "This project gives its agents no skills."
    /// How many of the skills every project shares the rules page lists before the rest are a link.
    public static let sharedSkillsShown = 5

    /// "2 more in Skills", the link under the skills every project shares.
    public static func moreSkillsLine(_ rest: Int) -> String {
        "\(rest) more in Skills"
    }

    public static let allMemoryLink = "All memory, shared with every project"

    public static let renameTitle = "Rename"
    public static let renameInCloud = "Rename in Memnox Cloud"
    public static let removeTitle = "Remove"
    public static let removeInCloud = "Remove in Memnox Cloud"
    public static let namePrompt = "Name"

    /// "Rename Spring launch", over the card renamed in place.
    public static func renameHeading(_ project: ProjectView) -> String {
        "Rename \(project.name)"
    }

    private static func withServers(_ project: ProjectView, _ servers: [String]) -> ProjectDraft {
        let base = ProjectLines.draft(of: project)
        return ProjectDraft(name: base.name, instructions: base.instructions, servers: servers.isEmpty ? nil : servers,
                            skills: base.skills, agents: base.agents, policy: base.policy, memory: base.memory)
    }

    private static func unique(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    private static func kind(of source: MemorySourceView) -> ProjectToolKind {
        switch MemorySourceKind(rawValue: source.kind) {
        case .obsidian: .notes
        case .markdown, .notionExport: .docs
        case .instructions: .instructions
        case .supermemory: .memoryService
        case .mcp: .app
        case nil: .docs
        }
    }
}
