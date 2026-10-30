import Foundation

/// Green goes ahead, amber waits, red is refused, grey says nothing either way.
public enum StudioTone: Equatable, Sendable {
    case good
    case attention
    case bad
    case quiet
}

/// One effect in the words the console uses: its name, and what it means for an agent.
public struct EffectWords: Equatable, Sendable {
    public let title: String
    public let says: String
}

/// One of the switches most people want first, each only a rule proposed with these fields.
public struct AlwaysAskSwitch: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let draft: RuleDraftInput
}

/// The words the Policies, Activity and Agents pages say, the same as Windows and Linux say them. Counts, never a score.
public enum StudioLines {
    /// The three effects, each explained once.
    public static func words(_ effect: RuleEffect) -> EffectWords {
        switch effect {
        case .allow: EffectWords(title: "Allow", says: "Goes ahead on its own")
        case .ask: EffectWords(title: "Ask", says: "Waits for a person to say yes")
        case .deny: EffectWords(title: "Deny", says: "Refused, and told what to do instead")
        }
    }

    /// An effect's name, or the runtime's own word for one this app does not know yet.
    public static func title(_ effect: String) -> String {
        RuleEffect(rawValue: effect).map { words($0).title } ?? effect
    }

    /// What an effect means, or the runtime's own word for one this app does not know yet.
    public static func says(_ effect: String) -> String {
        RuleEffect(rawValue: effect).map { words($0).says } ?? effect
    }

    public static func tone(_ effect: String) -> StudioTone {
        switch RuleEffect(rawValue: effect) {
        case .allow: .good
        case .ask: .attention
        case .deny: .bad
        case nil: .quiet
        }
    }

    /// Where a rule came from, said as a person would.
    public static func sourceWords(_ source: String, decidedBy: String? = nil, file: String? = nil) -> String {
        switch RuleSource(rawValue: source) {
        case .person: decidedBy.map { "Set by \($0)" } ?? "Set on this computer"
        case .file: file.map { "From \($0)" } ?? "From a rule file"
        case .workspace: "From your team"
        case .default: "Built in"
        case .autopilot: "Earned by the autopilot"
        case .allowance: "Allowed for a while"
        case .freeze: "A freeze"
        case nil: source
        }
    }

    public static func sourceWords(_ rule: PolicyRuleView) -> String {
        sourceWords(rule.source, decidedBy: rule.decidedBy, file: rule.file)
    }

    /// Rules counted per effect, for the filter chips.
    public static func countsByEffect(_ rules: [PolicyRuleView]) -> [RuleEffect: Int] {
        var counts: [RuleEffect: Int] = [.allow: 0, .ask: 0, .deny: 0]
        for rule in rules {
            if let effect = rule.ruleEffect { counts[effect, default: 0] += 1 }
        }
        return counts
    }

    /// "Asked you 12 times this week, 31 last week."
    public static func weekLine(thisWeek: ProgressWeek, lastWeek: ProgressWeek) -> String {
        "Asked you \(times(thisWeek.asked)) this week, \(times(lastWeek.asked)) last week."
    }

    public static func weekLine(_ progress: AutonomyProgress) -> String {
        weekLine(thisWeek: progress.thisWeek, lastWeek: progress.lastWeek)
    }

    public static func autopilotLine(_ count: Int) -> String {
        if count == 0 { return "The autopilot answered nothing for you this week." }
        return count == 1 ? "The autopilot answered 1 ask for you this week." : "The autopilot answered \(count) asks for you this week."
    }

    /// The week and the autopilot in one line, as Home and Let go both say it.
    public static func thisWeek(_ progress: AutonomyProgress) -> String {
        "\(weekLine(progress)) \(autopilotLine(progress.thisWeek.answeredByAutopilot))"
    }

    public static func almostLine(_ item: ProgressAlmost) -> String {
        let more = item.needed - item.approvals
        return more == 1 ? "1 more yes to \(item.action) and it is ready to let go"
            : "\(more) more yeses to \(item.action) and it is ready to let go"
    }

    /// What one activity row did, in a line.
    public static func activityLine(operation: String, target: String?) -> String {
        target.map { "\(operation) \($0)" } ?? operation
    }

    public static func answeredWords(by person: String?, how: String?) -> String? {
        guard let person else { return nil }
        switch how.flatMap(AnsweredHow.init(rawValue:)) {
        case .signed: return "\(person), signed"
        case .withinSession: return "\(person), inside its session"
        case .other, nil: return person
        }
    }

