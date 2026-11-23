import Foundation

/// Making a project as three questions anyone can answer, and one optional box: what the work is called, where it
/// lives, how careful agents should be there, and what agents there should always know. Each has an answer to skip to.
public enum NewProject {
    public static let title = "New project"
    public static let nameQuestion = "What is this work called?"
    public static let namePrompt = "Such as Website, Invoicing or Support inbox"
    public static let placeQuestion = "Where does it live?"
    public static let placeLine = "The folder on this Mac its files are in. Agents working there count as working on it."
    /// Said where a folder would be, since a project on this Mac is a folder; work with none lives in Memnox Cloud.
    public static let noFolderLine = "Work with no folder, done by cloud or no code agents, is a shared project in Memnox Cloud."
    public static let careQuestion = "How careful should agents be here?"
    public static let knowQuestion = "Anything agents here should always know?"
    public static let knowLine = "One thing per line, such as: refunds over 500 dollars go to finance. You can skip this."
    public static let create = "Make the project"

    /// The name typed, else the folder's own name, so skipping the first question still names it.
    public static func name(typed: String, folder: String) -> String {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return URL(fileURLWithPath: folder).lastPathComponent
    }

    /// What agents should always know, one line each, blank lines dropped.
    public static func instructions(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The manifest under the name answered, everything else the folder already had kept; nil where it is the same.
    public static func draft(of project: ProjectView, name: String) -> ProjectDraft? {
        ProjectPageLines.draft(of: project, renamed: name)
    }

    /// Said once what agents should know is kept.
    public static func remembered(_ count: Int) -> String {
        count == 1 ? "Agents here will know that from now on." : "Agents here will know those \(count) things from now on."
    }
}
