import Foundation

/// The pages one project opens on, as the console's project view holds them: what it is and what it learned lately,
/// the agents that work in it, what it learned, and what its AI may do. A project is a campaign or a deal as often as a codebase, so none
/// of them is about code. The desktop is one person's, so people show only once this Mac is joined to a workspace.
public enum ProjectPage: String, CaseIterable, Sendable {
    case overview
    /// Left off for now, since its folder shows on the Overview and Files and Connectors are pages of their own.
    case tools
    case agents
    case memory
    case rules

    public var title: String {
        switch self {
        case .overview: "Overview"
        case .tools: "Tools"
        case .agents: "Agents"
        case .memory: "Memory"
        case .rules: "What its AI may do"
        }
    }

    /// One line under the page's title saying what it is for.
    public var summary: String {
        switch self {
        case .overview: "What this project is, what it still needs, and what it learned lately."
        case .tools: "Where this project\u{2019}s work happens, and what its agents learn from."
        case .agents: "The agents that work in this project, and what each is given."
        case .memory: "What its agents learned in this project, and what they know in every project."
        case .rules: "The agents given this project, what they carry, and the rules that hold in it."
        }
    }
}

/// Where the window is inside one project: the project's id and the page of it.
public struct ProjectPlace: Hashable, Sendable {
    public let id: String
    public let page: ProjectPage

    /// A page left off lands on the Overview, so an old route or a switch never opens a hidden page.
    public init(id: String, page: ProjectPage) {
        self.id = id
        self.page = ProjectSidebar.pages.contains(page) ? page : .overview
    }
}

/// The sidebar a project swaps in once it is opened, as the Cloudflare dashboard swaps its own for a domain's: a way
/// back to every project, the project's name, and its own pages.
public enum ProjectSidebar {
    public static let backTitle = "Back to Projects"
    /// The switcher's own way back, said where a person picks which project to be in.
    public static let allTitle = "All projects"
    /// Where Back to Projects lands.
    public static let list = WindowRoute(.workspaces, tab: "projects")
    /// The pages the sidebar lists, with Tools left off for now.
    public static let pages: [ProjectPage] = [.overview, .agents, .memory, .rules]
    /// Said in place of a project's name while the projects are still being read, or once it is gone.
    public static let unnamed = "Project"
    /// Said where a project was open and is no longer among the projects.
    public static let goneTitle = "This project is gone"
    public static let goneLine = "It is no longer among the projects on this Mac. Go back to Projects to open another."

    /// One page of a project, the Overview unless another is named.
    public static func route(_ id: String, _ page: ProjectPage = .overview) -> WindowRoute {
        WindowRoute(list.destination, tab: list.tab, project: ProjectPlace(id: id, page: page))
    }

    /// The project the window is inside, nil anywhere else, which keeps the usual sidebar.
    public static func place(of route: WindowRoute) -> ProjectPlace? {
        guard route.destination == list.destination, route.tab == list.tab else { return nil }
        return route.project
    }

    /// Where the window is, as the top bar says it: Projects, the project's name, then the page.
    public static func breadcrumb(_ place: ProjectPlace, name: String?) -> [String] {
        ["Projects", name.flatMap { $0.isEmpty ? nil : $0 } ?? unnamed, place.page.title]
    }
}
