import Foundation

// The Policy Studio, the activity timeline and the agents view on the wire, mirrored from the runtime's
// daemon/policies.ts, daemon/activity.ts and daemon/agents-view.ts. Names only: no answer here carries an argument or
// a file's contents.

/// Where a rule in force came from, as the runtime's RULE_SOURCE names it.
public enum RuleSource: String, CaseIterable, Sendable {
    case person
    case file
    case workspace
    case `default`
    case autopilot
    case allowance
    case freeze
}

/// What a rule matches; an absent list matches anything.
public struct PolicyRuleMatch: Decodable, Equatable, Sendable {
    public let actions: [String]
    public let targets: [String]?
    public let agents: [String]?
    public let workingDirectories: [String]?
    public let classes: [String]?
    public let branches: [String]?

    public init(actions: [String], targets: [String]? = nil, agents: [String]? = nil, workingDirectories: [String]? = nil,
                classes: [String]? = nil, branches: [String]? = nil) {
        self.actions = actions
        self.targets = targets
        self.agents = agents
        self.workingDirectories = workingDirectories
        self.classes = classes
        self.branches = branches
    }
}

public struct PolicyRuleView: Decodable, Equatable, Identifiable, Sendable {
    public let name: String
    public let effect: String
    public let match: PolicyRuleMatch
    public let reason: String?
    /// The rule in one plain sentence, to read before the fields.
    public let sentence: String
    public let source: String
    /// The file it was read from, where it lives in one.
    public let file: String?
    /// On a workspace rule: who decided it, and when.
    public let decidedBy: String?
    public let decidedAt: String?
    /// When it ends on its own, for a grant, an allowance or a freeze.
    public let until: String?
    /// Only a rule a person added on this machine, which is the only kind a screen removes.
    public let editable: Bool

    public init(name: String, effect: String, match: PolicyRuleMatch, reason: String? = nil, sentence: String, source: String,
                file: String? = nil, decidedBy: String? = nil, decidedAt: String? = nil, until: String? = nil, editable: Bool) {
        self.name = name
        self.effect = effect
        self.match = match
        self.reason = reason
        self.sentence = sentence
        self.source = source
        self.file = file
        self.decidedBy = decidedBy
        self.decidedAt = decidedAt
        self.until = until
        self.editable = editable
    }

    public var id: String { name }
    public var ruleEffect: RuleEffect? { RuleEffect(rawValue: effect) }
    public var ruleSource: RuleSource? { RuleSource(rawValue: source) }
}

/// A rule file that is there and will not load, so its rules are not in force.
public struct PolicyLoadProblem: Decodable, Equatable, Sendable {
    public let file: String
    public let issues: [String]
}

public struct PolicyRulesView: Decodable, Equatable, Sendable {
    public let rules: [PolicyRuleView]
    public let problems: [PolicyLoadProblem]
    /// Registered files that are gone.
    public let missing: [String]
}

/// A rule as a form fills it in, sent as `ruleDraft`; the runtime reads it back and offers where it holds.
public struct RuleDraftInput: Encodable, Equatable, Sendable {
    public let effect: String
    public let action: String
    public let branches: [String]?
    public let targets: [String]?
    /// The agent kinds it is narrowed to; absent, it reaches every agent.
    public let agents: [String]?
    /// The folders it holds in; absent, it holds everywhere.
    public let workingDirectories: [String]?
    /// What the action does, such as write, destructive or communication.
    public let classes: [String]?
    public let reason: String

    public init(effect: RuleEffect, action: String, branches: [String]? = nil, targets: [String]? = nil, agents: [String]? = nil,
                workingDirectories: [String]? = nil, classes: [String]? = nil, reason: String) {
        self.effect = effect.rawValue
        self.action = action
        self.branches = branches
        self.targets = targets
        self.agents = agents
        self.workingDirectories = workingDirectories
        self.classes = classes
        self.reason = reason
    }
}

/// One action to rule on, the way `memnox policy test` takes it, sent as `ruleTest`.
public struct RuleTestInput: Encodable, Equatable, Sendable {
    /// A command line, or an action named outright such as `git.push`.
    public let action: String
    public let target: String?
    public let agent: String?
    public let workingDirectory: String?

    public init(action: String, target: String? = nil, agent: String? = nil, workingDirectory: String? = nil) {
        self.action = action
        self.target = target
        self.agent = agent
        self.workingDirectory = workingDirectory
    }
}

public struct RuleVerdictView: Decodable, Equatable, Sendable {
    public let effect: String
    public let reason: String
    /// The rule that decided, by name; absent when the default did.
    public let rule: String?
    /// What to do instead, where the rule names a way forward.
    public let instead: String?

    public var ruleEffect: RuleEffect? { RuleEffect(rawValue: effect) }
}

