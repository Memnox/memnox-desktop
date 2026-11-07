import Foundation

// What the Memory page says about the workspace's live graph: what each node is, who said it, through which tool and
// when, and whether the picture was read just now or stands on the saved facts. Words only; nothing here decides.

public enum WorkspaceLiveLines {
    /// A date written as the runtime writes it, read by its day.
    private static let dayLength = 10
    private static let secure = "https://"
    /// The most letters a person's initials are drawn with.
    private static let initialsMost = 2

    /// Whether a live node is drawn under the status chip: a decision only under its own standing, and what arrived
    /// under every chip, since the console shows it before anything is settled.
    public static func shows(_ node: WorkspaceGraphNode, under status: MemoryStatus?) -> Bool {
        guard let status else { return true }
        switch node.nodeKind {
        case .decision, .candidate: return LocalGraphs.liveStatus(node) == status
        // A rule set in force is as settled as a verified decision.
        case .policy: return status == .verified
        case .source, .document, .passage, .conversation, .person, .bot, .group, nil: return true
        }
    }

    /// What a node is, said under its name.
    public static func detail(_ node: WorkspaceGraphNode, kind: WorkspaceNodeKind) -> String {
        let tool = node.tool.map { WorkspaceMemoryLines.toolName($0.lowercased()) }
        switch kind {
        case .source: return WorkspaceMemoryLines.toolDetail
        case .document: return tool.map { "Arrived through \($0)" } ?? "Something your workspace took in"
        case .passage: return "A passage of something your workspace took in"
        case .conversation: return tool.map { "A conversation in \($0)" } ?? "A conversation your workspace took in"
        case .person: return "Somebody in your workspace"
        case .bot: return tool.map { "An app in \($0), never a person" } ?? "An app, never a person"
        case .group: return "A team the directory names"
        case .policy: return "A rule set in force"
        case .decision: return "Settled by your team"
        case .candidate: return "Not approved by anyone"
        }
    }

    /// The details of one live node, row by row: what it is, who said it, the tool, when, and how often.
    public static func rows(_ node: WorkspaceGraphNode) -> [(String, String)] {
        var rows: [(String, String)] = []
        if let kind = node.nodeKind { rows.append(("Kind", kindWord(kind))) }
        if let said = node.saidBy { rows.append(("Said by", said)) }
        if let tool = node.tool { rows.append(("Tool", WorkspaceMemoryLines.toolName(tool.lowercased()))) }
        if let at = node.at { rows.append((node.nodeKind == .decision ? "Settled" : "When", day(at))) }
        if let count = node.count { rows.append(("Count", countLine(count, kind: node.nodeKind))) }
        if node.nodeKind == .candidate {
            rows.append(("Standing", "Not approved by anyone, so agents weigh it as context and never as a decision"))
        }
        if let provenance = node.provenance { rows.append(("From", WorkspaceMemoryLines.provenanceWord(provenance))) }
        if node.untrusted { rows.append(("Trust", "Written by somebody your workspace does not know")) }
        return rows
    }

    public static func kindWord(_ kind: WorkspaceNodeKind) -> String {
        switch kind {
        case .source: "Tool"
        case .document: "Arrived"
        case .passage: "Passage"
        case .conversation: "Conversation"
        case .person: "Person"
        case .bot: "App"
        case .group: "Team"
        case .policy: "Rule set"
        case .decision: "Decision"
        case .candidate: "Candidate"
        }
    }

    /// A count said as what it counts: the same words said again, or an author's messages folded into one mark.
    public static func countLine(_ count: Int, kind: WorkspaceNodeKind?) -> String {
        switch kind {
        case .person, .bot: "\(count) messages, counted rather than drawn"
        case .source, .document, .passage, .conversation, .group, .policy, .decision, .candidate, nil: "Said \(count) times"
        }
    }

    /// The badge on a mark: the count itself, short.
    public static func badge(_ count: Int) -> String { "×\(count)" }

    /// Where a live node can be opened, only a secure link.
    public static func link(_ node: WorkspaceGraphNode) -> URL? {
        guard let href = node.href, href.hasPrefix(secure) else { return nil }
        return URL(string: href)
    }

    /// What a person's mark wears when the workspace sends no picture: the first letters of their first two names.
    public static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "_" || $0 == "-" })
        let letters = words.prefix(initialsMost).compactMap(\.first).map { String($0).uppercased() }
        return letters.isEmpty ? String(name.prefix(1)).uppercased() : letters.joined()
    }

    /// What the page says about where the workspace's picture came from, nil where there is nothing worth saying.
    public static func sourceLine(_ view: WorkspaceGraphView) -> String? {
        switch (view.graphSource, view.graphFallback) {
        case (.live, _): return "Read live from your workspace"
        case (_, .unreachable): return "Showing saved facts, the cloud could not be reached."
        case (_, .refused): return "Showing saved facts, your workspace did not answer this Mac."
        // A Mac not joined is told how to join by the empty line, so this says nothing more.
        case (_, .notJoined): return nil
        case (.saved, nil), (nil, _): return "Showing saved facts."
        }
    }

    /// What the workspace side says while the live picture holds nothing, nil once it does or while it was not read live.
    public static func emptyLine(_ view: WorkspaceGraphView) -> String? {
        guard view.graphSource == .live, view.nodes.isEmpty else { return nil }
        return view.withheld > 0 ? WorkspaceMemoryLines.withheldLine(view.withheld) : "Your workspace has taken nothing in yet."
    }

    private static func day(_ stamp: String) -> String {
        String(stamp.prefix(dayLength))
    }
}
