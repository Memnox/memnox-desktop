import Foundation

/// How one press on a project ended: done at once, done with the rest waiting for a signature on the island, nothing
/// to do because the runtime found every agent already had it, or refused.
public enum ProjectOutcome: Equatable, Sendable {
    case done(String)
    case proposed(id: String, note: String)
    case upToDate(String)
    case failed(String)
}

/// How a press's result line is marked beside its words.
public enum ProjectResultMark: String, Sendable {
    /// Something was written or put behind the proxy.
    case changed
    /// Applied, with what widens an agent waiting for Touch ID on the island.
    case waiting
    /// The runtime had nothing to change.
    case upToDate
    case failed
}

/// Where a project stands, said in a word beside its tone.
public enum ProjectTone: Equatable, Sendable {
    case good
    case attention
    case bad
    case quiet
}

/// One of the counts the Overview leads with.
public struct ProjectTile: Equatable, Sendable {
    public let value: Int
    public let label: String

    public init(value: Int, label: String) {
        self.value = value
        self.label = label
    }
}

/// A folder the sessions ran in, offered as a quick pick to open.
public struct FolderPick: Equatable, Sendable {
    public let path: String
    public let name: String

    public init(path: String, name: String) {
        self.path = path
        self.name = name
    }
}

/// The words of the projects under Workspaces, mirrored from shared/tauri-core's project-lines.ts so the Mac, Windows
/// and Linux say a project the same way.
public enum ProjectLines {
    /// "1 agent", "3 agents": a count, never a score.
    public static func counted(_ count: Int, _ one: String, _ many: String) -> String {
        count == 1 ? "1 \(one)" : "\(count) \(many)"
    }

    /// The four counts the Overview leads with, rules counted only while they are in force.
    public static func tiles(_ project: ProjectView) -> [ProjectTile] {
        let rules = project.rules.inForce ? project.rules.count : 0
        return [
            ProjectTile(value: project.agents.count, label: project.agents.count == 1 ? "Agent" : "Agents"),
            ProjectTile(value: project.skills.count, label: project.skills.count == 1 ? "Skill" : "Skills"),
            ProjectTile(value: project.servers.count, label: project.servers.count == 1 ? "MCP server" : "MCP servers"),
            ProjectTile(value: rules, label: rules == 1 ? "Active rule" : "Active rules"),
        ]
    }

    /// Where a project stands: a manifest that will not read comes first.
    public static func standing(_ project: ProjectView) -> (word: String, tone: ProjectTone) {
        if let problems = project.problems, !problems.isEmpty { return ("Manifest will not read", .bad) }
        if !project.declared { return ("Found, not saved", .quiet) }
        if !project.opened { return ("Not opened here", .attention) }
        return ("Opened", .good)
    }

    /// "Claude Code and Codex read it", or that no agent here reads it.
    public static func readersLine(_ agents: [String]) -> String {
        if agents.isEmpty { return "No agent here reads it" }
        return "\(listed(agents.map(McpHubLines.agentLabel))) \(agents.count == 1 ? "reads" : "read") it"
    }

    /// What one instruction file is: the source the project reads, a file Memnox wrote, both, or missing.
    public static func instructionWord(_ instruction: ProjectInstructionView) -> String {
        if !instruction.present { return "Missing" }
        if instruction.source, instruction.written { return "Source, written by Memnox" }
        if instruction.source { return "Source" }
        return instruction.written ? "Written by Memnox" : "Not written yet"
    }

    /// "Given to 2 of 3 agents", or that the hub here lacks it, so nobody is given it.
    public static func grantLine(_ grant: ProjectGrantView, of agents: Int) -> String {
        guard grant.inHub else { return "Not in the hub on this computer, so no agent is given it" }
        return "Given to \(grant.agents.count) of \(counted(agents, "agent", "agents"))"
    }

    /// The rules line under Active rules, saying why none are in force when none are.
    public static func rulesLine(_ rules: ProjectRulesView) -> String {
        if let problem = rules.problem { return "\(rules.file ?? "Its rule file") will not load: \(problem)" }
        guard let file = rules.file else { return "This project names no rule file, so the rules of this computer hold." }
        if !rules.inForce { return "\(counted(rules.count, "rule", "rules")) in \(file), not in force until applying is signed." }
        return "\(counted(rules.count, "rule", "rules")) from \(file), in force."
    }

