import Foundation

/// The Memnox window's five destinations and Settings, the same on the Mac, Windows and Linux. A tab that needs a
/// daemon method is shown only once the daemon answers it, so nothing on screen is a promise.
public enum Destination: String, CaseIterable, Sendable {
    /// What Today showed now sits on Home, so this stays only for old links, which land on Home.
    case today
    case home
    case agents
    case workspaces
    case mcp
    case governance
    case settings
}

/// The headings a destination's sub navigation groups its tabs under, as the console's settings tree does.
public enum TabGroupId: String, CaseIterable, Sendable {
    case agents
    case computer
    case projects
    case knowledge
    case skills
    case hub
    case apps
    case review
    case rules
    case record
    case account
    case devices
    case voice
    case app

    public var title: String {
        switch self {
        case .agents: "Agents"
        case .computer: "This computer"
        case .projects: "Projects"
        case .knowledge: "Knowledge"
        case .skills: "Skills"
        case .hub: "Hub"
        case .apps: "Apps"
        case .review: "Needs your attention"
        case .rules: "Rules"
        case .record: "Record"
        case .account: "Account"
        case .devices: "Devices"
        case .voice: "Voice"
        case .app: "App"
        }
    }
}

public struct TabInfo: Equatable, Sendable {
    public let id: String
    public let title: String
    /// The heading it sits under in the destination's sub navigation.
    public let group: TabGroupId
    /// One line under the pane's title saying what the tab is for.
    public let summary: String
    /// The daemon method this tab reads; nil when the tab needs nothing new.
    public let needs: String?

    public init(id: String, title: String, group: TabGroupId, summary: String, needs: String? = nil) {
        self.id = id
        self.title = title
        self.group = group
        self.summary = summary
        self.needs = needs
    }
}

/// One heading of a destination's sub navigation and the tabs shown under it now.
public struct TabGroup: Equatable, Sendable {
    public let id: TabGroupId
    public let title: String
    public let tabs: [TabInfo]
}

public struct DestinationInfo: Equatable, Sendable {
    public let id: Destination
    public let title: String
    public let subtitle: String
    /// The digit that opens it with Command.
    public let key: Character?
    public let tabs: [TabInfo]
}

/// Where the window is: a destination, and the tab within it when it has tabs.
public struct WindowRoute: Hashable, Sendable {
    public let destination: Destination
    public let tab: String?
    /// One project opened from Projects and the page of it shown, which swaps the sidebar for the project's own.
    public let project: ProjectPlace?

    public init(_ destination: Destination, tab: String? = nil, project: ProjectPlace? = nil) {
        self.destination = destination
        self.tab = tab
        self.project = project
    }
}

/// Whether the daemon answers a method: true, false, or nil while nobody has asked yet.
public typealias Supports = (String) -> Bool?

/// One place the command palette can go.
public struct PaletteCommand: Equatable, Identifiable, Sendable {
    public let route: WindowRoute
    public let title: String
    /// The destination it sits under, shown beside it in the palette; empty for a destination itself.
    public let under: String
    /// The digit that opens it with Command, on a destination that has one.
    public let key: String?

    public init(route: WindowRoute, title: String, under: String, key: String? = nil) {
        self.route = route
        self.title = title
        self.under = under
        self.key = key
    }

    public var id: WindowRoute { route }
}

public enum Destinations {
    /// What stays under Settings, grouped by who a change is about: the person, their devices, the voice, or this app.
    public static let settingsTabs: [TabInfo] = [
        TabInfo(id: "account", title: "Account", group: .account,
                summary: "Your name, who you are in Memnox Cloud, and what that lets Memnox do on this Mac."),
        TabInfo(id: "permissions", title: "Permissions", group: .account, summary: "What this Mac lets Memnox hear, type and see."),
        TabInfo(id: "connection", title: "Connection", group: .account,
                summary: "The Memnox service your agents talk to, and the key Touch ID signs with."),
        TabInfo(id: "phones", title: "Phones", group: .devices, summary: "Phones paired with this Mac and what each may do."),
        // Local network is left off for now, since phones reach this Mac through the relay without a setting.
        TabInfo(id: "sync", title: "Personal sync", group: .devices,
                summary: "Your own setup carried between your machines, sealed under a key only they hold.", needs: "personal-sync-status"),
        TabInfo(id: "voice", title: "Voice", group: .voice, summary: "Who thinks for the voice, and the voice it answers in."),
        TabInfo(id: "listening", title: "Listening", group: .voice, summary: "When Memnox listens and how it speaks up."),
        TabInfo(id: "dictation", title: "Dictation", group: .voice,
                summary: "Speak instead of typing, in any app, written the way you would have typed it."),
        TabInfo(id: "appearance", title: "Appearance", group: .app, summary: "Light, dark, or the same as this Mac."),
        // Backup is left off for now, so nobody leans on a restore that has not been tried end to end.
        TabInfo(id: "help", title: "Help", group: .app, summary: "Rules, a quick test, and what happened for support."),
    ]

