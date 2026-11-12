import Foundation

/// What the New profile sheet holds: the name and line as typed, and what was ticked in the hubs and packs.
public struct ProfileForm: Equatable, Sendable {
    public var name = ""
    public var description = ""
    public var skills: Set<String> = []
    public var servers: Set<String> = []
    /// A pack's id from the packs the runtime offers, or empty for none.
    public var pack = ""
    /// The job: what it is for, its role, its responsibilities one a line, its instructions, and who answers for it.
    public var purpose = ""
    public var role = ""
    public var responsibilities = ""
    public var instructions = ""
    public var responsiblePerson = ""
    /// Carried through an edit unseen, so saving never drops the projects or the template it came from.
    public var projects: [String] = []
    public var templateOf: String?

    public init(name: String = "", description: String = "", skills: Set<String> = [], servers: Set<String> = [], pack: String = "",
                purpose: String = "", role: String = "", responsibilities: String = "", instructions: String = "",
                responsiblePerson: String = "", projects: [String] = [], templateOf: String? = nil) {
        self.name = name
        self.description = description
        self.skills = skills
        self.servers = servers
        self.pack = pack
        self.purpose = purpose
        self.role = role
        self.responsibilities = responsibilities
        self.instructions = instructions
        self.responsiblePerson = responsiblePerson
        self.projects = projects
        self.templateOf = templateOf
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
        let purpose = AgentWorkLines.filled(form.purpose)
        // A job is a profile too, so its purpose alone is enough to keep it.
        if form.skills.isEmpty && form.servers.isEmpty && pack == nil && purpose == nil {
            return .failure(ProfileFormProblem("Choose at least one skill, server or rule pack."))
        }
        let description = form.description.trimmingCharacters(in: .whitespacesAndNewlines)
        return .success(ProfileDraft(
            name: name,
            description: description.isEmpty ? nil : description,
            skills: form.skills.isEmpty ? nil : form.skills.sorted(),
            mcpServers: form.servers.isEmpty ? nil : form.servers.sorted(),
            rulePack: pack.map { ProfileRulePack(name: $0.name, toml: $0.toml) },
            purpose: purpose,
            role: AgentWorkLines.filled(form.role),
            responsibilities: lines(form.responsibilities),
            instructions: AgentWorkLines.filled(form.instructions),
            responsiblePerson: AgentWorkLines.filled(form.responsiblePerson),
            projects: form.projects.isEmpty ? nil : form.projects,
            templateOf: form.templateOf
        ))
    }

    /// The form Edit opens with: the profile as kept, its pack matched by name among the packs offered now.
    public static func form(of profile: ProfileView, packs: [RulePackView]) -> ProfileForm {
        let pack = profile.rulePack.flatMap { kept in packs.first { $0.name == kept.name } }
        return ProfileForm(name: profile.name, description: profile.description ?? "", skills: Set(profile.skills),
                           servers: Set(profile.mcpServers), pack: pack?.id ?? "", purpose: profile.purpose ?? "",
                           role: profile.role ?? "", responsibilities: profile.responsibilities.joined(separator: "\n"),
                           instructions: profile.instructions ?? "", responsiblePerson: profile.responsiblePerson ?? "",
                           projects: profile.projects, templateOf: profile.templateOf)
    }

    /// One responsibility a line, blank lines dropped; nil when none was written.
    static func lines(_ text: String) -> [String]? {
        let kept = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return kept.isEmpty ? nil : kept
    }

    /// The form Give it a job opens with for an agent's default: its name, and nothing else decided for the person.
    public static func job(for profile: ProfileView) -> ProfileForm {
        ProfileForm(name: profile.name, responsiblePerson: profile.responsiblePerson ?? "")
    }

    /// What copying a template came to: a job with no agent behind it yet, and no rule applied.
    public static func copied(_ name: String) -> String {
        let named = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(named.isEmpty ? "The job" : named) is kept with no agent behind it yet. Its suggested rules wait for you to write them."
    }

    /// The names to tick: what the hub holds now, then any the profile keeps that the hub no longer does, so each can be unticked.
    public static func choiceNames(_ hub: [String], kept: Set<String>) -> [String] {
        hub + kept.filter { !hub.contains($0) }.sorted()
    }

    /// What saving an edit does to the pack the profile keeps. The runtime hands back only the pack's name, so a pack
    /// is sent again from the packs offered now, and one no longer offered cannot be kept.
    public static func packChange(kept: ProfilePackSummary?, form: ProfileForm, packs: [RulePackView]) -> String? {
        guard let kept else { return nil }
        let offered = packs.contains { $0.name == kept.name }
        guard let chosen = packs.first(where: { $0.id == form.pack }) else {
            return offered ? "Saving takes \(kept.name) out of the profile."
                : "\(kept.name) is no longer offered here, so saving takes it out of the profile. Choose a pack to keep one."
        }
        if chosen.name != kept.name { return "Saving replaces \(kept.name) with \(chosen.name)." }
        if chosen.ruleCount != kept.rules {
            return "Saving takes \(kept.name) as it is offered now, \(ProjectLines.counted(chosen.ruleCount, "rule", "rules")) where the profile keeps \(kept.rules)."
        }
        return nil
    }

    /// What a save came to: nothing is given by keeping a profile, and an edit gives nothing new until it is applied again.
    public static func saved(_ name: String, editing: Bool) -> String {
        editing ? "\(name) is saved. What it already gave stays, and the change gives nothing until you apply it again."
            : "\(name) is kept. It gives nothing until you apply it."
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
