import Foundation

/// Whether something on a project's page belongs to that project alone or is shared with every project on this
/// computer, said in a small badge so nobody has to guess which page changes it. Mirrors `project-context.ts`.
public enum ItemReach: String, CaseIterable, Sendable {
    case onlyHere
    case everyProject

    public var word: String {
        switch self {
        case .onlyHere: "Only here"
        case .everyProject: "Every project"
        }
    }

    /// What the badge says to a screen reader and on hover.
    public var hint: String {
        switch self {
        case .onlyHere: "Belongs to this project alone"
        case .everyProject: "Shared with every project, and changed on its own page"
        }
    }
}

/// One link in the project sidebar's Shared with every project group: the machine wide page it opens and how much of
/// it applies to this project, nil while that is still being read.
public struct SharedLink: Equatable, Identifiable, Sendable {
    public let row: SidebarRowId
    public let count: Int?
    /// Said on hover and to VoiceOver: what of it applies here.
    public let hint: String
    public let route: WindowRoute

    public var id: SidebarRowId { row }
    public var title: String { row.title }
}

/// How much of each shared page applies to one project, each nil while it is still being read.
public struct SharedCounts: Equatable, Sendable {
    public var rules: Int?
    public var skills: Int?
    public var servers: Int?
    public var connectors: Int?
    public var memory: Int?
    public var agents: Int?

    public init(rules: Int? = nil, skills: Int? = nil, servers: Int? = nil, connectors: Int? = nil, memory: Int? = nil,
                agents: Int? = nil) {
        self.rules = rules
        self.skills = skills
        self.servers = servers
        self.connectors = connectors
        self.memory = memory
        self.agents = agents
    }
}

/// One project in the sidebar's switcher: its name, its folder, and whether an agent is working there now.
public struct SwitcherRow: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let folder: String
    public let live: Bool
    public let current: Bool
}

/// What a project's card on the Projects list says beside its name: who works there now, what waits on the person
/// there, and when anything last happened, in plain words.
public struct ProjectPulse: Equatable, Sendable {
    /// The kinds of the agents working there now, each once.
    public let working: [String]
    public let waiting: Int
    public let lastActivity: String

    /// "Claude Code working now", "2 agents working now", or nil while nobody works there.
    public var workingLine: String? {
        switch working.count {
        case 0: nil
        case 1: "\(McpHubLines.agentLabel(working[0])) working now"
        default: "\(working.count) agents working now"
        }
    }

    /// "1 waits on you", or nil while nothing does.
    public var waitingLine: String? {
        switch waiting {
        case 0: nil
        case 1: "1 waits on you"
        default: "\(waiting) wait on you"
        }
    }
}

/// The memory page's project filter: everything, what is shared with every project, or what one project learned.
public enum MemoryProjectChoice: Hashable, Sendable {
    case all
    case shared
    case project(String)

    /// How the choice is remembered between openings.
    public var key: String {
        switch self {
        case .all: ""
        case .shared: ProjectContext.sharedMemoryKey
        case .project(let id): id
        }
    }

    public init(key: String) {
        switch key {
        case "": self = .all
        case ProjectContext.sharedMemoryKey: self = .shared
        default: self = .project(key)
        }
    }
}

/// The two contexts a person with several projects moves between: what belongs to one project, and what is shared with
/// every project on this computer. It only reads what the daemon scopes; anything carrying no project is shared.
public enum ProjectContext {
    // MARK: Shared with every project

    public static let sharedTitle = "Shared with every project"
    /// The shared group is left off a project's sidebar for now, since each item's badge already says where it is shared.
    public static let showsShared = false
    public static let sharedNote = "Set once for every project on this computer, and changed on its own page."
    /// The rows of the shared group, in the order the window's own sidebar lists them.
    public static let sharedRows: [SidebarRowId] = [.protection, .skills, .servers, .connectors, .memory, .agents]