    /// Pages that moved out of Settings into a destination, so a link to one still lands.
    static let moved: [String: WindowRoute] = [
        "overview": WindowRoute(.home),
        "tools": WindowRoute(.agents, tab: "computer"),
        "apps": WindowRoute(.mcp, tab: "apps"),
    ]

    /// Where the window opens: Home, which holds what needs the person today below the greeting.
    public static let landing = WindowRoute(.home)

    public static let all: [DestinationInfo] = [
        DestinationInfo(id: .today, title: "Today", subtitle: "What needs you today, the most urgent first, and what your agents did.",
                        key: nil, tabs: []),
        DestinationInfo(id: .home, title: "Home", subtitle: "What is running, what needs you, and where to carry on.",
                        key: "1", tabs: []),
        DestinationInfo(id: .agents, title: "AI agents", subtitle: "The agents on this Mac, their sessions, and what each can reach.",
                        key: "2", tabs: [
                            TabInfo(id: "list", title: "Agents", group: .agents,
                                    summary: "The agents on this Mac and what each can reach.", needs: "agents"),
                            TabInfo(id: "profiles", title: "Jobs", group: .agents,
                                    summary: "What each agent is for, who answers for it, and the agents each job works through.",
                                    needs: "profiles"),
                            TabInfo(id: "work", title: "Work", group: .agents,
                                    summary: "Which agent carries which issue, where it stands, and what waits on you.",
                                    needs: "agent-work"),
                            TabInfo(id: "sessions", title: "Sessions", group: .agents,
                                    summary: "What each agent is doing: what needs you, what runs, and what is done."),
                            TabInfo(id: "computer", title: "On this computer", group: .computer,
                                    summary: "The agents on this Mac and the apps Memnox can act in as you."),
                        ]),
        DestinationInfo(id: .workspaces, title: "Projects",
                        subtitle: "Your projects, with the skills, tools, memory and rules each one carries.",
                        key: "3", tabs: [
                            TabInfo(id: "projects", title: "Projects", group: .projects,
                                    summary: "Your projects, with the skills, tools, memory and rules each one carries."),
                            // The agents and all they reach as one map, its own page so it is one press from the sidebar.
                            TabInfo(id: "map", title: "Map", group: .knowledge,
                                    summary: "Your agents and everything they reach, drawn as one map of what they know and use.",
                                    needs: "memory-facts"),
                            TabInfo(id: "memory", title: "Memory", group: .knowledge,
                                    summary: "What your agents know, each fact with the evidence it was read from, and the sources it came out of.",
                                    needs: "memory-facts"),
                            TabInfo(id: "layers", title: "Layers", group: .knowledge,
                                    summary: "MEMORY.md, the router and the skills each project keeps, as the three layers any agent reads.",
                                    needs: "memory-layers"),
                            TabInfo(id: "sources", title: "Files", group: .knowledge,
                                    summary: "Where your agents' memory is read from: notes, instruction files, exports and memory servers.",
                                    needs: "memory-facts"),
                            TabInfo(id: "skills", title: "My Skills", group: .skills,
                                    summary: "The skills you keep, and the agents each one is given to.", needs: "skills-hub"),
                            TabInfo(id: "assigned", title: "Assigned", group: .skills, summary: "Which skills each agent carries.",
                                    needs: "skills-hub"),
                            // Discover is left off for now, since the marketplace holds no listing yet, and Profiles too,
                            // since a bundle handed across a team is kept in Memnox Cloud rather than on one person's Mac.
                        ]),
        DestinationInfo(id: .mcp, title: "MCP Hub", subtitle: "Servers set up once and given to the agents you choose.",
                        key: "4", tabs: [
                            // Servers, Clients and Secrets stand as the MCP servers row, Connectors as a row of its own.
                            TabInfo(id: "servers", title: "Servers", group: .hub,
                                    summary: "Servers set up once and given to the agents you choose.", needs: "mcp-hub"),
                            TabInfo(id: "clients", title: "Clients", group: .hub, summary: "Which agent has which server, set in one place.",
                                    needs: "mcp-hub"),
                            TabInfo(id: "secrets", title: "Secrets", group: .hub,
                                    summary: "Each secret by name, where it is used, and whether this Mac holds it.", needs: "mcp-hub"),
                            TabInfo(id: "apps", title: "Connectors", group: .apps,
                                    summary: "Connect any tool you use as yourself, and see the ones this Mac already reaches."),
                        ]),
        DestinationInfo(id: .governance, title: "Governance",
                        subtitle: "What your agents may do, what waits on you, and what happened.",
                        key: "5", tabs: [
                            TabInfo(id: "approvals", title: "Approvals", group: .review,
                                    summary: "What waits on you, oldest first, each saying what the agent wants to do and where."),
                            TabInfo(id: "policies", title: "Protection settings", group: .rules,
                                    summary: "For each thing your AI might do, choose Allow, Ask or Deny. Nothing changes until you save and the change is approved.", needs: "rules"),
                            TabInfo(id: "activity", title: "Activity", group: .record,
                                    summary: "What your agents did, newest first, beside what was decided.", needs: "activity"),
                            TabInfo(id: "learn", title: "Learn", group: .review,
                                    summary: "What was read out of your sources, waiting for you to confirm or reject it.", needs: "memory-learn"),
                        ]),
        DestinationInfo(id: .settings, title: "Settings", subtitle: "This Mac, your account, and the voice.",
                        key: nil, tabs: settingsTabs),
    ]

