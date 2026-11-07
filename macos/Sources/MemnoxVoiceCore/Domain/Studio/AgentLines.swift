import Foundation

/// Which agents the Agents page shows: all of them, the ones with a session running, or one standing.
public enum AgentFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case running
    case unprotected
    case paused

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "All"
        case .running: "Running"
        case .unprotected: "Not protected"
        case .paused: "Paused"
        }
    }

    public func admits(_ agent: AgentStanding) -> Bool {
        switch self {
        case .all: true
        case .running: agent.sessions.running > 0
        case .unprotected: agent.agentStatus == .unprotected
        case .paused: agent.agentStatus == .paused
        }
    }
}

/// The one press a card leads with: Protect where the agent runs outside Memnox, else pause or resume it.
public enum AgentPress: String, Sendable {
    case protect
    case pause
    case resume
}

/// The skill names a card shows as chips, and how many more it holds than fit.
public struct AgentChips: Equatable, Sendable {
    public let shown: [String]
    public let more: Int
}

/// The one step a Protect result offers beside its line, where the app can take it for the person.
public enum ProtectFollowUp: String, Sendable {
    /// The daemon answering predates the app, so it cannot say the agent is held until it runs the newer runtime.
    case restartService
}

/// What a Protect press came to for the agents it was pressed for, read from the cards the runtime drew after it.
public struct ProtectResult: Equatable, Sendable {
    /// The agents the press was for, by kind, so a card shows only its own.
    public let kinds: [String]
    public let line: String
    /// True when every one of them is protected now.
    public let held: Bool
    /// The press offered beside the line, nil where there is nothing the app can do for the person.
    public let followUp: ProtectFollowUp?
    /// When the runtime's cards were read after the press, so the line says how fresh it is.
    public let at: Date?

    public init(kinds: [String], line: String, held: Bool, followUp: ProtectFollowUp? = nil, at: Date? = nil) {
        self.kinds = kinds
        self.line = line
        self.held = held
        self.followUp = followUp
        self.at = at
    }

    public func covers(_ kind: String) -> Bool { kinds.contains(kind) }
}

/// One small labelled number on an agent's card.
public struct AgentFigure: Equatable, Sendable {
    public let label: String
    public let value: Int
    /// Amber for what waited on a person, red for what was refused, plain otherwise.
    public let tone: StudioTone
}

/// The Agents page's counts and sentences, worked out from what the runtime's AgentView says and nothing more.
public enum AgentLines {
    /// Said on a card whose agent has no session running and did nothing today.
    public static let nothingToday = "Nothing today"

    /// "6 agents, 5 protected, 1 running"
    public static func summary(_ agents: [AgentStanding]) -> String {
        let protected = agents.filter { $0.agentStatus == .protected }.count
        let running = agents.filter { AgentFilter.running.admits($0) }.count
        return "\(counted(agents.count, "agent", "agents")), \(protected) protected, \(running) running"
    }

    /// The agents a filter admits, the ones needing a decision first.
    public static func shown(_ agents: [AgentStanding], _ filter: AgentFilter) -> [AgentStanding] {
        StudioLines.sortedAgents(agents.filter(filter.admits))
    }

    public static func count(_ agents: [AgentStanding], _ filter: AgentFilter) -> Int {
        agents.filter(filter.admits).count
    }

    /// The chips worth offering: All, Running and Paused always, so their counts read even at nought, and Not protected
    /// only while some agent is, since that chip is a call to act.
    public static func filters(_ agents: [AgentStanding]) -> [AgentFilter] {
        AgentFilter.allCases.filter { $0 != .unprotected || count(agents, $0) > 0 }
    }

    /// The press a card leads with, read from the standing the runtime reported.
    public static func press(_ agent: AgentStanding) -> AgentPress {
        switch agent.agentStatus {
        case .unprotected: .protect
        case .paused: .resume
        case .protected, .dormant, nil: .pause
        }
    }

    /// The card's quiet line under its numbers: when it last did anything, and how many skills and MCP servers it has.
    public static func reachLine(_ agent: AgentStanding, now: Date) -> String {
        let seen = SessionText.ago(agent.recent.first?.at, now: now).map { "Last active \($0)" } ?? "No activity seen yet"
        let skills = counted(agent.skills?.count ?? 0, "skill", "skills")
        let servers = counted(agent.mcpServers.count, "MCP server", "MCP servers")
        return "\(seen) \u{00B7} \(skills) \u{00B7} \(servers)"
    }

    /// The first few skills by name and a count of the rest, so a card keeps one line of chips.
    public static func chips(_ names: [String]?, limit: Int) -> AgentChips {
        let names = names ?? []
        return AgentChips(shown: Array(names.prefix(limit)), more: max(0, names.count - limit))
    }

    /// Only the numbers that say something: sessions running and today's actions, asks and refusals above nought.
    public static func figures(_ agent: AgentStanding) -> [AgentFigure] {
        [
            AgentFigure(label: "Running", value: agent.sessions.running, tone: .good),
            AgentFigure(label: "Today", value: agent.today.actions, tone: .quiet),
            AgentFigure(label: "Asked", value: agent.today.asked, tone: .attention),
            AgentFigure(label: "Refused", value: agent.today.refused, tone: .bad),
        ].filter { $0.value > 0 }
    }

