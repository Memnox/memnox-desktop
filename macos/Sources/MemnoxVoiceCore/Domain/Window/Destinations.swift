import Foundation

/// The window's pages, one per row of the sidebar, named and ordered as `shared/ux/contract.json` names them for the
/// console, this Mac, Windows and Linux alike. A page or tab that needs a daemon method shows only once the daemon
/// answers it, so nothing on screen is a promise.
public enum Destination: String, CaseIterable, Sendable {
    case home
    case needsYou = "needs-you"
    case sessions
    case agents
    case projects
    case rules
    case handOver = "hand-over"
    case activity
    case memory
    case connectors
    case settings
}

/// The heading a page sits under in the sidebar: none for the top rows, Govern, Knowledge, or the foot.
public enum SidebarGroup: String, CaseIterable, Sendable {
    case top
    case govern
    case knowledge
    case foot

    /// The heading's words, nil where the rows stand without one, as the console's first rows and its foot do.
    public var title: String? {
        switch self {
        case .top, .foot: nil
        case .govern: "Govern"
        case .knowledge: "Knowledge"
        }
    }
}

/// The headings Settings groups its pages under, as the console's settings tree does.
public enum TabGroupId: String, CaseIterable, Sendable {
    case account
    case devices
    case voice
    case app

    public var title: String {
        switch self {
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
    /// The heading it sits under in Settings' tree; nil on a page's tab strip, which has no headings.
    public let group: TabGroupId?
    /// One line under the pane's title saying what the tab is for.
    public let summary: String
    /// The daemon method this tab reads; nil when the tab needs nothing new.
    public let needs: String?

    public init(id: String, title: String, group: TabGroupId? = nil, summary: String, needs: String? = nil) {
        self.id = id
        self.title = title
        self.group = group
        self.summary = summary
        self.needs = needs
    }
}

/// One heading of Settings' tree and the tabs shown under it now.
public struct TabGroup: Equatable, Sendable {
    public let id: TabGroupId
    public let title: String
    public let tabs: [TabInfo]
}

public struct DestinationInfo: Equatable, Sendable {
    public let id: Destination
    public let title: String
    public let subtitle: String
    /// The SF Symbol on its row, the nearest to the lucide icon the console draws on the same row.
    public let symbol: String
    public let group: SidebarGroup
    /// The daemon method a page with no tabs reads, nil when it needs nothing new.
    public let needs: String?
    public let tabs: [TabInfo]

    public init(id: Destination, title: String, subtitle: String, symbol: String, group: SidebarGroup,
                needs: String? = nil, tabs: [TabInfo] = []) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.group = group
        self.needs = needs
        self.tabs = tabs
    }
}

/// Where the window is: a page, and the tab within it when it has tabs.
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
    /// The page it sits under, shown beside it in the palette; empty for a page itself.
    public let under: String
    /// The digit that opens it with Command, on a page that has one.
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
    /// This Mac is the one machine here, so its service and signing key are a setting rather than a Machines page.
    public static let settingsTabs: [TabInfo] = [
        TabInfo(id: "account", title: "Account", group: .account,
                summary: "Your name, who you are in Memnox Cloud, and what that lets Memnox do on this Mac."),
        TabInfo(id: "permissions", title: "Permissions", group: .account, summary: "What this Mac lets Memnox hear, type and see."),
        TabInfo(id: "connection", title: "This Mac", group: .devices,
                summary: "The Memnox service on this Mac, and the key Touch ID signs with."),
        TabInfo(id: "phones", title: "Phones", group: .devices, summary: "Phones paired with this Mac and what each may do."),
        TabInfo(id: "voice", title: "Voice", group: .voice, summary: "Who thinks for the voice, and the voice it answers in."),
        TabInfo(id: "listening", title: "Listening", group: .voice, summary: "When Memnox listens and how it speaks up."),
        TabInfo(id: "dictation", title: "Dictation", group: .voice,
                summary: "Speak instead of typing, in any app, written the way you would have typed it."),
        TabInfo(id: "appearance", title: "Appearance", group: .app, summary: "Light, dark, or the same as this Mac."),
        TabInfo(id: "help", title: "Help", group: .app, summary: "Rules, a quick test, setup again, and what happened for support."),
    ]

    /// Pages that moved, so a link to one still lands.
    static let moved: [String: WindowRoute] = [
        "overview": WindowRoute(.home),
        "today": WindowRoute(.home),
        "tools": WindowRoute(.agents, tab: "this-computer"),
        "apps": WindowRoute(.connectors, tab: "systems"),
        "machines": WindowRoute(.settings, tab: "connection"),
        "approvals": WindowRoute(.needsYou, tab: "decide-now"),
        "learn": WindowRoute(.needsYou, tab: "decide-now"),
        "governance": WindowRoute(.needsYou, tab: "decide-now"),
    ]