/// An action a person approved often enough, with nothing arguing against handing it over.
public struct ProgressReady: Decodable, Equatable, Sendable {
    public let action: String
    public let approvals: Int
    public let targets: [String]
    public let because: String

    /// The same action as the home's ready block, so handing it over is the home's own press.
    public var homeReady: HomeReady { HomeReady(action: action, approvals: approvals, targets: targets, because: because) }
}

/// Approved, never refused, and not yet often enough.
public struct ProgressAlmost: Decodable, Equatable, Sendable {
    public let action: String
    public let approvals: Int
    /// Approvals still to go before it is ready.
    public let needed: Int

    public init(action: String, approvals: Int, needed: Int) {
        self.action = action
        self.approvals = approvals
        self.needed = needed
    }
}

/// A grant the autopilot made and that still stands.
public struct ProgressGrant: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let actions: [String]
    public let targets: [String]
    public let agents: [String]
    public let since: String
    public let until: String
    public let says: String
}

/// Where the machine stands on the autonomy ladder, and what the next rung asks for.
public struct ProgressLadder: Decodable, Equatable, Sendable {
    public let level: String
    public let says: String
    public let rungs: [String]
    public let next: String?
    /// What the record has to show before the next rung, in a sentence.
    public let needs: String?
    public let actionsThisWeek: Int
    public let asksThisWeek: Int
    /// Actions in a week before the top two rungs can be claimed.
    public let minimumEvidence: Int
}

/// One week in counts, never hours saved.
public struct ProgressWeek: Decodable, Equatable, Sendable {
    public let from: String
    public let asked: Int
    /// Allowed by an autopilot grant rather than by a person.
    public let answeredByAutopilot: Int
    /// Grants the autopilot made in the week.
    public let handedOver: Int

    public init(from: String, asked: Int, answeredByAutopilot: Int, handedOver: Int) {
        self.from = from
        self.asked = asked
        self.answeredByAutopilot = answeredByAutopilot
        self.handedOver = handedOver
    }
}

/// The runtime's ProgressView, named for what it holds since SwiftUI already has a ProgressView.
public struct AutonomyProgress: Decodable, Equatable, Sendable {
    public let ready: [ProgressReady]
    public let almost: [ProgressAlmost]
    public let grants: [ProgressGrant]
    public let autopilotOn: Bool
    public let ladder: ProgressLadder
    public let thisWeek: ProgressWeek
    public let lastWeek: ProgressWeek
}

/// What kind of thing an agent did, as the runtime's ACTIVITY_KIND names it.
public enum ActivityKind: String, CaseIterable, Sendable {
    case tool
    case command
    case file
    case mcp
}

/// How a held call was let through, as the runtime's ANSWERED_HOW names it.
public enum AnsweredHow: String, CaseIterable, Sendable {
    case signed
    case withinSession = "within-session"
    case other
}

/// Which rows a page of activity holds, sent as `activityFilter`.
public struct ActivityFilter: Encodable, Equatable, Sendable {
    public var effect: String?
    /// The agent's kind, such as claude-code.
    public var agent: String?
    public var kind: String?
    /// Matched against the operation, the target and the rule's name, never arguments.
    public var text: String?
    /// ISO 8601; only rows at or after it.
    public var since: String?
    /// ISO 8601; only rows at or before it.
    public var until: String?

    public init(effect: RuleEffect? = nil, agent: String? = nil, kind: ActivityKind? = nil, text: String? = nil,
                since: String? = nil, until: String? = nil) {
        self.effect = effect?.rawValue
        self.agent = agent
        self.kind = kind?.rawValue
        self.text = text
        self.since = since
        self.until = until
    }
}

public struct ActivityRow: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let at: String
    public let agent: String
    public let agentName: String
    public let session: String
    public let kind: String
    public let operation: String
    public let target: String?
    public let effect: String
    /// What enforce would have said, where the mode kept it from being applied.
    public let shadowEffect: String?
    public let rule: String?
    public let reason: String
    public let answeredBy: String?
    public let answeredHow: String?
    /// The exit code, where it ran and failed.
    public let failed: Int?

    public var ruleEffect: RuleEffect? { RuleEffect(rawValue: effect) }
    public var activityKind: ActivityKind? { ActivityKind(rawValue: kind) }
    public var answered: AnsweredHow? { answeredHow.flatMap(AnsweredHow.init(rawValue:)) }
}

/// One row as it is written, for a live timeline: names only, never arguments, output or contents.
public struct LiveActivityRow: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let at: String
    /// The agent's kind, such as claude-code.
    public let agent: String
    public let operation: String
    public let effect: String
    /// The target by name: a path, a host, a server; never what was sent to it.
    public let target: String?

    public init(id: String, at: String, agent: String, operation: String, effect: String, target: String? = nil) {
        self.id = id
        self.at = at
        self.agent = agent
        self.operation = operation
        self.effect = effect
        self.target = target
    }

    public var ruleEffect: RuleEffect? { RuleEffect(rawValue: effect) }
}