    /// "2 open questions" or that none waits.
    public static func questionsLine(_ count: Int) -> String {
        count == 0 ? "No open questions" : counted(count, "open question", "open questions")
    }

    /// What applying did at once, in a line; what it proposed waits on the island and is said apart.
    public static func appliedLine(_ applied: ProjectApplySummary) -> String {
        let parts = [
            applied.written.isEmpty ? nil : "wrote \(counted(applied.written.count, "instruction file", "instruction files"))",
            applied.removed.isEmpty ? nil : "took out \(applied.removed.count)",
            applied.kept.isEmpty ? nil : "left \(applied.kept.count) of yours alone",
            applied.governed.isEmpty ? nil : "put \(counted(applied.governed.count, "server", "servers")) behind the proxy",
        ].compactMap { $0 }
        let done = parts.isEmpty
            ? "Nothing needed applying: every agent here already has this project\u{2019}s instructions."
            : "\(capital(parts.joined(separator: ", ")))."
        if applied.missing.isEmpty { return done }
        return "\(done) The hub here lacks \(listed(applied.missing)), so no agent is given \(applied.missing.count == 1 ? "it" : "them")."
    }

    /// True when applying changed no file and put no server behind the proxy, so the project was already applied;
    /// a file of the person's left alone or a name the hub lacks is said, but applying again would not change it.
    public static func upToDate(_ applied: ProjectApplySummary) -> Bool {
        applied.written.isEmpty && applied.removed.isEmpty && applied.governed.isEmpty
    }

    /// What a press said, the part waiting on the island named with the key that signs it.
    public static func note(_ outcome: ProjectOutcome) -> String {
        switch outcome {
        case .failed(let why): return why
        case .proposed(_, let note): return "\(note) Its servers, skills and rules wait for you on the island: confirm them with Touch ID."
        case .done(let note), .upToDate(let note): return note
        }
    }

    /// The mark a press's result line wears.
    public static func mark(_ outcome: ProjectOutcome) -> ProjectResultMark {
        switch outcome {
        case .done: .changed
        case .proposed: .waiting
        case .upToDate: .upToDate
        case .failed: .failed
        }
    }

    /// The line under Apply or Save as project, saying what the press does before it is pressed.
    public static func pressLine(declared: Bool) -> String {
        declared
            ? "Apply hands its instructions to its agents at once. Servers, skills and rules that widen an agent wait for your signature."
            : "Found from the sessions here. Save as project writes .memnox/project.toml with what it shows now, applying nothing until you ask."
    }

    /// Said beside Open a folder, before anything is opened.
    public static let openLine = "Opening hands its instructions to its agents at once. Whatever widens an agent waits for your signature on the island."

    /// "4 sessions, 3 ended. Applied 2 hours ago."
    public static func sessionsLine(_ project: ProjectView, now: Date) -> String {
        let applied = project.appliedAt.map { " Applied \(SessionText.ago($0, now: now) ?? "a while ago")." } ?? " Never applied."
        return "\(counted(project.sessions.total, "session", "sessions")), \(project.sessions.ended) ended.\(applied)"
    }

    /// "3 rules of this computer hold here too."
    public static func everywhereLine(_ count: Int) -> String {
        count == 1 ? "1 rule of this computer holds here too." : "\(count) rules of this computer hold here too."
    }

    /// The rules that hold in this project: those reaching into its folder, and those its own rule file brings. A rule
    /// naming no folder holds everywhere and is counted apart, so the list says what this project adds.
    public static func rules(_ rules: [PolicyRuleView], in project: ProjectView) -> (here: [PolicyRuleView], everywhere: Int) {
        let here = rules.filter { fromProjectFile($0, project) || reachesInto($0.match.workingDirectories, project.path) }
        let names = Set(here.map(\.name))
        let everywhere = rules.filter { !names.contains($0.name) && ($0.match.workingDirectories ?? []).isEmpty }.count
        return (here, everywhere)
    }

    /// The project as found, made into the manifest Save as project writes: everything it shows now, named.
    public static func draft(of project: ProjectView) -> ProjectDraft {
        let instructions = project.instructions.filter(\.source).map(\.path)
        return ProjectDraft(
            name: project.name,
            instructions: instructions.isEmpty ? nil : instructions,
            servers: project.servers.isEmpty ? nil : project.servers.map(\.name),
            skills: project.skills.isEmpty ? nil : project.skills.map(\.name),
            agents: project.agents.isEmpty ? nil : project.agents,
            policy: project.rules.file,
            memory: project.memoryScope.isEmpty ? nil : project.memoryScope)
    }

