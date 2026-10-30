import Foundation

/// The Memnox window's five destinations and Settings, the same on the Mac, Windows and Linux. A tab that needs a
/// daemon method is shown only once the daemon answers it, so nothing on screen is a promise.
public enum Destination: String, CaseIterable, Sendable {
    case home
    case agents
    case workspaces
    case mcp
    case governance
    case settings
}

public struct TabInfo: Equatable, Sendable {
    public let id: String
    public let title: String
    /// The daemon method this tab reads; nil when the tab needs nothing new.
    public let needs: String?

    public init(id: String, title: String, needs: String? = nil) {
        self.id = id
        self.title = title
        self.needs = needs
    }
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

    public init(_ destination: Destination, tab: String? = nil) {
        self.destination = destination
        self.tab = tab
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

    public var id: WindowRoute { route }
}

public enum Destinations {
    /// What stays under Settings, in the order the sidebar groups had them.
    public static let settingsTabs: [TabInfo] = [
        TabInfo(id: "account", title: "Account"),
        TabInfo(id: "permissions", title: "Permissions"),
        TabInfo(id: "connection", title: "Connection"),
        TabInfo(id: "phones", title: "Phones"),
        TabInfo(id: "network", title: "Local network", needs: "lan-status"),
        TabInfo(id: "appearance", title: "Appearance"),
        TabInfo(id: "backup", title: "Backup"),
        TabInfo(id: "sync", title: "Personal sync", needs: "personal-sync-status"),
        TabInfo(id: "voice", title: "Voice"),
        TabInfo(id: "listening", title: "Listening"),
        TabInfo(id: "dictation", title: "Dictation"),
        TabInfo(id: "help", title: "Help"),
    ]

    /// Pages that moved out of Settings into a destination, so a link to one still lands.
    static let moved: [String: WindowRoute] = [
        "overview": WindowRoute(.home),
        "tools": WindowRoute(.agents, tab: "computer"),
        "apps": WindowRoute(.mcp, tab: "apps"),
    ]

    public static let all: [DestinationInfo] = [
        DestinationInfo(id: .home, title: "Home", subtitle: "What is running, what needs you, and where to carry on.",
                        key: "1", tabs: []),
        DestinationInfo(id: .agents, title: "Agents", subtitle: "The agents on this Mac, their sessions, and what each can reach.",
                        key: "2", tabs: [
                            TabInfo(id: "list", title: "Agents", needs: "agents"),
                            TabInfo(id: "sessions", title: "Sessions"),
                            TabInfo(id: "computer", title: "On this computer"),
                        ]),
        DestinationInfo(id: .workspaces, title: "Workspaces",
                        subtitle: "Your projects, with the skills, tools, memory and rules each one carries.",
                        key: "3", tabs: [
                            TabInfo(id: "projects", title: "Workspaces"),
                            TabInfo(id: "memory", title: "Memory", needs: "memory-facts"),
                            TabInfo(id: "skills", title: "My Skills", needs: "skills-hub"),
                            TabInfo(id: "assigned", title: "Assigned", needs: "skills-hub"),
                        ]),
        DestinationInfo(id: .mcp, title: "MCP Hub", subtitle: "Servers set up once and given to the agents you choose.",
                        key: "4", tabs: [
                            TabInfo(id: "servers", title: "Servers", needs: "mcp-hub"),
                            TabInfo(id: "clients", title: "Clients", needs: "mcp-hub"),
                            TabInfo(id: "secrets", title: "Secrets", needs: "mcp-hub"),
                            TabInfo(id: "apps", title: "Your apps"),
                        ]),
        DestinationInfo(id: .governance, title: "Governance",
                        subtitle: "What your agents may do, what waits on you, and what happened.",
                        key: "5", tabs: [
                            TabInfo(id: "approvals", title: "Approvals"),
                            TabInfo(id: "policies", title: "Policies", needs: "rules"),
                            TabInfo(id: "activity", title: "Activity", needs: "activity"),
                            TabInfo(id: "learn", title: "Learn", needs: "memory-learn"),
                        ]),
        DestinationInfo(id: .settings, title: "Settings", subtitle: "This Mac, your account, and the voice.",
                        key: nil, tabs: settingsTabs),
    ]

    public static func info(_ id: Destination) -> DestinationInfo {
        // Every Destination is listed above, so the lookup always lands.
        all.first { $0.id == id }!
    }

    /// The tabs shown now: those needing nothing, and those whose method the daemon answered.
    public static func visibleTabs(_ id: Destination, supports: Supports) -> [TabInfo] {
        info(id).tabs.filter { tab in
            guard let needs = tab.needs else { return true }
            return supports(needs) == true
        }
    }

    /// The route as it will be drawn: a missing or hidden tab falls back to the first one shown.
    public static func settled(_ route: WindowRoute, supports: Supports) -> WindowRoute {
        let tabs = visibleTabs(route.destination, supports: supports)
        guard let first = tabs.first else { return WindowRoute(route.destination) }
        let tab = tabs.first { $0.id == route.tab } ?? first
        return WindowRoute(route.destination, tab: tab.id)
    }

    /// A page an old Settings link names, as a route: moved pages land on their destination, the rest under Settings.
    public static func route(forPage name: String) -> WindowRoute? {
        if let moved = moved[name] { return moved }
        if settingsTabs.contains(where: { $0.id == name }) { return WindowRoute(.settings, tab: name) }
        return Destination(rawValue: name).map { WindowRoute($0) }
    }

    /// Every place the palette can go, in sidebar order.
    public static func commands(supports: Supports) -> [PaletteCommand] {
        all.flatMap { each -> [PaletteCommand] in
            let top = PaletteCommand(route: WindowRoute(each.id), title: each.title, under: "")
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
