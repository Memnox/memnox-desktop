import Foundation

/// The rows the window's sidebar holds, named as the web console's sidebar names them, so a person moving between the
/// two finds the same page under the same word.
public enum SidebarRowId: String, CaseIterable, Sendable {
    case home
    case projects
    case waiting
    case activity
    case agents
    case protection
    case memory
    case skills
    case servers
    case connectors
    case files

    public var title: String {
        switch self {
        case .home: "Home"
        case .projects: "Projects"
        case .waiting: "Needs your attention"
        case .activity: "Activity"
        case .agents: "AI agents"
        case .protection: "Protection settings"
        case .memory: "Memory"
        case .skills: "Skills"
        case .servers: "MCP servers"
        case .connectors: "Connectors"
        case .files: "Files"
        }
    }
}

/// One page a row opens, and the word its tab says when the row holds more than one.
public struct SidebarPage: Equatable, Sendable {
    public let route: WindowRoute
    /// The tab's word, nil to take the destination tab's own title.
    public let title: String?

    public init(_ route: WindowRoute, title: String? = nil) {
        self.route = route
        self.title = title
    }
}

public struct SidebarRow: Equatable, Sendable {
    public let id: SidebarRowId
    /// The pages it opens, the first shown being where a press on the row lands; more than one become a tab strip.
    public let pages: [SidebarPage]

    public var title: String { id.title }
}

/// A heading of the sidebar and its rows; the first section stands without a heading, as the console's does.
public struct SidebarSection: Equatable, Sendable {
    public let title: String?
    public let rows: [SidebarRow]
}

/// One tab of a page's strip: where it goes, what it says, and what the page is for.
public struct StripTab: Equatable, Sendable {
    public let route: WindowRoute
    public let title: String
    public let summary: String
}

public enum Sidebar {
    public static let sections: [SidebarSection] = [
        SidebarSection(title: nil, rows: [
            // Home is one page, since what Today showed now sits on it below the greeting, so no strip shows.
            SidebarRow(id: .home, pages: [SidebarPage(WindowRoute(.home))]),
            SidebarRow(id: .projects, pages: [SidebarPage(WindowRoute(.workspaces, tab: "projects"))]),
            SidebarRow(id: .waiting, pages: [SidebarPage(WindowRoute(.governance, tab: "approvals")),
                                             SidebarPage(WindowRoute(.governance, tab: "learn"))]),
            SidebarRow(id: .activity, pages: [SidebarPage(WindowRoute(.governance, tab: "activity"))]),
        ]),
        SidebarSection(title: "Your AI", rows: [
            // An agent's sessions and what this Mac holds are about the agents, so they are tabs here.
            SidebarRow(id: .agents, pages: [SidebarPage(WindowRoute(.agents, tab: "list")),
                                            SidebarPage(WindowRoute(.agents, tab: "profiles")),
                                            SidebarPage(WindowRoute(.agents, tab: "sessions")),
                                            SidebarPage(WindowRoute(.agents, tab: "computer"))]),
            SidebarRow(id: .protection, pages: [SidebarPage(WindowRoute(.governance, tab: "policies"))]),
            // One row for memory, opening on the map, with the list and the layers as its tabs, so the strip is its only switch.
            SidebarRow(id: .memory, pages: [SidebarPage(WindowRoute(.workspaces, tab: "map")),
                                            SidebarPage(WindowRoute(.workspaces, tab: "memory"), title: "List"),
                                            SidebarPage(WindowRoute(.workspaces, tab: "layers"))]),
            // A row of its own, as the console keeps one, since a page behind another row's tab is one nobody finds.
            SidebarRow(id: .skills, pages: [SidebarPage(WindowRoute(.workspaces, tab: "skills")),
                                            SidebarPage(WindowRoute(.workspaces, tab: "assigned"))]),
            SidebarRow(id: .servers, pages: [SidebarPage(WindowRoute(.mcp, tab: "servers")),
                                             SidebarPage(WindowRoute(.mcp, tab: "clients")),
                                             SidebarPage(WindowRoute(.mcp, tab: "secrets"))]),
        ]),
        // Meetings stays out until this Mac has a page for them, so no row leads nowhere, and Organization with it
        // since People has no page here either; Settings stands at the foot instead.
        SidebarSection(title: "Connected tools", rows: [
            SidebarRow(id: .connectors, pages: [SidebarPage(WindowRoute(.mcp, tab: "apps"))]),
            SidebarRow(id: .files, pages: [SidebarPage(WindowRoute(.workspaces, tab: "sources"))]),
        ]),
    ]

    public static var rows: [SidebarRow] { sections.flatMap(\.rows) }

    /// The row a route sits under, nil for Settings, which keeps its own tree in the page.
    public static func row(of route: WindowRoute) -> SidebarRow? {
        rows.first { row in row.pages.contains { $0.route == route } }
    }

    /// The row's pages the daemon answers now, in the row's order, each with its word and what it is for.
    public static func tabs(_ row: SidebarRow, supports: Supports) -> [StripTab] {
        row.pages.compactMap { page in
            let route = page.route
            guard let tab = route.tab else {
                let info = Destinations.info(route.destination)
                return StripTab(route: route, title: page.title ?? info.title, summary: info.subtitle)
            }
            return Destinations.visibleTabs(route.destination, supports: supports)
                .first { $0.id == tab }
                .map { StripTab(route: route, title: page.title ?? $0.title, summary: $0.summary) }
        }
    }

    /// Where a press on the row lands: its first page shown, nil while the daemon answers none of them.
    public static func target(_ row: SidebarRow, supports: Supports) -> WindowRoute? {
        tabs(row, supports: supports).first?.route
    }

    /// The strip over a page: the tabs of its row once there are two to choose between, otherwise none.
    public static func strip(for route: WindowRoute, supports: Supports) -> [StripTab] {
        guard let row = row(of: route) else { return [] }
        let tabs = tabs(row, supports: supports)
        return tabs.count > 1 ? tabs : []
    }
}