    /// Where the window opens: Home, which holds what needs the person below the greeting.
    public static let landing = WindowRoute(.home)

    public static let all: [DestinationInfo] = [
        DestinationInfo(id: .home, title: "Home", subtitle: "What your agents can do on their own, and what still needs you.",
                        symbol: "house", group: .top),
        DestinationInfo(id: .needsYou, title: "Needs you",
                        subtitle: "What waits on you, oldest first, each saying what the agent wants to do and where.",
                        symbol: "tray", group: .top, tabs: [
                            TabInfo(id: "decide-now", title: "Decide now",
                                    summary: "Calls held for you, and what was read from your sources, waiting for a yes or a no."),
                            TabInfo(id: "kept", title: "Kept for later",
                                    summary: "Questions nobody answered in time, kept so a later yes lets the retry through.",
                                    needs: "waiting-kept"),
                            TabInfo(id: "decided", title: "Decided", summary: "What was answered lately, and by whom.",
                                    needs: "decided"),
                            TabInfo(id: "rule-changes", title: "Rule changes",
                                    summary: "Rules proposed by an agent or a teammate, waiting for your signature.",
                                    needs: "rule-changes"),
                        ]),
        DestinationInfo(id: .sessions, title: "Sessions",
                        subtitle: "Every session on this Mac by status: what needs you, what was stopped, what runs and what finished.",
                        symbol: "rectangle.stack", group: .top),
        DestinationInfo(id: .agents, title: "Agents", subtitle: "The agents on this Mac, what each is for, and what each can reach.",
                        symbol: "cpu", group: .top, tabs: [
                            TabInfo(id: "agents", title: "Agents", summary: "The agents on this Mac and what each can reach.",
                                    needs: "agents"),
                            TabInfo(id: "jobs", title: "Jobs",
                                    summary: "Ready made jobs and the ones you wrote. Pick one, then connect a real agent to do it.",
                                    needs: "profiles"),
                            TabInfo(id: "this-computer", title: "On this computer",
                                    summary: "The agents on this Mac and the apps Memnox can act in as you."),
                        ]),
        DestinationInfo(id: .projects, title: "Projects",
                        subtitle: "Your projects, with the skills, tools, memory and rules each one carries.",
                        symbol: "folder", group: .top),
        DestinationInfo(id: .rules, title: "Rules",
                        subtitle: "For each thing your AI might do, choose Allow, Ask or Deny. Nothing changes until you save and the change is approved.",
                        symbol: "checkmark.shield", group: .govern, tabs: [
                            TabInfo(id: "rules", title: "Rules", summary: "What each agent may do, and what it asks first.",
                                    needs: "rules"),
                            TabInfo(id: "history", title: "History",
                                    summary: "Every change to your rules, and a way back to any of them.", needs: "rules-history"),
                        ]),
        DestinationInfo(id: .handOver, title: "Hand over",
                        subtitle: "What you could let your agents do on their own, what they may spend, and what autopilot gave them.",
                        symbol: "gauge.with.dots.needle.67percent", group: .govern, tabs: [
                            TabInfo(id: "ready", title: "Ready to hand over",
                                    summary: "What you said yes to often enough that it could run without asking."),
                            TabInfo(id: "budgets", title: "Budgets",
                                    summary: "How much each kind of action may happen in a window, and how much has.", needs: "budgets"),
                            TabInfo(id: "autopilot", title: "Autopilot",
                                    summary: "What autopilot let an agent do on its own, and a way to take it back.", needs: "autopilot"),
                        ]),
        DestinationInfo(id: .activity, title: "Activity", subtitle: "What your agents did, newest first, beside what was decided.",
                        symbol: "clock.arrow.circlepath", group: .govern, tabs: [
                            TabInfo(id: "timeline", title: "Timeline",
                                    summary: "What your agents did, newest first, beside what was decided.", needs: "activity"),
                            TabInfo(id: "caught", title: "What was caught",
                                    summary: "What Memnox stopped or would have stopped, and why.", needs: "findings"),
                        ]),
        DestinationInfo(id: .memory, title: "Memory", subtitle: "What your agents know, and the skills they carry.",
                        symbol: "brain", group: .knowledge, tabs: [
                            TabInfo(id: "map", title: "Map",
                                    summary: "Your agents and everything they reach, drawn as one map of what they know and use.",
                                    needs: "memory-facts"),
                            TabInfo(id: "list", title: "List",
                                    summary: "What your agents know, each fact with the evidence it was read from, and the sources it came out of.",
                                    needs: "memory-facts"),
                            TabInfo(id: "layers", title: "Layers",
                                    summary: "MEMORY.md, the router and the skills each project keeps, as the three layers any agent reads.",
                                    needs: "memory-layers"),
                            TabInfo(id: "skills", title: "Skills", summary: "The skills you keep, and the agents each one is given to.",
                                    needs: "skills-hub"),
                        ]),
        DestinationInfo(id: .connectors, title: "Connectors",
                        subtitle: "The tools your agents reach, the files their memory is read from, and the MCP servers they share.",
                        symbol: "square.grid.2x2", group: .knowledge, tabs: [
                            TabInfo(id: "systems", title: "Systems",
                                    summary: "Connect any tool you use as yourself, and see the ones this Mac already reaches."),
                            TabInfo(id: "files", title: "Files",
                                    summary: "Where your agents' memory is read from: notes, instruction files, exports and memory servers.",
                                    needs: "memory-facts"),
                            TabInfo(id: "mcp", title: "MCP servers",
                                    summary: "Servers set up once and given to the agents you choose, and the secrets they use.",
                                    needs: "mcp-hub"),
                        ]),
        DestinationInfo(id: .settings, title: "Settings", subtitle: "This Mac, your account, and the voice.",
                        symbol: "gearshape", group: .foot, tabs: settingsTabs),
    ]