    /// Who runs outside Memnox, for the strip over the page: "Claude Desktop is not protected", nil while every agent is.
    public static func needsProtecting(_ agents: [AgentStanding]) -> String? {
        let names = agents.filter { $0.agentStatus == .unprotected }.map(\.name)
        guard !names.isEmpty else { return nil }
        return "\(listed(names)) \(names.count == 1 ? "is" : "are") not protected"
    }

    /// The agents a Protect press is for: the one card, or every agent the strip names.
    public static func unprotectedKinds(_ agents: [AgentStanding]) -> [String] {
        agents.filter { $0.agentStatus == .unprotected }.map(\.kind)
    }

    /// Whether the daemon answering predates seams: no card it drew says how Memnox holds its agent, which a runtime
    /// that knows seams always says for an agent with a hook, so an agent held through its servers reads as outside.
    public static func runtimePredatesSeams(_ agents: [AgentStanding]) -> Bool {
        !agents.isEmpty && agents.allSatisfy { $0.seam == nil }
    }

    /// What a Protect press came to, from the runtime's cards read after it: the reason it failed, that they are
    /// protected and whether an app must be opened again to take its servers up, or what still keeps one outside.
    /// `restarted` is true once the app restarted the service for this press, so a service still too old says so.
    public static func afterProtect(
        _ kinds: [String], agents: [AgentStanding], failed: String?, restarted: Bool = false, at: Date? = nil
    ) -> ProtectResult {
        if let failed { return ProtectResult(kinds: kinds, line: failed, held: false, at: at) }
        let asked = agents.filter { kinds.contains($0.kind) }
        let left = asked.filter { $0.agentStatus == .unprotected }
        guard let first = left.first else {
            return ProtectResult(kinds: kinds, line: protectedLine(asked), held: true, at: at)
        }
        let names = left.map(\.name)
        let one = names.count == 1
        if runtimePredatesSeams(agents) {
            let line = restarted
                ? "The Memnox service restarted but still runs a runtime older than this app, so it counts \(listed(names)) "
                    + "as outside. Update the runtime, then restart the service."
                : "The Memnox service on this Mac is older than this app, so it cannot see that \(listed(names)) "
                    + "\(one ? "is" : "are") held. Restart it to run the newer runtime."
            return ProtectResult(kinds: kinds, line: line, held: false, followUp: .restartService, at: at)
        }
        let line: String
        switch first.agentSeam {
        case .servers:
            line = "\(listed(names)) still \(one ? "starts" : "start") a server outside Memnox, which setup leaves alone "
                + "when it cannot find memnox-mcp-proxy. In a terminal: memnox mcp wrap"
        case .hook:
            line = "\(listed(names)) \(one ? "is" : "are") still not protected because \(one ? "its" : "their") hook did not go in. "
                + "In a terminal: memnox setup"
        case nil:
            line = "Memnox has no way into \(listed(names)) yet, so Protect cannot hold \(one ? "it" : "them")."
        }
        return ProtectResult(kinds: kinds, line: line, held: false, at: at)
    }

    /// "Claude Desktop is protected. Quit and open it again so its servers start through Memnox."
    private static func protectedLine(_ agents: [AgentStanding]) -> String {
        let names = agents.map(\.name)
        guard !names.isEmpty else { return "Your agents are protected." }
        let done = "\(listed(names)) \(names.count == 1 ? "is" : "are") protected."
        // An agent held only through its servers reads its config when it opens, so the change waits for a restart.
        let reopen = agents.filter { $0.agentSeam == .servers }.map(\.name)
        guard !reopen.isEmpty else { return done }
        let one = reopen.count == 1
        return "\(done) Quit and open \(listed(reopen)) again so \(one ? "its" : "their") servers start through Memnox."
    }

    /// "A", "A and B", "A, B and C".
    private static func listed(_ names: [String]) -> String {
        guard let last = names.last else { return "" }
        if names.count == 1 { return last }
        return "\(names.dropLast().joined(separator: ", ")) and \(last)"
    }

    /// A recent action's target as a person names it, the path's last parts, or nil where it had none.
    public static func target(_ action: AgentAction) -> String? {
        guard let target = action.target?.trimmingCharacters(in: .whitespacesAndNewlines), !target.isEmpty else { return nil }
        return target.contains("/") ? SessionText.shortPath(target) : target
    }

    /// Said where a filter leaves no agent to show.
    public static func noneShown(_ filter: AgentFilter) -> String {
        switch filter {
        case .all: "No agents found yet."
        case .running: "No agent has a session running right now."
        case .unprotected: "Every agent here is protected."
        case .paused: "No agent is paused."
        }
    }

    private static func counted(_ count: Int, _ one: String, _ many: String) -> String {
        count == 1 ? "1 \(one)" : "\(count) \(many)"
    }
}
