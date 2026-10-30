import Foundation

/// The kind filter on Discover: everything, or one of the two kinds the index lists.
public enum IndexKindFilter: String, CaseIterable, Sendable {
    case all
    case skill
    case rulePack = "rule_pack"

    public var title: String {
        switch self {
        case .all: "Everything"
        case .skill: "Skills"
        case .rulePack: "Rule packs"
        }
    }
}

/// The words Discover and the Policies packs say, the same as Windows and Linux say them in index-lines.ts.
public enum IndexLines {
    private static let minute: TimeInterval = 60
    private static let hour: TimeInterval = 3_600
    private static let day: TimeInterval = 86_400

    /// What a listing is, in a word a person reads.
    public static func kindWord(_ kind: String) -> String {
        kind == IndexKind.rulePack.rawValue ? "Rule pack" : "Skill"
    }

    /// "By Acme", whether an organization or a member published it.
    public static func publisher(_ publisher: IndexPublisher) -> String {
        "By \(publisher.name)"
    }

    /// The agents a listing supports, by name, or that it works with every agent.
    public static func supportedAgents(_ agents: [String]) -> String {
        if agents.isEmpty { return "Works with every agent" }
        return "For \(SkillsLines.listed(agents.map(McpHubLines.agentLabel)))"
    }

    /// "v1.2.0", or that every version was marked unsafe and nothing can be installed.
    public static func latest(_ entry: IndexEntryView) -> String {
        guard !entry.unsafe, let latest = entry.latest else { return "No safe version to install" }
        return "v\(latest.version)"
    }

    /// A count of versions marked unsafe, or nil when there are none. Counts, never a score.
    public static func yanked(_ yanked: [String]) -> String? {
        if yanked.isEmpty { return nil }
        return yanked.count == 1 ? "1 version marked unsafe" : "\(yanked.count) versions marked unsafe"
    }

    /// Only a version that is not marked unsafe is offered, and only when the listing has one.
    public static func canInstall(_ entry: IndexEntryView) -> Bool {
        !entry.unsafe && entry.latest != nil
    }

    /// What a skill already in the hub is at, so Install reads as an update rather than a first install.
    public static func installed(_ entry: IndexEntryView) -> String? {
        guard let installed = entry.installed, entry.indexKind == .skill else { return nil }
        return "v\(installed) in My Skills"
    }

    /// Where an install from the index goes next, said under every Install so nobody expects it to be live.
    public static func installWaits(kind: String, keyTitle: String) -> String {
        if kind == IndexKind.rulePack.rawValue {
            return "Installing a rule pack proposes each of its rules, and each waits for your signature with \(keyTitle) on the island."
        }
        return "Installing a skill puts it in My Skills, where it waits for you to accept it before any agent is given it."
    }

    /// The categories the listings carry, each once, in order.
    public static func categories(_ entries: [IndexEntryView]) -> [String] {
        Set(entries.compactMap { $0.category }.filter { !$0.isEmpty }).sorted()
    }

    /// The listings in one category, or all of them; the runtime filters words and kind, the category is the window's.
    public static func inCategory(_ entries: [IndexEntryView], _ category: String?) -> [IndexEntryView] {
        guard let category else { return entries }
        return entries.filter { $0.category == category }
    }

    /// Where the index was read from and how long ago, or why it is not fresh, in a line.
    public static func state(_ view: CommunityIndexView, now: Date) -> String {
        if let said = view.said, !said.isEmpty { return said }
        let partial = view.complete ? "" : " It held more than it carries, so some listings are not shown."
        guard let fetchedAt = view.fetchedAt else { return "Not read from \(view.source) yet.\(partial)" }
        return "Read from \(view.source) \(since(fetchedAt, now: now)).\(partial)"
    }

    /// What an install did, in a line: a skill held for acceptance, or how many rules wait on the island.
    public static func installedNote(_ installed: IndexInstalled, keyTitle: String) -> String {
        if installed.kind == IndexKind.rulePack.rawValue {
            let count = installed.proposed.count
            if count == 0 { return "\(installed.name) v\(installed.version) held no rule to propose." }
            let rules = count == 1 ? "1 rule waits" : "\(count) rules wait"
            return "\(rules) from \(installed.name) v\(installed.version) for your signature with \(keyTitle) on the island."
        }
        if installed.held { return "\(installed.name) v\(installed.version) is in My Skills, waiting for you to accept it." }
        return "\(installed.name) v\(installed.version) is in My Skills."
    }

    private static func since(_ at: String, now: Date) -> String {
        guard let then = parsed(at) else { return "at some point" }
        let gone = max(0, now.timeIntervalSince(then))
        if gone < minute { return "just now" }
        if gone < hour { return ago(Int(gone / minute), "minute") }
        if gone < day { return ago(Int(gone / hour), "hour") }
        return ago(Int(gone / day), "day")
    }

    private static func ago(_ count: Int, _ unit: String) -> String {
        count == 1 ? "1 \(unit) ago" : "\(count) \(unit)s ago"
    }

    private static func parsed(_ at: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: at) ?? ISO8601DateFormatter().date(from: at)
    }
}
