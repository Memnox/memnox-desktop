import Foundation

/// The tone a hub status is drawn in, always beside its word.
public enum McpTone: Equatable, Sendable {
    case good
    case bad
    case quiet
}

/// Where one press on the hub stands, said in its own row rather than at the top of a page the person may not be looking at.
public enum McpPress: Equatable, Sendable {
    /// With the runtime now.
    case working
    /// Proposed, and waiting for the person's signature on the island, with what the runtime said about it.
    case waiting(String?)
    case done(String)
    case failed(String)
}

/// A secret named across the hub, with every server that uses it and whether this computer holds it.
public struct HubSecret: Equatable, Sendable {
    public let name: String
    public let held: Bool
    public let usedBy: [String]

    public init(name: String, held: Bool, usedBy: [String]) {
        self.name = name
        self.held = held
        self.usedBy = usedBy
    }
}

/// The MCP Hub's words, the same as Windows and Linux say them in shared/tauri-core's mcp-hub-lines.ts.
public enum McpHubLines {
    /// The word and tone a server's health is shown with.
    public static func health(_ health: McpServerHealth) -> (word: String, tone: McpTone) {
        switch health.healthState {
        case .healthy: return ("Answering", .good)
        case .error: return ("Not answering", .bad)
        case .unknown, nil: return ("Not tested yet", .quiet)
        }
    }

    public static func tools(_ count: Int) -> String {
        if count == 0 { return "No tools listed yet" }
        return count == 1 ? "1 tool" : "\(count) tools"
    }

    public static func calls(_ count: Int) -> String {
        if count == 0 { return "No calls this week" }
        return count == 1 ? "1 call this week" : "\(count) calls this week"
    }

    public static func agents(_ count: Int) -> String {
        if count == 0 { return "Given to no agent yet" }
        return count == 1 ? "Given to 1 agent" : "Given to \(count) agents"
    }

    /// The pill a card wears beside its name: reached over the network or started on this computer.
    public static func transport(_ server: McpHubServerView) -> String {
        server.hubTransport == .http ? "Remote" : "Local"
    }

    /// Which agents use a server, by name: "Claude Code and Cursor", or that none was given it yet.
    public static func usedBy(_ server: McpHubServerView) -> String {
        let names = agentsOnce(server).map(agentLabel)
        guard let last = names.last else { return agents(0) }
        if names.count == 1 { return last }
        return "\(names.dropLast().joined(separator: ", ")) and \(last)"
    }

    /// What one card says under the name: how it is reached, without the arguments, which can be long.
    public static func launch(_ server: McpHubServerView) -> String {
        if server.hubTransport == .http { return server.url ?? "A remote server" }
        return server.command ?? "A local server"
    }

    /// Secrets a server names that this computer does not hold, which keep it from starting.
    public static func missingSecrets(_ server: McpHubServerView) -> [String] {
        missingSecrets(server.secretsHeld)
    }

    public static func missingSecrets(_ held: [String: Bool]) -> [String] {
        held.filter { !$0.value }.map(\.key).sorted()
    }

    /// Every secret named across the hub, once each, with the servers that use it in the order they are listed.
    public static func secretsAcross(_ servers: [(name: String, secretsHeld: [String: Bool])]) -> [HubSecret] {
        var byName: [String: (held: Bool, usedBy: [String])] = [:]
        for server in servers {
            for (name, held) in server.secretsHeld.sorted(by: { $0.key < $1.key }) {
                let entry = byName[name] ?? (held, [])
                byName[name] = (entry.held && held, entry.usedBy + [server.name])
            }
        }
        return byName.map { HubSecret(name: $0.key, held: $0.value.held, usedBy: $0.value.usedBy) }
            .sorted { $0.name < $1.name }
    }

    public static func secretsAcross(_ servers: [McpHubServerView]) -> [HubSecret] {
        secretsAcross(servers.map { (name: $0.name, secretsHeld: $0.secretsHeld) })
    }

