import Foundation

/// How one press ended: done at once, proposed and waiting for a signature on the island, or refused.
public enum SyncOutcome: Equatable, Sendable {
    case done
    case proposed(id: String)
    case failed(String)
}

/// The words of the Personal sync page, mirrored from shared/tauri-core's personal-sync-lines.ts with Touch ID named.
public enum PersonalSyncLines {
    /// Where personal sync stands, in a word beside its tone; the runtime's own sentence goes under it.
    public static func stateWord(_ state: PersonalSyncState?) -> (word: String, tone: ProjectTone) {
        switch state {
        case .off: ("Off", .quiet)
        case .waitingForKey: ("Waiting for the key", .attention)
        case .keyArrived: ("Key arrived", .attention)
        case .ready: ("On", .good)
        case .notOnPlan: ("Not on your plan", .quiet)
        case .noPerson: ("No person signed in", .quiet)
        // A state this app does not know yet is said by the runtime's sentence alone.
        case nil: ("", .quiet)
        }
    }

    /// What personal sync is, said above everything else on the page.
    public static let what =
        "Your own MCP servers, skills, projects, rules and the memory you confirmed, carried between your machines sealed under a key only they hold. It runs when you ask and after you change something here, never on a timer."

    /// Said beside a fingerprint on the machine giving the key.
    public static let compareToOffer =
        "Compare these digits with the ones your other machine shows. Offer the key only if every group matches."

    /// Said beside a fingerprint on the machine taking the key.
    public static let compareToAccept =
        "Compare these digits with the ones your machine holding the key shows. Accept only if every group matches."

    /// Said under the opened copies: keeping one side sends it as the newest.
    public static let conflictChoice = "Keep theirs puts their copy back here and sends it as the newest. Keep mine lets their copy go."

    private static let kindTitles: [String: (one: String, many: String)] = [
        "servers": ("MCP server", "MCP servers"),
        "skills": ("skill", "skills"),
        "projects": ("project", "projects"),
        "rules": ("rule", "rules"),
        "memory": ("memory fact", "memory facts"),
    ]

    /// "3 skills", "1 memory fact": a count of what this Mac carries, never a score.
    public static func kindCount(_ count: PersonalSyncKindCount) -> String {
        let title = kindTitles[count.kind] ?? (count.kind, count.kind)
        return ProjectLines.counted(count.items, title.one, title.many)
    }

    /// The count's tile: the number large, what it counts under it.
    public static func kindTile(_ count: PersonalSyncKindCount) -> ProjectTile {
        let title = kindTitles[count.kind] ?? (count.kind, count.kind)
        return ProjectTile(value: count.items, label: capital(count.items == 1 ? title.one : title.many))
    }

    /// A kind on its own, for a conflict's caption: "Skill", "MCP server".
    public static func kindTitle(_ kind: String) -> String {
        capital(kindTitles[kind]?.one ?? kind)
    }

    /// The six groups of five digits the runtime writes, one each, so they read side by side.
    public static func fingerprintGroups(_ fingerprint: String) -> [String] {
        let groups = fingerprint.split(whereSeparator: \.isWhitespace).map(String.init)
        guard groups.count == 1, let digits = groups.first else { return groups }
        return stride(from: 0, to: digits.count, by: groupLength).map { start in
            let from = digits.index(digits.startIndex, offsetBy: start)
            return String(digits[from..<(digits.index(from, offsetBy: groupLength, limitedBy: digits.endIndex) ?? digits.endIndex)])
        }
    }

    /// "Last synced 5 min ago", or that it never has here.
    public static func lastSyncedLine(_ when: String?) -> String {
        guard let when else { return "Not synced on this machine yet." }
        return "Last synced \(when)."
    }

    /// "2 conflicts" waiting for a choice, or none.
    public static func conflictsLine(_ count: Int) -> String {
        count == 0 ? "No conflicts." : "\(ProjectLines.counted(count, "conflict", "conflicts")) to choose between."
    }

    /// Who wrote the copy that lost and when it was kept, under its name.
    public static func conflictCaption(_ conflict: PersonalSyncConflict, kept: String?) -> String {
        "\(kindTitle(conflict.kind)) written on \(conflict.writtenBy)\(kept.map { ", kept \($0)" } ?? "")"
    }

    /// Said under Opened elsewhere: what the person opened on another machine and not here.
    public static func openedElsewhereLine(_ count: Int) -> String {
        "\(ProjectLines.counted(count, "repository", "repositories")) opened on your other machines and not on this one."
    }

    /// Said once an offer or an accept was proposed: the key moves only once the person signs it.
    public static func keyWaitsLine(offering: Bool) -> String {
        "Nothing moves yet. \(offering ? "Giving the key" : "Taking the key") waits for your signature with Touch ID on the island."
    }

    /// Five digits a group, as the runtime writes a fingerprint.
    private static let groupLength = 5

    private static func capital(_ line: String) -> String {
        line.prefix(1).uppercased() + line.dropFirst()
    }
}