    /// The badge on a project the organization shares, which is read only here.
    public static let fromOrganization = "From your organization"

    /// "Release rules, 4 rules", or that the organization gives this project no rule pack.
    public static func organizationRulesLine(_ organization: ProjectOrganizationView) -> String {
        guard let pack = organization.rulePack else { return "No rule pack from the organization." }
        return "\(pack), \(counted(organization.rules, "rule", "rules"))"
    }

    /// Where what its agents learn is kept, as the organization set it.
    public static func organizationMemoryLine(_ memory: String) -> String {
        switch memory {
        case "none": "Its agents keep no memory from this project."
        case "project": "What its agents learn is kept under the organization’s project rather than this folder."
        default: "Memory is kept as \(memory)."
        }
    }

    /// Folders the sessions ran in that are not projects yet, offered as quick picks to open.
    public static func foldersToOpen(_ seen: [FolderPick], projects: [ProjectView]) -> [FolderPick] {
        let known = Set(projects.map { normalised($0.path) })
        return seen.filter { !known.contains(normalised($0.path)) }
    }

    private static func fromProjectFile(_ rule: PolicyRuleView, _ project: ProjectView) -> Bool {
        guard let ruleFile = rule.file, let projectFile = project.rules.file else { return false }
        let file = normalised(ruleFile)
        return file == normalised("\(project.path)/\(projectFile)")
            || (file.hasPrefix(normalised(project.path)) && file.hasSuffix(normalised(projectFile)))
    }

    private static func reachesInto(_ folders: [String]?, _ path: String) -> Bool {
        guard let folders else { return false }
        let root = normalised(path)
        return folders.contains { folder in
            let each = normalised(stripStars(folder))
            return each == root || each.hasPrefix("\(root)/")
        }
    }

    /// "/code/app/**" reads as "/code/app", since a folder and everything under it is the same reach here.
    private static func stripStars(_ folder: String) -> String {
        var trimmed = Substring(folder)
        while trimmed.hasSuffix("*") { trimmed = trimmed.dropLast() }
        return trimmed.count < folder.count && trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : folder
    }

    private static func normalised(_ path: String) -> String {
        var each = path.replacingOccurrences(of: "\\", with: "/")
        while each.hasSuffix("/") { each.removeLast() }
        return each
    }

    private static func capital(_ line: String) -> String {
        line.prefix(1).uppercased() + line.dropFirst()
    }

    private static func listed(_ items: [String]) -> String {
        guard items.count > 1, let last = items.last else { return items.joined() }
        return "\(items.dropLast().joined(separator: ", ")) and \(last)"
    }
}

/// What a project's card says, as the console's Projects grid draws one: where it lives, one line, and chips.
extension ProjectLines {
    /// Said where a project has no repository to name.
    public static let noRepository = "No repository yet"

    /// The repository the organization shares it under, else the folder this Mac holds it in.
    public static func repositoryLine(_ project: ProjectView) -> String {
        if let repository = project.sharedBy?.repository, !repository.isEmpty { return repository }
        return project.path.isEmpty ? noRepository : project.path
    }

    /// The card's one line: what the organization says it is for, else the mission open in it, else its sessions.
    public static func cardLine(_ project: ProjectView) -> String {
        if let description = project.sharedBy?.description, !description.isEmpty { return description }
        if let mission = project.openMissions.first { return mission.statement }
        let sessions = project.sessions.total
        return sessions == 0 ? "No agent has worked here yet." : "\(counted(sessions, "session", "sessions")) so far."
    }

    /// The chips along the card's foot: its servers, its skills, and whether its agents keep memory from it.
    public static func chips(_ project: ProjectView) -> [String] {
        let servers = project.sharedBy?.servers.count ?? project.servers.count
        let skills = project.sharedBy?.skills.count ?? project.skills.count
        let memory = project.sharedBy?.memory ?? project.memoryScope
        return [counted(servers, "server", "servers"), counted(skills, "skill", "skills"),
                memory.isEmpty || memory == "none" ? "No memory" : "Memory"]
    }
}
