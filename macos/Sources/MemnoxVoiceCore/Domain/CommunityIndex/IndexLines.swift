import Foundation

/// The words the rule packs under Rules say, the same as Windows and Linux say them in index-lines.ts.
public enum IndexLines {
    /// "By Acme", whether an organization or a member published it.
    public static func publisher(_ publisher: IndexPublisher) -> String {
        "By \(publisher.name)"
    }

    /// "v1.2.0", or that every version was marked unsafe and nothing can be installed.
    public static func latest(_ entry: IndexEntryView) -> String {
        guard !entry.unsafe, let latest = entry.latest else { return "No safe version to install" }
        return "v\(latest.version)"
    }

    /// Only a version that is not marked unsafe is offered, and only when the listing has one.
    public static func canInstall(_ entry: IndexEntryView) -> Bool {
        !entry.unsafe && entry.latest != nil
    }

    /// Where an install from the index goes next, said under every Install so nobody expects it to be live.
    public static func installWaits(kind: String, keyTitle: String) -> String {
        if kind == IndexKind.rulePack.rawValue {
            return "Installing a rule pack proposes each of its rules, and each waits for your signature with \(keyTitle) on the island."
        }
        return "Installing a skill puts it in My Skills, where it waits for you to accept it before any agent is given it."
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
}