public struct ActivityPage: Decodable, Equatable, Sendable {
    public let rows: [ActivityRow]
    /// Handed back as `activityCursor` for the next page; absent on the last.
    public let nextCursor: String?
}

/// The rule that decided, as it stands now beside what the row recorded.
public struct DecisionRule: Decodable, Equatable, Sendable {
    public let name: String
    public let file: String?
    public let line: Int?
    public let source: String?
    public let decidedBy: String?
    public let decidedAt: String?
    /// The workspace has published newer rules since this was decided.
    public let newerSince: Bool?
}

/// One step the session took just before, names only.
public struct DecisionStep: Decodable, Equatable, Sendable {
    public let at: String
    public let operation: String
    public let target: String?
    public let effect: String

    public var ruleEffect: RuleEffect? { RuleEffect(rawValue: effect) }
}

/// The ledger's own account of the action, as `memnox trace` prints it.
public struct DecisionTrace: Decodable, Equatable, Sendable {
    public let mode: String
    public let exitCode: Int?
    public let durationMs: Int?
    public let approvedBy: String?
    public let argsDigest: String?
    public let outputDigest: String?
}

/// One part of what was known when the action was ruled on, in words.
public struct ContextPart: Decodable, Equatable, Sendable {
    public let domain: String
    public let facts: [String]
    /// Something here is why the verdict came out the way it did.
    public let decided: Bool
}

public struct DecisionView: Decodable, Equatable, Sendable {
    public let row: ActivityRow
    public let rule: DecisionRule?
    /// Who handed the work down, as one line: person, agent, helper.
    public let chain: String
    public let context: [ContextPart]
    /// The task somebody declared for the session, where one was.
    public let task: String?
    public let before: [DecisionStep]
    public let alternative: String?
    public let trace: DecisionTrace
}

/// Where an agent stands with Memnox, as the runtime's AGENT_STATUS names it.
public enum AgentStatus: String, CaseIterable, Sendable {
    /// Its hook is in, so every action is ruled on.
    case protected
    /// Found here and running outside Memnox.
    case unprotected
    /// Silent for a month and still holding reach.
    case dormant
    /// A person paused it; nothing it asks for runs.
    case paused
}

public struct AgentSessions: Decodable, Equatable, Sendable {
    public let running: Int
    public let idle: Int
    public let finished: Int
}

public struct AgentToday: Decodable, Equatable, Sendable {
    public let actions: Int
    public let asked: Int
    public let refused: Int
}

/// One thing it did lately, by name.
public struct AgentAction: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let at: String
    public let operation: String
    public let target: String?
    public let effect: String

    public var ruleEffect: RuleEffect? { RuleEffect(rawValue: effect) }
}

/// The runtime's AgentView, one card per agent found on this machine.
public struct AgentStanding: Decodable, Equatable, Identifiable, Sendable {
    public let kind: String
    public let name: String
    public let status: String
    /// Where its binary sits: installed, or somewhere unusual. Never the path, which names the user.
    public let installed: String?
    /// Its MCP config file, where the hub found one.
    public let configPath: String?
    /// When a pause lifts on its own.
    public let pausedUntil: String?
    public let sessions: AgentSessions
    /// The hub's servers given to it, by name.
    public let mcpServers: [String]
    /// The Skills Hub's skills given to it, by name, whether or not they are enabled; absent from a runtime before the hub.
    public let skills: [String]?
    public let today: AgentToday
    /// The last five, newest first.
    public let recent: [AgentAction]
    /// Whether agent-launch can open it, which only an agent with a known launch command can; absent reads as no.
    public let launchable: Bool?

    public var id: String { kind }
    public var agentStatus: AgentStatus? { AgentStatus(rawValue: status) }
    /// Launch is offered only where the runtime said it can open the agent.
    public var canLaunch: Bool { launchable == true }
}

/// What agent-launch asked the Mac to type, in the folder it opens on.
public struct AgentLaunched: Decodable, Equatable, Sendable {
    public let agent: String
    public let workingDirectory: String
    /// The line typed into the new terminal.
    public let line: String

    public init(agent: String, workingDirectory: String, line: String) {
        self.agent = agent
        self.workingDirectory = workingDirectory
        self.line = line
    }
}

/// A pack Memnox ships, with its TOML to hand straight to rule-pack-import.
public struct RulePackView: Decodable, Equatable, Identifiable, Sendable {
    /// The file it ships as, without its extension, which stays the same between releases.
    public let id: String
    public let name: String
    public let description: String
    public let ruleCount: Int
    public let toml: String

    public init(id: String, name: String, description: String, ruleCount: Int, toml: String) {
        self.id = id
        self.name = name
        self.description = description
        self.ruleCount = ruleCount
        self.toml = toml
    }
}