    /// A word a person typed turned into a name the hub and every agent's config accept.
    public static func serverName(from typed: String) -> String {
        let lowered = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let joined = lowered.replacingOccurrences(of: "[^a-z0-9._-]+", with: "-", options: .regularExpression)
        let started = joined.replacingOccurrences(of: "^[^a-z0-9]+", with: "", options: .regularExpression)
        return String(started.prefix(serverNameLimit))
    }

    /// The longest name the runtime's registry accepts.
    static let serverNameLimit = 64

    /// A launch line typed in one field, split the way a shell would for plain words and quoted ones.
    public static func splitCommand(_ line: String) -> (command: String, args: [String])? {
        let pattern = #""[^"]*"|'[^']*'|\S+"#
        // The pattern is a literal that always compiles.
        let expression = try! NSRegularExpression(pattern: pattern)
        let whole = NSRange(line.startIndex..., in: line)
        let words = expression.matches(in: line, range: whole).compactMap { match -> String? in
            guard let range = Range(match.range, in: line) else { return nil }
            return unquoted(String(line[range]))
        }
        guard let command = words.first else { return nil }
        return (command, Array(words.dropFirst()))
    }

    private static func unquoted(_ word: String) -> String {
        guard word.count >= 2, let first = word.first, first == "\"" || first == "'", word.last == first else { return word }
        return String(word.dropFirst().dropLast())
    }

    /// The secret name a variable marked secret is kept under, so two servers' tokens never share a name.
    public static func secretName(server: String, variable: String) -> String {
        "\(server)-\(variable.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "_", with: "-"))"
    }

    /// "Wrote 2 configs: 1 added, 1 removed." or that nothing needed writing.
    public static func synced(_ synced: McpSyncSummary) -> String {
        let parts = [
            synced.added > 0 ? "\(synced.added) added" : nil,
            synced.updated > 0 ? "\(synced.updated) updated" : nil,
            synced.removed > 0 ? "\(synced.removed) removed" : nil,
        ].compactMap { $0 }
        if parts.isEmpty { return "Every agent already has what the hub gives it." }
        let files = synced.files.count == 1 ? "1 config" : "\(synced.files.count) configs"
        return "Wrote \(files): \(parts.joined(separator: ", "))."
    }

    /// Said in a row while its change waits on the island, since a press there otherwise seems to do nothing.
    public static let waitingForTouchID = "Waiting for Touch ID on the island"
    /// Said once a proposal stopped waiting and the hub does not show it written: declined, or run out.
    public static let notSigned = "Not signed, so nothing changed."

    /// The words a row shows for where its last press stands, and their tone; nothing while none was made.
    public static func pressLine(_ press: McpPress?) -> (text: String, tone: McpTone)? {
        switch press {
        case nil, .working?: return nil
        case .waiting(let note)?: return ([waitingForTouchID, note].compactMap { $0 }.joined(separator: ". "), .quiet)
        case .done(let line)?: return (line, .good)
        case .failed(let why)?: return (why, .bad)
        }
    }

    /// What the page says after a server is added: who it waits on, what will run, and who gets it once signed.
    public static func added(_ press: McpPress?, server: String, agents: [String]) -> String? {
        guard case .waiting(let note)? = press else { return pressLine(press)?.text }
        var parts = ["\(server) waits for Touch ID on the island"]
        if let note { parts.append(sentence(note)) }
        let names = agents.map(agentLabel)
        if let last = names.last {
            let who = names.count == 1 ? last : "\(names.dropLast().joined(separator: ", ")) and \(last)"
            parts.append("Once it is signed, giving it to \(who) asks for Touch ID again")
        }
        return parts.joined(separator: ". ") + "."
    }

    /// A line without the full stop it may already carry, so two joined never read "..".
    private static func sentence(_ line: String) -> String {
        line.hasSuffix(".") ? String(line.dropLast()) : line
    }

    /// Why a line the hub wrote is left alone, in the person's terms.
    public static func leftAlone(_ entry: McpHubEntryView) -> String {
        if let reason = entry.reason { return reason }
        if entry.kind == "removed" { return "You removed the line the hub wrote, so it is not put back." }
        return "You changed the line the hub wrote, so the hub leaves it alone."
    }

