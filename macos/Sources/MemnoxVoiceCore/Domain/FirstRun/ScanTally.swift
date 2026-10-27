import Foundation

/// The kinds of thing the scan after setup counts, in the order it says them.
public enum ScanKind: String, CaseIterable, Sendable {
    case agents
    case skills
    case servers
    case sources
    case apps

    /// The heading over its count.
    public var title: String {
        switch self {
        case .agents: return "Agents"
        case .skills: return "Skills"
        case .servers: return "MCP servers"
        case .sources: return "Memory sources"
        case .apps: return "Connected apps"
        }
    }
}

/// One thing the scan found, by name, with where it was found when that says more.
public struct ScanFinding: Equatable, Sendable {
    public let kind: ScanKind
    public let name: String
    public let detail: String?
}

/// Everything the scan found, kind by kind, which the voice sums up over the full screen scan.
public struct ScanTally: Equatable, Sendable {
    public let findings: [ScanFinding]

    public init(findings: [ScanFinding]) {
        self.findings = findings
    }

    public func count(_ kind: ScanKind) -> Int {
        findings.filter { $0.kind == kind }.count
    }
}

/// Builds the scan from what the app reads off the daemon, and says it in a line. A skill is counted once by name, so
/// one in the hub and still in an agent's folder is one skill; a server once by name and the program it starts.
public enum ScanLines {
    /// `scanned` is the runtime's own live scan, which names the agents and their servers when the daemon answers it.
    public static func tally(agents: [AgentStanding], scanned: AgentsScanView? = nil, skills: SkillsHubView?, servers: McpHubView?,
                             sources: [MemorySourceView], apps: [YourAppCard]) -> ScanTally {
        var findings = agentFindings(agents, scanned: scanned)
        findings += skillFindings(skills)
        findings += serverFindings(servers, scanned: scanned)
        findings += sources.map { ScanFinding(kind: .sources, name: $0.name, detail: nil) }
        findings += reachable(apps).map { ScanFinding(kind: .apps, name: $0.name, detail: $0.standing.line) }
        return ScanTally(findings: findings)
    }

    /// The live scan's agents when there is one, each with its card's standing where the cards know it.
    private static func agentFindings(_ agents: [AgentStanding], scanned: AgentsScanView?) -> [ScanFinding] {
        guard let scanned else {
            return agents.map { ScanFinding(kind: .agents, name: $0.name, detail: FirstRunLines.agentDetail($0)) }
        }
        return scanned.agents.map { node in
            let card = agents.first { "agt_\($0.kind)" == node.id || $0.kind == node.kind }
            return ScanFinding(kind: .agents, name: node.name, detail: card.map(FirstRunLines.agentDetail))
        }
    }

    /// The hub's skills and the skills still only in an agent's folder. A persona is an agent rather than a skill, and
    /// one already imported is the hub's own, so neither is counted again.
    private static func skillFindings(_ skills: SkillsHubView?) -> [ScanFinding] {
        let kept = (skills?.skills ?? []).map { ($0.name, "In Memnox") }
        let found = (skills?.found ?? [])
            .filter { $0.kind == skillKind && !$0.imported }
            .map { ($0.name, "In \(McpHubLines.agentLabel($0.agent))") }
        return unique(kept + found).map { ScanFinding(kind: .skills, name: $0.0, detail: $0.1) }
    }

    /// What a found skill is called when it is a skill, as against a persona.
    private static let skillKind = "skill"

    /// The servers on this Mac: the hub's, each agent's own, and the lines the hub found in an agent's config. A
    /// repository's own file is the project's rather than this Mac's, so its lines are left out.
    private static func serverFindings(_ servers: McpHubView?, scanned: AgentsScanView?) -> [ScanFinding] {
        // The hub writes its servers into the agents' configs, often behind the Memnox proxy, so a line by its name is
        // that server whatever program it starts.
        var lines = (servers?.servers ?? []).map { ServerLine(name: $0.name, command: nil, detail: "In Memnox") }
        for node in scanned?.agents ?? [] {
            lines += (node.mcp ?? []).map { ServerLine(name: $0.name, command: $0.command, detail: "In \(node.name)") }
        }
        lines += (servers?.found ?? []).compactMap { entry in
            entry.agent.map { ServerLine(name: entry.name, command: nil, detail: "In \(McpHubLines.agentLabel($0))") }
        }
        return distinct(lines).map { ScanFinding(kind: .servers, name: $0.name, detail: $0.detail) }
    }

    /// The first line of each server, where two lines are one server when they share a name and neither names a
    /// different program; the same name starting two programs is two servers.
    static func distinct(_ lines: [ServerLine]) -> [ServerLine] {
        var kept: [ServerLine] = []
        for line in lines where !kept.contains(where: { $0.sameServer(as: line) }) {
            kept.append(line)
        }
        return kept
    }

    /// The apps an agent can act in now: connected, or reached on this Mac itself. One only offered, or needing a
    /// sign in again, is not counted, so the number is what works today.
    public static func reachable(_ apps: [YourAppCard]) -> [YourAppCard] {
        apps.filter { app in
            switch app.standing {
            case .connected, .onThisMac: return true
            case .signInAgain, .available: return false
            }
        }
    }