    /// The shared group at the foot of a project's sidebar: only the pages the daemon answers, so no link leads nowhere.
    public static func shared(_ counts: SharedCounts, supports: Supports) -> [SharedLink] {
        sharedRows.compactMap { id in
            guard let row = Sidebar.rows.first(where: { $0.id == id }), let route = Sidebar.target(row, supports: supports) else { return nil }
            let count = count(id, counts)
            return SharedLink(row: id, count: count, hint: hint(id, count), route: route)
        }
    }

    /// How much of each shared page applies to one project, from whatever of it the window has read so far.
    public static func counts(_ project: ProjectView, rules: [PolicyRuleView]?, skills: [SkillView]?, servers: [McpHubServerView]?,
                              connections: [ToolConnection]?, memory: [MemoryItemView]?, agents: Int?) -> SharedCounts {
        SharedCounts(
            rules: rules.map { ProjectLines.rules($0, in: project).everywhere },
            skills: skills.map { $0.filter { reach(skillScope: $0.scope, skillProject: $0.project, in: project) == .everyProject }.count },
            servers: servers.map { $0.filter(givenEverywhere).count },
            connectors: connections.map { $0.filter(\.connected).count },
            memory: memory.map { $0.filter { owner($0.project) == nil }.count },
            agents: agents)
    }

    /// A server the hub gives to agents on their own, or the organization hands down, reaches every project.
    public static func givenEverywhere(_ server: McpHubServerView) -> Bool {
        !server.agents.isEmpty || server.scope == McpScope.organization.rawValue
    }

    private static func count(_ row: SidebarRowId, _ counts: SharedCounts) -> Int? {
        switch row {
        case .protection: counts.rules
        case .skills: counts.skills
        case .servers: counts.servers
        case .connectors: counts.connectors
        case .memory: counts.memory
        case .agents: counts.agents
        case .home, .projects, .waiting, .activity, .files: nil
        }
    }

    private static func hint(_ row: SidebarRowId, _ count: Int?) -> String {
        guard let count else { return "\(row.title), shared with every project" }
        switch row {
        case .protection: return "\(ProjectLines.counted(count, "rule holds", "rules hold")) here and in every project"
        case .skills: return "\(ProjectLines.counted(count, "skill", "skills")) its agents carry in every project"
        case .servers: return "\(ProjectLines.counted(count, "server", "servers")) given to agents in every project"
        case .connectors: return "\(ProjectLines.counted(count, "app", "apps")) connected as you, reached from every project"
        case .memory: return "\(ProjectLines.counted(count, "fact", "facts")) known in every project"
        case .agents: return "\(ProjectLines.counted(count, "agent", "agents")) on this computer, set up once for every project"
        case .home, .projects, .waiting, .activity, .files: return row.title
        }
    }

    // MARK: Which items belong where

    /// A skill the daemon wrote into this project's folder is only here; the person's own and the organization's are
    /// shared; one written into another project is nil, since it does not apply here.
    public static func reach(skillScope: String, skillProject: String?, in project: ProjectView) -> ItemReach? {
        guard skillScope == SkillScope.project.rawValue else { return .everyProject }
        guard let folder = skillProject, !folder.isEmpty else { return .everyProject }
        return ShellLines.inside(normalised(folder), project: normalised(project.path)) ? .onlyHere : nil
    }

    /// A server the project's manifest names is only here, unless the hub already gives it to agents everywhere.
    public static func reach(serverGivenEverywhere: Bool) -> ItemReach {
        serverGivenEverywhere ? .everyProject : .onlyHere
    }

    /// Memory kept under this project is only here, memory under no project is shared, and memory another project
    /// learned is nil, since it does not apply here.
    public static func reach(memory item: MemoryItemView, in project: ProjectView) -> ItemReach? {
        guard let owner = owner(item.project) else { return .everyProject }
        return belongs(owner, to: project) ? .onlyHere : nil
    }

    /// What one project learned, newest first, and what is known in every project because it names none.
    public static func memory(_ items: [MemoryItemView], in project: ProjectView) -> (here: [MemoryItemView], everywhere: [MemoryItemView]) {
        let here = items.filter { reach(memory: $0, in: project) == .onlyHere }
        let everywhere = items.filter { owner($0.project) == nil }
        return (newestFirst(here), newestFirst(everywhere))
    }

