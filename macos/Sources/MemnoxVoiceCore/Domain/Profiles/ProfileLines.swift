import Foundation

/// What the New profile sheet holds: the name and line as typed, and what was ticked in the hubs and packs.
public struct ProfileForm: Equatable, Sendable {
    public var name = ""
    public var description = ""
    public var skills: Set<String> = []
    public var servers: Set<String> = []
    /// A pack's id from the packs the runtime offers, or empty for none.
    public var pack = ""

    public init(name: String = "", description: String = "", skills: Set<String> = [], servers: Set<String> = [], pack: String = "") {
        self.name = name
        self.description = description
        self.skills = skills
        self.servers = servers
        self.pack = pack
    }
}

/// The words Profiles says, the same as Windows and Linux say them in profile-lines.ts.
public enum ProfileLines {
    /// "2 skills · 1 server · Careful, 6 rules", counted, never a score.
    public static func contents(_ profile: ProfileView) -> String {
        var parts = [ProjectLines.counted(profile.skills.count, "skill", "skills"),
                     ProjectLines.counted(profile.mcpServers.count, "server", "servers")]
        if let pack = profile.rulePack {
            parts.append("\(pack.name), \(ProjectLines.counted(pack.rules, "rule", "rules"))")
        } else {
            parts.append("No rule pack")
        }
        return parts.joined(separator: " · ")
    }

    /// What applying a profile raised, in a line: the proposals waiting on the island, what was already given, what was skipped.
    public static func applied(_ applied: ProfileApplied, keyTitle: String) -> String {
        let count = applied.proposed.count
        let waits = count == 0 ? "" : count == 1 ? "1 proposal waits for your signature with \(keyTitle) on the island."
            : "\(count) proposals wait for your signature with \(keyTitle) on the island."
        let already = applied.already.isEmpty ? "" : applied.already.count == 1 ? "1 was already given." : "\(applied.already.count) were already given."
        let skipped = applied.skipped.isEmpty ? "" : "Skipped: \(applied.skipped.joined(separator: " "))"
        let said = [waits, already, skipped].filter { !$0.isEmpty }.joined(separator: " ")
        return said.isEmpty ? "The profile holds nothing to give." : said
    }

    /// The form as the runtime takes it, or what is missing in the words the sheet shows.
    public static func draft(_ form: ProfileForm, packs: [RulePackView]) -> Result<ProfileDraft, ProfileFormProblem> {
        let name = form.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return .failure(ProfileFormProblem("Give the profile a name.")) }
        let pack = packs.first { $0.id == form.pack }
        if !form.pack.isEmpty && pack == nil { return .failure(ProfileFormProblem("That rule pack is no longer offered. Choose another.")) }
        if form.skills.isEmpty && form.servers.isEmpty && pack == nil {
            return .failure(ProfileFormProblem("Choose at least one skill, server or rule pack."))
        }
        let description = form.description.trimmingCharacters(in: .whitespacesAndNewlines)
        return .success(ProfileDraft(
            name: name,
            description: description.isEmpty ? nil : description,
            skills: form.skills.isEmpty ? nil : form.skills.sorted(),
            mcpServers: form.servers.isEmpty ? nil : form.servers.sorted(),
            rulePack: pack.map { ProfileRulePack(name: $0.name, toml: $0.toml) }
        ))
    }

    /// Where a profile is applied, said before Apply: a repository, or the agent's home folder.
    public static func applyWhere(_ project: String) -> String {
        let trimmed = project.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Skills go into the agent’s home folder." : "Skills go into \(trimmed)."
    }
}

/// What the New profile form is missing, in the words it shows.
public struct ProfileFormProblem: Error, Equatable, Sendable {
    public let why: String

    public init(_ why: String) {
        self.why = why
    }
}