    /// The agents as the full screen scan draws them from the cards, for a daemon too old to answer agents-scan. The
    /// cards hold only the hub's servers, no tool counts and running sessions that include ones merely open, so the
    /// tools, capabilities and working are left unknown here and the scan says so rather than a false zero.
    public static func nodes(_ agents: [AgentStanding]) -> [AgentNode] {
        agents.map { agent in
            AgentNode(id: "agt_\(agent.kind)", kind: agent.kind, name: agent.name, servers: agent.mcpServers.count,
                      mcp: agent.mcpServers.map { AgentServer(name: $0) })
        }
    }

    /// "Found 3 agents, 90 skills, 4 MCP servers, 2 memory sources and no connected apps."
    public static func summary(_ tally: ScanTally) -> String {
        let parts = ScanKind.allCases.map { kind in counted(tally.count(kind), kind) }
        return "Found \(listed(parts))."
    }

    private static func counted(_ count: Int, _ kind: ScanKind) -> String {
        let many = plural(kind)
        let one: String
        switch kind {
        case .agents: one = "agent"
        case .skills: one = "skill"
        case .servers: one = "MCP server"
        case .sources: one = "memory source"
        case .apps: one = "connected app"
        }
        switch count {
        case 0: return "no \(many)"
        case 1: return "1 \(one)"
        default: return "\(count) \(many)"
        }
    }

    /// The heading lowercased for a sentence, but MCP stays in capitals since it is said as letters.
    private static func plural(_ kind: ScanKind) -> String {
        kind == .servers ? "MCP servers" : kind.title.lowercased()
    }

    private static func listed(_ parts: [String]) -> String {
        guard let last = parts.last else { return "" }
        let rest = parts.dropLast()
        return rest.isEmpty ? last : "\(rest.joined(separator: ", ")) and \(last)"
    }

    /// The first of each name, in order.
    private static func unique(_ named: [(String, String)]) -> [(String, String)] {
        var seen: Set<String> = []
        return named.filter { seen.insert($0.0).inserted }
    }
}

/// One MCP server line the scan found, by name and, where known, the program it starts.
struct ServerLine: Equatable {
    let name: String
    let command: String?
    let detail: String?

    /// The same server when the names match and neither names a different program.
    func sameServer(as other: ServerLine) -> Bool {
        guard name == other.name else { return false }
        guard let command, let theirs = other.command else { return true }
        return command == theirs
    }
}

/// A figure along the bottom of the full screen scan: a count, still being counted, or not known at all.
public enum ScanFigure: Equatable, Sendable {
    case counted(Int)
    /// The runtime is asking the servers now, so the figure lands on the next answer.
    case counting
    /// Nothing here can count it, from a daemon too old to scan, so the figure is left off rather than drawn as zero.
    case unknown
}

/// The full screen scan's totals, worked out from the agents it draws so a zero is only ever a counted zero.
public enum ScanFigures {
    /// The tools of every server once, by name and program, so one server two agents share counts once.
    public static func tools(_ agents: [AgentNode]) -> ScanFigure {
        let servers = uniqueServers(agents)
        if servers.allSatisfy({ $0.tools != nil }) { return .counted(servers.reduce(0) { $0 + ($1.tools ?? 0) }) }
        if counting(agents) { return .counting }
        // A counted scan whose server still names no tools answered with none it could list, so the known ones stand.
        if scanned(agents) { return .counted(servers.reduce(0) { $0 + ($1.tools ?? 0) }) }
        return .unknown
    }

    /// The runtime's shares added up; an older daemon's per server figure where every server has one.
    public static func capabilities(_ agents: [AgentNode]) -> ScanFigure {
        if counting(agents) { return .counting }
        if scanned(agents) { return .counted(agents.reduce(0) { $0 + ($1.capabilities?.total ?? 0) }) }
        let servers = uniqueServers(agents)
        guard !servers.isEmpty, servers.allSatisfy({ $0.changing != nil }) else { return .unknown }
        return .counted(servers.reduce(0) { $0 + ($1.changing ?? 0) })
    }

    /// Sessions working now; unknown where the agents came from cards that count an open session as running.
    public static func working(_ agents: [AgentNode], sessionsKnown: Bool) -> ScanFigure {
        sessionsKnown ? .counted(agents.reduce(0) { $0 + $1.working }) : .unknown
    }

    /// Every agent drew its share from the runtime's scan.
    private static func scanned(_ agents: [AgentNode]) -> Bool {
        !agents.isEmpty && agents.allSatisfy { $0.capabilities != nil }
    }

    /// Some agent's share is still being counted.
    private static func counting(_ agents: [AgentNode]) -> Bool {
        agents.contains { $0.capabilities != nil && $0.capabilities?.total == nil }
    }

    private static func uniqueServers(_ agents: [AgentNode]) -> [AgentServer] {
        var kept: [AgentServer] = []
        for server in agents.flatMap({ $0.mcp ?? [] }) {
            let line = ServerLine(name: server.name, command: server.command, detail: nil)
            if !kept.contains(where: { ServerLine(name: $0.name, command: $0.command, detail: nil).sameServer(as: line) }) {
                kept.append(server)
            }
        }
        return kept
    }
}