    public static let memoryHereTitle = "What this project learned"
    public static let memoryEverywhereTitle = "Also known everywhere"
    public static let memoryEverywhereNote = "Facts that belong to no one project, so the agents in every project read them."
    public static let memoryHereEmpty = "Nothing learned in this project yet. As its agents work here, what they learn shows here."
    /// How many shared facts the project's Memory page shows before linking to the rest.
    public static let everywhereShown = 5

    // MARK: The shared Memory page's filter

    /// Where the filter is remembered, by the project's id, the shared key, or empty for everything.
    public static let memoryChoiceKey = "memnox.memory.project"
    static let sharedMemoryKey = "shared"
    public static let allMemoryTitle = "All projects"
    public static let sharedMemoryTitle = "Shared with every project"

    /// The filter's choices: everything, what is shared, then each project, the most recently active first.
    public static func memoryChoices(_ projects: [ProjectView]) -> [(choice: MemoryProjectChoice, title: String)] {
        [(.all, allMemoryTitle), (.shared, sharedMemoryTitle)] + recent(projects).map { (.project($0.id), $0.name) }
    }

    /// The choice's title, all projects again when the project picked is gone.
    public static func title(_ choice: MemoryProjectChoice, projects: [ProjectView]) -> String {
        switch choice {
        case .all: return allMemoryTitle
        case .shared: return sharedMemoryTitle
        case .project(let id): return projects.first { $0.id == id }?.name ?? allMemoryTitle
        }
    }

    /// The facts the filter leaves on screen; a project that is gone shows everything rather than nothing.
    public static func shown(_ items: [MemoryItemView], _ choice: MemoryProjectChoice, projects: [ProjectView]) -> [MemoryItemView] {
        switch choice {
        case .all: return items
        case .shared: return items.filter { owner($0.project) == nil }
        case .project(let id):
            guard let project = projects.first(where: { $0.id == id }) else { return items }
            return items.filter { reach(memory: $0, in: project) == .onlyHere }
        }
    }

    /// Whose a fact is, said beside it: the project's name, Every project for a fact naming none, or the folder's own
    /// name for a project this computer has not opened.
    public static func owner(of item: MemoryItemView, projects: [ProjectView]) -> String {
        guard let owner = owner(item.project) else { return ItemReach.everyProject.word }
        if let project = projects.first(where: { belongs(owner, to: $0) }) { return project.name }
        return folderName(owner)
    }

    // MARK: The Projects list

    /// From how many projects the list offers a search, since a few fit on screen without one.
    public static let searchFrom = 6
    public static let searchPrompt = "Find a project"
    public static let emptyTitle = "Keep each piece of work apart"
    public static let emptyLine = "A project is a folder on this computer where your AI agents work, such as a website, a report or a campaign. Add one and Memnox keeps what its agents learn and may do there apart from your other work."
    public static let suggestionsTitle = "Folders your agents worked in"
    public static let suggestionsNote = "Your agents already worked in these folders. Add one to make it a project."
    public static let chooseTitle = "Choose a folder"
    public static let addTitle = "Add"
    public static let noActivity = "No activity yet"

    /// The projects most recently active first; two equally recent keep the daemon's order.
    public static func recent(_ projects: [ProjectView]) -> [ProjectView] {
        projects.enumerated().sorted { left, right in
            let a = left.element.lastActive ?? ""
            let b = right.element.lastActive ?? ""
            return a == b ? left.offset < right.offset : a > b
        }.map(\.element)
    }