    /// The rules in an exported file, counted so a person knows what they are saving.
    public static let nothingToExport = "No rule set on this computer to export yet."

    /// Said once a pack was written to the file the person picked.
    public static func packSaved(_ count: Int) -> String {
        count == 1 ? "Saved 1 rule as TOML, ready to share." : "Saved \(count) rules as TOML, ready to share."
    }

    /// Said once a pack was copied, where no save dialog is to be had.
    public static func packCopied(_ count: Int) -> String {
        "Copied \(count) rules as TOML, ready to save or share."
    }

    public static func exportedCount(_ toml: String) -> Int {
        toml.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.trimmingCharacters(in: .whitespaces) == "[[policies]]" }
            .count
    }

    /// What a rule being built will do, read back before it is proposed; the runtime words the one it keeps.
    public static func draftSentence(_ draft: RuleDraftInput, agentName: (String) -> String) -> String {
        let agents = draft.agents ?? []
        let who = agents.isEmpty ? "any agent" : agents.map(agentName).joined(separator: " or ")
        let action = draft.action.trimmingCharacters(in: .whitespaces)
        let what = action.isEmpty ? "this action" : action
        let on = ((draft.targets ?? []).map { "on \($0)" } + (draft.branches ?? []).map { "on the \($0) branch" }
            + (draft.workingDirectories ?? []).map { "in \($0)" }).joined(separator: " ")
        let tail = on.isEmpty ? "" : " \(on)"
        switch RuleEffect(rawValue: draft.effect) {
        case .allow: return "Let \(who) run \(what)\(tail) without asking."
        case .deny: return "Never let \(who) run \(what)\(tail)."
        case .ask, nil: return "Ask you before \(who) runs \(what)\(tail)."
        }
    }

    public static let alwaysAsk: [AlwaysAskSwitch] = [
        AlwaysAskSwitch(id: "push-main", title: "Pushing to main",
                        draft: RuleDraftInput(effect: .ask, action: "git.push", branches: ["main"],
                                              reason: "you chose to be asked before anything reaches main")),
        AlwaysAskSwitch(id: "delete-files", title: "Deleting files",
                        draft: RuleDraftInput(effect: .ask, action: "filesystem.delete",
                                              reason: "you chose to be asked before files are deleted")),
        AlwaysAskSwitch(id: "mcp-writes", title: "MCP tools that change something",
                        draft: RuleDraftInput(effect: .ask, action: "mcp.*", classes: ["write", "destructive", "communication"],
                                              reason: "you chose to be asked before a tool changes something outside this computer")),
    ]

    /// Whether a rule already in force asks about this switch's action, so the switch shows on.
    public static func switchOn(_ rules: [PolicyRuleView], action: String, branches: [String]? = nil) -> Bool {
        rules.contains { rule in
            rule.effect != RuleEffect.allow.rawValue && rule.match.actions.contains(action)
                && (branches ?? []).allSatisfy { (rule.match.branches ?? []).contains($0) }
        }
    }

    /// The agents that need a decision first: paused, then unprotected, then protected, then dormant.
    public static func sortedAgents(_ agents: [AgentStanding]) -> [AgentStanding] {
        let order: [AgentStatus] = [.paused, .unprotected, .protected, .dormant]
        let rank = { (agent: AgentStanding) in agent.agentStatus.flatMap { order.firstIndex(of: $0) } ?? order.count }
        // Enumerated, so agents of one standing keep the runtime's order.
        return agents.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }

    public static func statusWord(_ status: String) -> (word: String, tone: StudioTone) {
        switch AgentStatus(rawValue: status) {
        case .protected: ("Protected", .good)
        case .unprotected: ("Not protected", .attention)
        case .dormant: ("Dormant", .quiet)
        case .paused: ("Paused", .bad)
        case nil: (status, .quiet)
        }
    }

    /// "1 running, 2 idle, 4 finished · Today 3 actions, 1 asked, 0 refused"
    public static func agentCounts(_ agent: AgentStanding) -> String {
        let sessions = agent.sessions
        let today = agent.today
        return "\(sessions.running) running, \(sessions.idle) idle, \(sessions.finished) finished \u{00B7} "
            + "Today \(today.actions) actions, \(today.asked) asked, \(today.refused) refused"
    }

    private static func times(_ count: Int) -> String {
        count == 1 ? "1 time" : "\(count) times"
    }
}
