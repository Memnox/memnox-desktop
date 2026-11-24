import Foundation

/// The words Profiles says, the same as Windows and Linux say them in profile-lines.ts.
public enum ProfileLines {
    /// "2 skills · 1 server · Careful, 6 rules", counted, never a score.
    public static func contents(_ profile: ProfileView) -> String {
        var parts = [ProjectLines.counted(profile.skills.count, "skill", "skills"),
                     ProjectLines.counted(profile.mcpServers.count, "server", "servers")]
        if let pack = profile.rulePack {
            parts.append("\(pack.name), \(ProjectLines.counted(pack.rules, "rule", "rules"))")
        } else {
            parts.append("No starter rules")
        }
        return parts.joined(separator: " · ")
    }

    /// What applying a profile raised, in a line: the proposals waiting on the island, what was already given, what was skipped.
    public static func applied(_ applied: ProfileApplied, keyTitle: String) -> String {
        let count = applied.proposed.count
        let waits = count == 0 ? "" : count == 1 ? "1 change waits for your OK with \(keyTitle) on the island."
            : "\(count) changes wait for your OK with \(keyTitle) on the island."
        let already = applied.already.isEmpty ? "" : applied.already.count == 1 ? "1 was already given." : "\(applied.already.count) were already given."
        let skipped = applied.skipped.isEmpty ? "" : "Skipped: \(applied.skipped.joined(separator: " "))"
        let said = [waits, already, skipped].filter { !$0.isEmpty }.joined(separator: " ")
        return said.isEmpty ? "The profile holds nothing to give." : said
    }

    /// What a save came to: nothing is given by keeping a profile, and an edit gives nothing new until it is applied again.
    public static func saved(_ name: String, editing: Bool) -> String {
        editing ? "\(name) is saved. What it already gave stays, and the change gives nothing until you apply it again."
            : "\(name) is kept. It gives nothing until you apply it."
    }
}