    /// An organization's server is read only here: it is given, changed and removed in Memnox Cloud.
    public static func fromOrganization(_ server: McpHubServerView) -> Bool {
        fromOrganization(scope: server.scope)
    }

    public static func fromOrganization(scope: String?) -> Bool {
        scope == McpScope.organization.rawValue
    }

    public static let organizationWord = "From your organization"
    public static let organizationLine = "Your organization set this server up, so who has it is changed in Memnox Cloud rather than here."

    /// The name an agent goes by, from the kind the runtime reports; an unknown kind is shown as it is.
    public static func agentLabel(_ kind: String) -> String {
        agentNames[kind] ?? kind
    }

    /// One repository an agent was given a server in: the folder name a chip shows, and the full path for its help.
    public struct ProjectChip: Equatable, Sendable {
        public let name: String
        public let path: String
    }

    /// A repository's folder name from its absolute path, so a chip stays short.
    public static func projectFolder(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    /// The repositories one agent was given a server in; none for an agent given it everywhere, or an older runtime.
    public static func projects(_ server: McpHubServerView, agent: String) -> [ProjectChip] {
        server.projects(of: agent).map { ProjectChip(name: projectFolder($0), path: $0) }
    }

    /// What a project chip's help says: whose assignment it is and the repository in full.
    public static func projectHelp(agent: String, path: String) -> String {
        "Given to \(agentLabel(agent)) in \(path) only"
    }

    /// How far one agent has a server: in every project, only in the repositories named, or not at all.
    public enum Reach: Equatable, Sendable {
        case everywhere
        case projects
        case none
    }

    /// The runtime lists an agent in `agents` once per assignment, a repository's included, so an agent counted
    /// there more often than in `projects` also has it everywhere.
    public static func reach(_ server: McpHubServerView, agent: String) -> Reach {
        let given = server.agents.filter { $0 == agent }.count
        let inProjects = server.projects(of: agent).count
        if given > inProjects { return .everywhere }
        return inProjects > 0 ? .projects : .none
    }

    /// What an agent's row says under its name, for each reach, so a project only assignment never reads as everywhere.
    public static func reachCaption(_ server: McpHubServerView, agent: String) -> String? {
        switch reach(server, agent: agent) {
        case .everywhere: return "Has this server in every project"
        case .none: return nil
        case .projects:
            let chips = projects(server, agent: agent)
            if chips.count == 1, let only = chips.first { return "Has this server only in \(only.name)" }
            return "Has this server only in \(chips.count) projects"
        }
    }

    /// Why a project only assignment is never taken away here: unticking would remove nothing.
    public static let projectOnlyLine = "A folder means the agent has this server only in that project. It is given in that project's settings, so it is changed in Workspaces, and giving it here gives it in every project."
    /// The control beside a project only assignment: it gives the server everywhere, signed like every other give.
    public static let giveEverywhere = "Give in every project"
    public static let workspacesLink = "Open Workspaces"

    /// The help on a project only cell: who has it, where, and where it is changed.
    public static func projectOnlyHelp(_ server: McpHubServerView, agent: String) -> String {
        let paths = server.projects(of: agent).joined(separator: ", ")
        return "\(agentLabel(agent)) has this server only in \(paths), given in that project's settings in Workspaces."
    }

    /// Each agent a server is shown on once, in the hub's order, since one given in two repositories is listed twice.
    public static func agentsOnce(_ server: McpHubServerView) -> [String] {
        var seen = Set<String>()
        return server.agents.filter { seen.insert($0).inserted }
    }

    private static let agentNames: [String: String] = [
        "claude-code": "Claude Code",
        "claude-desktop": "Claude Desktop",
        "codex-cli": "Codex",
        "cursor": "Cursor",
        "cline": "Cline",
        "vscode": "VS Code",
        "gemini-cli": "Gemini CLI",
        "windsurf": "Windsurf",
        "copilot-cli": "Copilot CLI",
        "opencode": "OpenCode",
        "hermes": "Hermes",
        "openclaw": "OpenClaw",
        "devin": "Devin",
        "ruflo": "Ruflo",
    ]
}
