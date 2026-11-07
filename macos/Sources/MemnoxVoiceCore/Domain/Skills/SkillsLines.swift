import Foundation

/// What the New skill form holds, every list as typed.
public struct SkillForm: Equatable, Sendable {
    public var name: String
    public var version: String
    public var description: String
    public var category: String
    public var instructions: String
    public var tools: String
    public var commands: String

    public init(name: String = "", version: String = "", description: String = "", category: String = "",
                instructions: String = "", tools: String = "", commands: String = "") {
        self.name = name
        self.version = version
        self.description = description
        self.category = category
        self.instructions = instructions
        self.tools = tools
        self.commands = commands
    }
}

/// The agents to give a skill to and to take it from, so Continue sends only what changed.
public struct AssignmentChanges: Equatable, Sendable {
    public let give: [String]
    public let take: [String]
}

/// Every loss for one agent chosen, said before Continue.
public struct ConversionLoss: Equatable, Sendable {
    public let label: String
    public let loses: [String]
}

/// One kind of reach a skill asks for, and its items.
public struct PermissionLine: Equatable, Sendable {
    public let title: String
    public let items: [String]
}

/// The Skills Hub's words, the same as Windows and Linux say them in shared/tauri-core's skills-lines.ts. Counts,
/// never a score.
public enum SkillsLines {
    private static let secondsPerDay: Double = 86_400
    /// The version a new skill gets when none is typed.
    public static let firstVersion = "1.0.0"
    /// The longest name every agent folder takes.
    static let nameLimit = 64

    /// "3 agents assigned", or that none is yet.
    public static func assigned(_ count: Int) -> String {
        if count == 0 { return "No agents assigned" }
        return count == 1 ? "1 agent assigned" : "\(count) agents assigned"
    }

    /// "Updated 4 days ago", counted in whole days so the card does not change by the minute.
    public static func updated(_ updatedAt: String, now: Date) -> String {
        guard let at = readInstant(updatedAt) else { return "Updated at some point" }
        let days = max(0, Int((now.timeIntervalSince(at) / secondsPerDay).rounded(.down)))
        if days == 0 { return "Updated today" }
        if days == 1 { return "Updated yesterday" }
        return "Updated \(days) days ago"
    }

    /// "Testing · v1.2.0", or the version alone where no category was given.
    public static func categoryVersion(category: String?, version: String) -> String {
        let versioned = "v\(version)"
        guard let category, !category.isEmpty else { return versioned }
        return "\(category) · \(versioned)"
    }

    public static func categoryVersion(_ skill: SkillView) -> String {
        categoryVersion(category: skill.category, version: skill.version)
    }

    /// Why a skill is held, in a sentence, and what accepting it does.
    public static func held(_ hold: SkillHold) -> String {
        let reach = hold.gained.isEmpty ? "" : " It now reaches \(listed(hold.gained))."
        let sign = hold.signed ? " Accepting it waits for your signature on the island." : " Accepting it happens at once."
        switch hold.skillStanding {
        case .new: return "Nobody has accepted this folder yet, so no agent is given it.\(reach)\(sign)"
        case .widened: return "Its folder reaches further than the version you accepted, so nothing new of it is handed out.\(reach)\(sign)"
        case .changed, nil: return "Its folder changed since you accepted it, so nothing new of it is handed out.\(reach)\(sign)"
        }
    }

    /// What one agent keeps of a skill once written in its format.
    public static func compatibility(supported: Bool, loses: [String]) -> String {
        if !supported { return "Cannot take skills" }
        if loses.isEmpty { return "Keeps everything" }
        return loses.count == 1 ? "Loses 1 thing in conversion" : "Loses \(loses.count) things in conversion"
    }

    public static func compatibility(_ each: SkillCompatibility) -> String {
        compatibility(supported: each.supported, loses: each.loses)
    }

    /// "Wrote 3, removed 1, skipped 2." or that every agent already had what the hub gives it.
    public static func synced(_ synced: SkillsSyncSummary) -> String {
        let parts = [
            synced.written > 0 ? "wrote \(synced.written)" : nil,
            synced.removed > 0 ? "removed \(synced.removed)" : nil,
            synced.skipped.isEmpty ? nil : "skipped \(synced.skipped.count)",
        ].compactMap { $0 }
        if parts.isEmpty { return "Every agent already has the skills the hub gives it." }
        let line = parts.joined(separator: ", ")
        return "\(line.prefix(1).uppercased())\(line.dropFirst())."
    }