    public static func info(_ id: Destination) -> DestinationInfo {
        // Every Destination is listed above, so the lookup always lands.
        all.first { $0.id == id }!
    }

    /// Pages left off for now, so the window stays straightforward and nobody gets lost; each still settles on its
    /// destination's first tab shown, so an old link lands somewhere.
    /// Learn and Secrets stay shown, since memory read from a source waits in Learn to be confirmed and a server that
    /// needs a secret is set up only under Secrets; hiding either left the pages that send people there a dead end.
    public static let leftOff: Set<WindowRoute> = [
        WindowRoute(.mcp, tab: "clients"),
        WindowRoute(.workspaces, tab: "assigned"),
        WindowRoute(.agents, tab: "sessions"),
        WindowRoute(.settings, tab: "sync"),
    ]

    /// The tabs shown now: those needing nothing, and those whose method the daemon answered, past the ones left off.
    public static func visibleTabs(_ id: Destination, supports: Supports) -> [TabInfo] {
        info(id).tabs.filter { tab in
            if leftOff.contains(WindowRoute(id, tab: tab.id)) { return false }
            guard let needs = tab.needs else { return true }
            return supports(needs) == true
        }
    }

    /// The tabs shown now under their headings, in the order the headings first appear, an empty heading dropped so a
    /// group never stands over nothing.
    public static func tabGroups(_ id: Destination, supports: Supports) -> [TabGroup] {
        var groups: [(id: TabGroupId, tabs: [TabInfo])] = []
        for tab in visibleTabs(id, supports: supports) {
            if let at = groups.firstIndex(where: { $0.id == tab.group }) {
                groups[at].tabs.append(tab)
            } else {
                groups.append((tab.group, [tab]))
            }
        }
        return groups.map { TabGroup(id: $0.id, title: $0.id.title, tabs: $0.tabs) }
    }

    /// The tab a route names, with its heading, for the pane's own header.
    public static func tab(of route: WindowRoute) -> (tab: TabInfo, group: String)? {
        guard let tab = info(route.destination).tabs.first(where: { $0.id == route.tab }) else { return nil }
        return (tab, tab.group.title)
    }

    /// The route as it will be drawn: a missing or hidden tab falls back to the first one shown.
    public static func settled(_ route: WindowRoute, supports: Supports) -> WindowRoute {
        if route.destination == .today { return WindowRoute(.home) }
        let tabs = visibleTabs(route.destination, supports: supports)
        guard let first = tabs.first else { return WindowRoute(route.destination) }
        let tab = tabs.first { $0.id == route.tab } ?? first
        // A project's page stays open while its tab is still the one shown.
        return WindowRoute(route.destination, tab: tab.id, project: tab.id == route.tab ? route.project : nil)
    }

