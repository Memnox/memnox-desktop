import Foundation

/// The five onboarding steps, the same ids and words on the console, this Mac, Windows and Linux, from the
/// contract's `onboarding` list in `shared/ux/contract.json`.
public enum FirstRunStepID: String, CaseIterable, Sendable {
    case who
    case agents
    case connect
    case askWhere = "ask-where"
    case rules

    /// The step's question, heading its page.
    public var title: String {
        switch self {
        case .who: "Who is Memnox for?"
        case .agents: "Which agents do you run?"
        case .connect: "Connect this machine"
        case .askWhere: "Where should Memnox ask you?"
        case .rules: "Your starting rules"
        }
    }

    /// The step's name under the progress bar, short enough for five side by side.
    public var label: String {
        switch self {
        case .who: "Who it is for"
        case .agents: "Your agents"
        case .connect: "This Mac"
        case .askWhere: "Where you are asked"
        case .rules: "Starting rules"
        }
    }
}

/// Who Memnox is for, the first question, which only picks what is suggested next: where Memnox asks first.
public enum FirstRunAudience: String, CaseIterable, Identifiable, Sendable {
    case me
    case away
    case team

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .me: "Just me"
        case .away: "Just me, with agents working while I'm away"
        case .team: "A team"
        }
    }

    public var detail: String {
        switch self {
        case .me: "My agents on this Mac, answered here."
        case .away: "Agents that keep going when I step out, answered from my phone."
        case .team: "Agents across people and machines, under the same rules."
        }
    }

    /// Where asking suggests itself first: here, the phone, or Memnox Cloud where a team answers.
    public var suggested: FirstRunAskRoute {
        switch self {
        case .me: .here
        case .away: .phone
        case .team: .cloud
        }
    }
}

/// The places Memnox asks a person, each one more way in beside Touch ID on this Mac, which is always on.
public enum FirstRunAskRoute: String, CaseIterable, Sendable {
    case here
    case phone
    case cloud

    public var title: String {
        switch self {
        case .here: "Touch ID on this Mac"
        case .phone: "Your iPhone"
        case .cloud: "Memnox Cloud, in the browser or chat"
        }
    }

    public var detail: String {
        switch self {
        case .here: "Always on. The island asks, and your finger signs the yes."
        case .phone: "Pair it with a code here, and answer with Face ID wherever you are."
        case .cloud: "Sign in, and a question reaches you in the browser or chat your workspace uses."
        }
    }
}

/// The first run's short steps and what each says, with the safe defaults already chosen so a press of Continue
/// is always the sensible answer. Counts, never a score.
public enum FirstRunLines {
    /// The steps by name, as the stepper shows them, in the contract's order.
    public static let steps = FirstRunStepID.allCases.map(\.label)

    /// What the end offers to paste into an agent, so the first ask arrives in minutes; the contract's `tryPrompt`.
    public static let tryPrompt = "Make a folder called memnox-try, then delete it with rm -rf memnox-try."
    public static let tryTitle = "Try it with your agent"
    public static let tryDetail = "Paste this into Claude Code, Codex or Cursor. Memnox asks you before the delete runs."

    /// "Step 2 of 5", over every step, so a new person always knows how much is left.
    public static func progressLabel(step: Int) -> String {
        "Step \(min(max(step, 0), steps.count - 1) + 1) of \(steps.count)"
    }

    /// How far the bar is filled, one step's share at a time, and whole once the steps are done.
    public static func progress(step: Int, done: Bool) -> Double {
        if done { return 1 }
        return Double(step + 1) / Double(steps.count)
    }

    /// The first step moves on as soon as the service runs, since everything after it reads through the service and
    /// the key and the agents finish on their own behind it.
    public static func canContinueConnect(serviceRunning: Bool) -> Bool { serviceRunning }

    /// Said under Continue while the service is still on its way, so the person knows they need do nothing.
    public static let connectWaiting = "Continue opens once the Memnox service is running. It installs and starts by itself."

    /// The pack a new Mac starts under, the one Memnox ships as its safe defaults.
    public static let recommendedPackId = "safe-defaults"

    /// The pack offered first and already chosen: the safe defaults when the runtime ships them, otherwise its first.
    public static func recommendedPack(_ packs: [RulePackView]) -> RulePackView? {
        packs.first { $0.id == recommendedPackId } ?? packs.first
    }

    /// Every other pack, behind See other packs, in the runtime's order.
    public static func otherPacks(_ packs: [RulePackView]) -> [RulePackView] {
        let recommended = recommendedPack(packs)?.id
        return packs.filter { $0.id != recommended }
    }

    /// "Careful · 6 rules", as a pack is listed to choose from.
    public static func packTitle(_ pack: RulePackView) -> String {
        "\(pack.name) · \(counted(pack.ruleCount, "rule", "rules"))"
    }

    /// The agents found on this Mac, in a line, the unprotected ones said so.
    public static func agentsFound(_ agents: [AgentStanding]) -> String {
        agentsFound(count: agents.count, open: agents.filter { $0.agentStatus == .unprotected }.count)
    }

    public static func agentsFound(count: Int, open: Int) -> String {
        if count == 0 { return "No agent found yet. Install Claude Code, Codex, Cursor or another agent, then check again." }
        let found = "Found \(counted(count, "agent", "agents"))."
        return open == 0 ? "\(found) Every one passes your boundaries first." : "\(found) \(counted(open, "still runs", "still run")) outside Memnox until you protect it."
    }

    /// What one agent's row says under its name in the first step.
    public static func agentDetail(_ agent: AgentStanding) -> String {
        switch agent.agentStatus {
        case .unprotected: return "Runs outside Memnox until you protect it."
        case .paused: return "Paused. Nothing it asks for runs."
        default: return "Every action passes your boundaries first."
        }
    }

    private static func counted(_ count: Int, _ one: String, _ many: String) -> String {
        count == 1 ? "1 \(one)" : "\(count) \(many)"
    }
}
