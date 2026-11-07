import Foundation

/// The rail headings a project's Tools page groups its cards under, by what the tool is for rather than how it is
/// reached, so a repository sits beside the files and channels as one more place the work lives.
public enum ProjectToolCategory: String, CaseIterable, Sendable {
    case conversations
    case writing
    case tracking
    case building

    public var title: String {
        switch self {
        case .conversations: "Conversations"
        case .writing: "Files and docs"
        case .tracking: "Work tracking"
        case .building: "Code and apps"
        }
    }
}

/// One card of a project's Tools page: a kind of tool, what it is for, and how one is added.
public enum ProjectToolSlot: String, CaseIterable, Sendable {
    case files
    case docs
    case channels
    case meetings
    case tickets
    case apps
    case repositories

    public var title: String {
        switch self {
        case .files: "Files"
        case .docs: "Docs"
        case .channels: "Channels"
        case .meetings: "Meetings"
        case .tickets: "Tickets"
        case .apps: "Apps"
        case .repositories: "Repositories"
        }
    }

    public var summary: String {
        switch self {
        case .files: "Notes and folders its AI reads, such as a vault or a shared drive."
        case .docs: "Pages where it is written down, such as Notion or exported docs."
        case .channels: "Where the team talks it through, such as Slack channels."
        case .meetings: "Calls whose notes and decisions belong to it."
        case .tickets: "The boards and tickets that track the work."
        case .apps: "Tools its AI can reach and act in, such as Linear, a database or a design tool."
        case .repositories: "Where its code lives, when it has any."
        }
    }

    public var category: ProjectToolCategory {
        switch self {
        case .channels, .meetings: .conversations
        case .files, .docs: .writing
        case .tickets: .tracking
        case .apps, .repositories: .building
        }
    }

    /// A team's tool, linked to a project only in Memnox Cloud, so it waits behind `ProjectToolCatalog.showsTeamTools`.
    public var isTeamTool: Bool {
        switch self {
        case .channels, .meetings, .tickets: true
        case .files, .docs, .apps, .repositories: false
        }
    }

    /// How one is added: on this Mac where the runtime can save it, in Memnox Cloud once this Mac is joined to a
    /// workspace, and nil where neither can, so a Mac on its own never shows an action that only opens the cloud.
    public func adding(joined: Bool) -> ProjectToolAdding? {
        switch self {
        case .files, .docs: .files
        case .apps: .apps
        case .channels, .meetings, .tickets, .repositories: joined ? .cloud : nil
        }
    }

    /// The card's add action, in its words.
    public var addTitle: String {
        switch self {
        case .files: "Add files"
        case .docs: "Add docs"
        case .channels: "Add channels"
        case .meetings: "Add meetings"
        case .tickets: "Add tickets"
        case .apps: "Add an app"
        case .repositories: "Add a repository"
        }
    }
}

/// Where a card's add action takes the person.
public enum ProjectToolAdding: Equatable, Sendable {
    /// The Files page, where a folder or an export is pointed at.
    case files
    /// An app of this Mac's hub, put into the project's own setup on the card itself.
    case apps
    /// Memnox Cloud, since this Mac cannot connect it to a project.
    case cloud
}

/// A card and what is linked to it now.
public struct ProjectToolCard: Equatable, Identifiable, Sendable {
    public let slot: ProjectToolSlot
    public let linked: [ProjectTool]

    public var id: String { slot.rawValue }
}

/// The Tools page as the Connectors page lays out its own: a card per kind of tool with a categories rail and a search.
/// Left off for now with `ProjectPage.tools`, so no page reads it.
public enum ProjectToolCatalog {
    /// Channels, meetings and tickets stay off the page for now, since nothing on one Mac links them; they come back
    /// once user feedback says how a team wants them here.
    public static let showsTeamTools = false

    /// Every card in the page's order, each with what this Mac knows is linked to it.
    public static func cards(_ project: ProjectView, sources: [MemorySourceView]) -> [ProjectToolCard] {
        let tools = ProjectPageLines.tools(project, sources: sources)
        return ProjectToolSlot.allCases.filter { showsTeamTools || !$0.isTeamTool }.map { slot in
            ProjectToolCard(slot: slot, linked: tools.filter { self.slot(of: $0.kind) == slot })
        }
    }

    /// The cards in a category matching what was typed, against the card's words and the names linked to it.
    public static func shown(_ cards: [ProjectToolCard], category: ProjectToolCategory?, query: String) -> [ProjectToolCard] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return cards.filter { card in
            guard category == nil || card.slot.category == category else { return false }
            let text = ([card.slot.title, card.slot.summary] + card.linked.map(\.name)).joined(separator: " ").lowercased()
            return words.allSatisfy { text.contains($0) }
        }
    }

    /// The rail's rows: each category with how many cards it holds, in the categories' own order.
    public static func categories(_ cards: [ProjectToolCard]) -> [(id: String, title: String, count: Int)] {
        ProjectToolCategory.allCases.compactMap { category in
            let count = cards.filter { $0.slot.category == category }.count
            return count == 0 ? nil : (category.rawValue, category.title, count)
        }
    }

    /// The card's status line: what is linked, by name, or that nothing is yet.
    public static func linkedLine(_ card: ProjectToolCard) -> String {
        let names = card.linked.map(\.name)
        switch names.count {
        case 0: return "Nothing linked yet"
        case 1: return "\(names[0]) linked"
        case 2: return "\(names[0]) and \(names[1]) linked"
        default: return "\(names[0]), \(names[1]) and \(names.count - 2) more linked"
        }
    }

    private static func slot(of kind: ProjectToolKind) -> ProjectToolSlot {
        switch kind {
        case .notes, .instructions: .files
        case .docs, .memoryService: .docs
        case .app: .apps
        case .repository, .folder: .repositories
        }
    }
}