    public static func info(_ id: Destination) -> DestinationInfo {
        // Every Destination is listed above, so the lookup always lands.
        all.first { $0.id == id }!
    }

    /// The digit that opens a page with Command: the first nine rows of the sidebar, in its order.
    public static func key(_ id: Destination) -> String? {
        guard let at = all.firstIndex(where: { $0.id == id }), at < 9 else { return nil }
        return String(at + 1)
    }

    /// Whether a page shows now: one with tabs while any tab does, one without while its own method is answered.
    public static func isShown(_ id: Destination, supports: Supports) -> Bool {
        let page = info(id)
        if !page.tabs.isEmpty { return !visibleTabs(id, supports: supports).isEmpty }
        guard let needs = page.needs else { return true }
        return supports(needs) == true
    }

    /// The tabs shown now: those needing nothing, and those whose method the daemon answered.
    public static func visibleTabs(_ id: Destination, supports: Supports) -> [TabInfo] {
        info(id).tabs.filter { tab in
            guard let needs = tab.needs else { return true }
            return supports(needs) == true
        }
    }

    /// Settings' tabs shown now under their headings, in the order the headings first appear.
    public static func tabGroups(_ id: Destination, supports: Supports) -> [TabGroup] {
        var groups: [(id: TabGroupId, tabs: [TabInfo])] = []
        for tab in visibleTabs(id, supports: supports) {
            guard let group = tab.group else { continue }
            if let at = groups.firstIndex(where: { $0.id == group }) {
                groups[at].tabs.append(tab)
            } else {
                groups.append((group, [tab]))
            }
        }
        return groups.map { TabGroup(id: $0.id, title: $0.id.title, tabs: $0.tabs) }
    }

    /// The tab a route names, for the pane's own header.
    public static func tab(of route: WindowRoute) -> TabInfo? {
        info(route.destination).tabs.first { $0.id == route.tab }
    }

    /// The route as it will be drawn: a missing or hidden tab falls back to the first one shown.
    public static func settled(_ route: WindowRoute, supports: Supports) -> WindowRoute {
        let tabs = visibleTabs(route.destination, supports: supports)
        guard let first = tabs.first else { return WindowRoute(route.destination, project: route.project) }
        let tab = tabs.first { $0.id == route.tab } ?? first
        // A project's page stays open while its tab is still the one shown.
        return WindowRoute(route.destination, tab: tab.id, project: tab.id == route.tab ? route.project : nil)
    }

    /// A page an old link names, as a route: moved pages land where they went, the rest under Settings or as a page.
    public static func route(forPage name: String) -> WindowRoute? {
        if let moved = moved[name] { return moved }
        if settingsTabs.contains(where: { $0.id == name }) { return WindowRoute(.settings, tab: name) }
        return Destination(rawValue: name).map { WindowRoute($0) }
    }

    /// Every place the palette can go, in sidebar order, each page with its tabs under it.
    public static func commands(supports: Supports) -> [PaletteCommand] {
        all.filter { isShown($0.id, supports: supports) }.flatMap { each -> [PaletteCommand] in
            let top = PaletteCommand(route: WindowRoute(each.id), title: each.title, under: "", key: key(each.id))
            let tabs = visibleTabs(each.id, supports: supports).map {
                PaletteCommand(route: WindowRoute(each.id, tab: $0.id), title: $0.title, under: each.title)
            }
            return [top] + tabs
        }
    }

    /// The commands whose title or page contains every word typed, best first.
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