    /// A page an old Settings link names, as a route: moved pages land on their destination, the rest under Settings.
    public static func route(forPage name: String) -> WindowRoute? {
        if let moved = moved[name] { return moved }
        if name == Destination.today.rawValue { return WindowRoute(.home) }
        if settingsTabs.contains(where: { $0.id == name }) { return WindowRoute(.settings, tab: name) }
        return Destination(rawValue: name).map { WindowRoute($0) }
    }

    /// Every place the palette can go, in sidebar order.
    public static func commands(supports: Supports) -> [PaletteCommand] {
        // Today folded into Home, so the palette offers Home alone for both.
        all.filter { $0.id != .today }.flatMap { each -> [PaletteCommand] in
            let top = PaletteCommand(route: WindowRoute(each.id), title: each.title, under: "", key: each.key.map(String.init))
            let tabs = visibleTabs(each.id, supports: supports).map {
                PaletteCommand(route: WindowRoute(each.id, tab: $0.id), title: $0.title, under: each.title)
            }
            return [top] + tabs
        }
    }

    /// The commands whose title or destination contains every word typed, best first.
    public static func matchCommands(_ query: String, supports: Supports) -> [PaletteCommand] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        let every = commands(supports: supports)
        guard let first = words.first else { return every }
        let matching = every.filter { each in
            let text = "\(each.title) \(each.under)".lowercased()
            return words.allSatisfy { text.contains($0) }
        }
        // A title that starts with what was typed is the likelier aim; the rest keep their sidebar order.
        let starting = matching.filter { $0.title.lowercased().hasPrefix(first) }
        let rest = matching.filter { !$0.title.lowercased().hasPrefix(first) }
        return starting + rest
    }
}

/// Window widths at which the layout changes, the same numbers Windows and Linux use.
public enum WindowWidth {
    public static let wide: Double = 1200
    public static let medium: Double = 900
    public static let narrow: Double = 640
}

/// Wide keeps the inspector beside the page, medium floats it, narrow folds the sidebar to icons, compact to a sheet.
public enum WidthClass: Equatable, Sendable {
    case wide
    case medium
    case narrow
    case compact

    public init(width: Double) {
        if width >= WindowWidth.wide {
            self = .wide
        } else if width >= WindowWidth.medium {
            self = .medium
        } else if width >= WindowWidth.narrow {
            self = .narrow
        } else {
            self = .compact
        }
    }
}

/// How the shell lays itself out at a width: the sidebar with labels, as icons or as a sheet, and the inspector beside
/// the page, floating over it or over the whole window. Mirrors `shellLayout` in `destinations.ts`.
public struct ShellLayout: Equatable, Sendable {
    public enum Sidebar: Equatable, Sendable { case labels, rail, sheet }
    public enum Inspector: Equatable, Sendable { case beside, drawer, full }

    public let sidebar: Sidebar
    public let inspector: Inspector
    /// Whether the sidebar offers to fold, which it does only where labels fit.
    public let canFold: Bool

    public init(sidebar: Sidebar, inspector: Inspector, canFold: Bool) {
        self.sidebar = sidebar
        self.inspector = inspector
        self.canFold = canFold
    }

    public init(_ width: WidthClass, collapsed: Bool) {
        switch width {
        case .wide: self.init(sidebar: collapsed ? .rail : .labels, inspector: .beside, canFold: true)
        case .medium: self.init(sidebar: collapsed ? .rail : .labels, inspector: .drawer, canFold: true)
        case .narrow: self.init(sidebar: .rail, inspector: .full, canFold: false)
        case .compact: self.init(sidebar: .sheet, inspector: .full, canFold: false)
        }
    }
}

/// Where Back and Forward go, as a browser does: a visit drops whatever was ahead.
public struct RouteHistory: Equatable, Sendable {
    private var visited: [WindowRoute]
    private var at = 0

    public init(_ first: WindowRoute) {
        visited = [first]
    }

    public var current: WindowRoute { visited[at] }
    public var canGoBack: Bool { at > 0 }
    public var canGoForward: Bool { at < visited.count - 1 }

    public mutating func visit(_ route: WindowRoute) {
        guard route != current else { return }
        visited = Array(visited.prefix(at + 1)) + [route]
        at = visited.count - 1
    }

    public mutating func back() {
        if canGoBack { at -= 1 }
    }

    public mutating func forward() {
        if canGoForward { at += 1 }
    }
}