    public static func assignmentChanges(current: [String], chosen: Set<String>) -> AssignmentChanges {
        let had = Set(current)
        return AssignmentChanges(give: chosen.filter { !had.contains($0) }.sorted(), take: current.filter { !chosen.contains($0) })
    }

    /// What a Continue that gave and took said in one line, the gives waiting on the island.
    public static func assignedNote(proposed: Int, done: Int, failed: [String], keyTitle: String) -> String {
        if let first = failed.first { return first }
        let waits = proposed == 0 ? "" : proposed == 1 ? "1 agent waits for your signature with \(keyTitle) on the island."
            : "\(proposed) agents wait for your signature with \(keyTitle) on the island."
        let now = done == 0 ? "" : done == 1 ? "1 change made at once." : "\(done) changes made at once."
        let said = [waits, now].filter { !$0.isEmpty }.joined(separator: " ")
        return said.isEmpty ? "Nothing changed." : said
    }

    /// Every loss across the agents chosen, said before Continue, so nobody learns of it afterwards.
    public static func conversionLosses(_ compatibility: [SkillCompatibility], chosen: Set<String>) -> [ConversionLoss] {
        compatibility.filter { chosen.contains($0.agent) && !$0.loses.isEmpty }.map { ConversionLoss(label: $0.label, loses: $0.loses) }
    }

    /// What a skill asks to reach, a line per kind that has anything.
    public static func permissions(_ skill: SkillView) -> [PermissionLine] {
        [
            PermissionLine(title: "Agent tools", items: skill.tools),
            PermissionLine(title: "MCP servers", items: skill.mcpServers),
            PermissionLine(title: "Commands", items: skill.permissions.commands),
            PermissionLine(title: "Files outside its folder", items: skill.permissions.filesystem),
            PermissionLine(title: "Hosts", items: skill.permissions.network),
        ].filter { !$0.items.isEmpty }
    }

    /// A word a person typed made into a name every agent folder takes.
    public static func name(from typed: String) -> String {
        let lowered = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let joined = lowered.replacingOccurrences(of: "[^a-z0-9-]+", with: "-", options: .regularExpression)
        let trimmed = joined.replacingOccurrences(of: "^-+|-+$", with: "", options: .regularExpression)
        return String(trimmed.prefix(nameLimit))
    }

    /// A comma or line separated field as a list, blanks dropped.
    public static func list(from typed: String) -> [String] {
        typed.split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The form as the runtime takes it, or what is missing in the words the form shows.
    public static func draft(from form: SkillForm) -> Result<SkillDraft, SkillFormProblem> {
        let name = name(from: form.name)
        if name.isEmpty { return .failure(SkillFormProblem("Give the skill a name.")) }
        let description = form.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if description.isEmpty { return .failure(SkillFormProblem("Say in a line what the skill is for.")) }
        if form.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .failure(SkillFormProblem("Write the instructions the agent follows."))
        }
        let typedVersion = form.version.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = form.category.trimmingCharacters(in: .whitespacesAndNewlines)
        let tools = list(from: form.tools)
        let commands = list(from: form.commands)
        return .success(SkillDraft(
            name: name,
            version: typedVersion.isEmpty ? firstVersion : typedVersion,
            description: description,
            category: category.isEmpty ? nil : category,
            instructions: form.instructions,
            tools: tools.isEmpty ? nil : tools,
            permissions: commands.isEmpty ? nil : SkillDraftPermissions(commands: commands)
        ))
    }

    /// "Bash and curl", or "a, b and c".
    static func listed(_ items: [String]) -> String {
        guard let last = items.last, items.count > 1 else { return items.joined() }
        return "\(items.dropLast().joined(separator: ", ")) and \(last)"
    }
}

/// What the New skill form is missing, in the words it shows.
public struct SkillFormProblem: Error, Equatable, Sendable {
    public let why: String

    public init(_ why: String) {
        self.why = why
    }
}
