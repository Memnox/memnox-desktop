import Foundation

/// A change to the team's rules that waits on a second person, as memnox-cloud's `PolicyProposal` sends it. Only the
/// fields this app shows are read, since approving one is signed in Memnox Cloud and never here.
public struct CloudRuleChange: Decodable, Equatable, Sendable {
    public let id: String
    public let proposedBy: String
    public let proposedAt: String
    /// What it changes; absent on an older record, which is a rule set.
    public let kind: String?

    public init(id: String, proposedBy: String, proposedAt: String, kind: String? = nil) {
        self.id = id
        self.proposedBy = proposedBy
        self.proposedAt = proposedAt
        self.kind = kind
    }
}

/// One team rule change as Needs you lists it.
public struct TeamRuleChangeLine: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let caption: String
}

/// The words for team rule changes on Needs you, which point to Memnox Cloud because a second admin signs them there.
public enum TeamRuleChangeLines {
    public static let title = "Team rule changes"
    public static let detail = "Each one is approved by a second person in Memnox Cloud, where your team signs it."
    public static let open = "Open in Memnox Cloud"
    /// The console's Needs you, opened on its Rule changes list.
    public static let consoleAddress = URL(string: "https://app.memnox.com/inbox?queue=rule-changes")! // A literal that always parses.

    /// What a change is about, by the cloud's `ProposalKind`; an unknown kind is still a change to what the team allows.
    public static func title(kind: String?) -> String {
        switch kind {
        case "data_patterns": return "A change to what counts as sensitive"
        case "mcp_servers": return "A change to the team's tool servers"
        case "org_skills": return "A change to the team's skills"
        case "shared_projects": return "A change to the team's projects"
        default: return "A change to the team's rules"
        }
    }

    /// Every waiting change, newest first as the cloud sends it.
    public static func lines(_ changes: [CloudRuleChange], now: Date) -> [TeamRuleChangeLine] {
        changes.map { change in
            let asked = change.proposedBy.isEmpty ? "Asked by a teammate" : "Asked by \(change.proposedBy)"
            let caption = [asked, SessionText.ago(change.proposedAt, now: now)].compactMap { $0 }.joined(separator: ", ")
            return TeamRuleChangeLine(id: change.id, title: title(kind: change.kind), caption: caption)
        }
    }
}