    /// The projects whose name or folder holds every word typed.
    public static func matching(_ projects: [ProjectView], query: String) -> [ProjectView] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return projects }
        return projects.filter { project in
            let text = "\(project.name) \(project.path)".lowercased()
            return words.allSatisfy { text.contains($0) }
        }
    }

    /// Who works in the project now, what waits on the person there, and its last activity, from the sessions and the
    /// held calls the island already keeps. A held call names its folder only by name, so that is what it is matched by.
    public static func pulse(_ project: ProjectView, sessions: [SessionCard], waitingPlaces: [String?], now: Date) -> ProjectPulse {
        let here = sessions.filter { holds($0.repository, project) }
        var working: [String] = []
        for card in here where card.status.isActive {
            let kind = card.agent ?? card.agentName
            if !working.contains(kind) { working.append(kind) }
        }
        let waiting = waitingPlaces.filter { named($0, project) }.count
        let latest = ([project.lastActive] + here.map(\.lastActive)).compactMap { $0 }.max()
        let line = working.isEmpty ? SessionText.ago(latest, now: now).map { "Active \($0)" } ?? noActivity : "Active now"
        return ProjectPulse(working: working, waiting: waiting, lastActivity: line)
    }

    /// Whether an agent is working in the project now, which lights its dot in the switcher.
    public static func live(_ project: ProjectView, sessions: [SessionCard]) -> Bool {
        sessions.contains { $0.status.isActive && holds($0.repository, project) }
    }

    // MARK: The switcher

    public static let switcherPrompt = "Find a project"
    public static let allProjectsTitle = "All projects"
    public static let switcherHint = "Switch to another project"

    /// Every project, most recently active first, narrowed by what was typed, with the one open marked.
    public static func switcher(_ projects: [ProjectView], sessions: [SessionCard], current: String?, query: String) -> [SwitcherRow] {
        matching(recent(projects), query: query).map { project in
            SwitcherRow(id: project.id, name: project.name, folder: project.path, live: live(project, sessions: sessions),
                        current: project.id == current)
        }
    }

    /// Switching keeps the page the person was on, so Memory stays Memory in the next project.
    public static func switchRoute(to id: String, from place: ProjectPlace) -> WindowRoute {
        ProjectSidebar.route(id, place.page)
    }

    // MARK: Naming where things happen

    /// The project a session's repository sits in, by its name, else the folder's own name.
    public static func projectName(repository: String?, projects: [ProjectView]) -> String? {
        guard let repository = SessionReading.repository(repository) else { return nil }
        return projects.first { holds(repository, $0) }?.name ?? folderName(repository)
    }

    /// The project a held call's folder name belongs to, else the folder's name as the daemon sent it.
    public static func projectName(place: String?, projects: [ProjectView]) -> String? {
        guard let place = SessionReading.repository(place) else { return nil }
        return projects.first { named(place, $0) }?.name ?? place
    }

    /// "In Spring launch", said before what an item on Home or Needs your attention is about.
    public static func inLine(_ name: String?) -> String? {
        name.map { "In \($0)" }
    }

    // MARK: Matching

    /// The project's own memory key, which an organization project keeps its memory under.
    private static let organizationMemoryPrefix = "org-project:"

    private static func owner(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return value
    }

    /// Whether a memory item or source's project names this one, by its id, folder, name or organization key.
    static func belongs(_ value: String, to project: ProjectView) -> Bool {
        if ProjectPageLines.belongs(value, to: project) { return true }
        if !project.path.isEmpty, normalised(value) == normalised(project.path) { return true }
        if let id = project.sharedBy?.id, !id.isEmpty, value == "\(organizationMemoryPrefix)\(id)" { return true }
        return false
    }

    /// Whether a session's repository sits inside the project's folder.
    private static func holds(_ repository: String?, _ project: ProjectView) -> Bool {
        guard let repository, !repository.isEmpty, !project.path.isEmpty else { return false }
        return ShellLines.inside(normalised(repository), project: normalised(project.path))
    }

    /// Whether a folder's name is the project's folder or the project itself.
    private static func named(_ place: String?, _ project: ProjectView) -> Bool {
        guard let place, !place.isEmpty else { return false }
        return place == folderName(project.path) || place == project.name
    }

    private static func folderName(_ path: String) -> String {
        let last = normalised(path).split(separator: "/").last.map(String.init)
        return last ?? path
    }

    private static func normalised(_ path: String) -> String {
        var each = path.replacingOccurrences(of: "\\", with: "/")
        while each.count > 1, each.hasSuffix("/") { each.removeLast() }
        return each
    }

    private static func newestFirst(_ items: [MemoryItemView]) -> [MemoryItemView] {
        items.sorted { $0.createdAt > $1.createdAt }
    }
}
