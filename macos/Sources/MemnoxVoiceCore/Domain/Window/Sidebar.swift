import Foundation

/// A heading of the sidebar and its pages: the top rows stand without one, as the console's do.
public struct SidebarSection: Equatable, Sendable {
    public let group: SidebarGroup
    public let rows: [Destination]

    public var title: String? { group.title }
}

/// One tab of a page's strip: where it goes, what it says, and what the page is for.
public struct StripTab: Equatable, Sendable {
    public let route: WindowRoute
    public let title: String
    public let summary: String
}

/// The window's one navigation, read off `Destinations.all` so the rows, their order, their headings and their words
/// are the contract's and never a second list kept beside it.
public enum Sidebar {
    /// The headings above the foot, in order; the foot is drawn apart, under the runtime's standing.
    public static let sections: [SidebarSection] = [SidebarGroup.top, .govern, .knowledge].map { group in
        SidebarSection(group: group, rows: Destinations.all.filter { $0.group == group }.map(\.id))
    }

    /// The pages at the foot, Settings last.
    public static let foot: [Destination] = Destinations.all.filter { $0.group == .foot }.map(\.id)

    /// The page's tabs the daemon answers now, in the page's order, each with its word and what it is for.
    public static func tabs(_ row: Destination, supports: Supports) -> [StripTab] {
        Destinations.visibleTabs(row, supports: supports).map {
            StripTab(route: WindowRoute(row, tab: $0.id), title: $0.title, summary: $0.summary)
        }
    }

    /// Where a press on the row lands: its first tab shown, the page itself when it has none, nil while it shows nothing.
    public static func target(_ row: Destination, supports: Supports) -> WindowRoute? {
        guard Destinations.isShown(row, supports: supports) else { return nil }
        return tabs(row, supports: supports).first?.route ?? WindowRoute(row)
    }

    /// The strip over a page: its tabs once there are two to choose between, none for Settings, which keeps a tree.
    public static func strip(for route: WindowRoute, supports: Supports) -> [StripTab] {
        guard route.destination != .settings else { return [] }
        let tabs = tabs(route.destination, supports: supports)
        return tabs.count > 1 ? tabs : []
    }
}
