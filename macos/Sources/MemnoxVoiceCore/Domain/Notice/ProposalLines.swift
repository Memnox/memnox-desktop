import Foundation

/// A proposal worded by the kind of change it carries, where the daemon named one, and in its own words where it did not.
public enum ProposalLines {
    /// Each kind by the runtime's PROPOSAL_KIND value, said as what saying yes would do.
    public static let phrases: [String: String] = [
        "rules": "a new rule",
        "answer": "an answer to a held call",
        "resume": "letting a paused session carry on",
        "rewind": "putting a repository back to a milestone",
        "command": "running a Memnox command",
        "mac": "something only this Mac can do",
        "team": "an answer to your team",
        "work": "acting in one of your own accounts",
        "account": "claiming an account as your own",
        "mcp-hub": "a change to your MCP servers",
        "rule-remove": "removing one of your rules",
        "agent-resume": "letting a paused agent carry on",
        "skills-hub": "a change to your skills",
        "project": "handing a project its setup",
        "backup-restore": "putting a backup back",
        "lan": "opening this Mac to your local network",
        "personal-sync-key": "sharing your personal sync key",
        "index-source": "reading listings from another source",
    ]

    /// What Touch ID's sheet says it is for: the kind first where one is known, then the proposal's own words.
    public static func prompt(kind: String?, summary: String) -> String {
        guard let phrase = phrase(kind) else { return summary }
        return "\(phrase.prefix(1).uppercased())\(phrase.dropFirst()): \(summary)"
    }

    /// The island's caption while Touch ID is up, short enough for the notch.
    public static func caption(kind: String?, summary: String) -> String {
        guard let phrase = phrase(kind) else { return "Touch ID to \(summary)" }
        return "Touch ID for \(phrase)"
    }

    /// Said once a proposal nobody asked for is declined, naming what it would have done where the kind is known.
    public static func unasked(kind: String?) -> String {
        guard let phrase = phrase(kind) else { return unaskedAllow }
        return "Something proposed \(phrase), which you did not ask for. I have declined it."
    }

    /// The words from before a proposal named its kind, kept for an older daemon and a kind this app does not know.
    static let unaskedAllow = "Something proposed an allow you did not ask for. I have declined it."

    private static func phrase(_ kind: String?) -> String? {
        kind.flatMap { phrases[$0] }
    }
}
