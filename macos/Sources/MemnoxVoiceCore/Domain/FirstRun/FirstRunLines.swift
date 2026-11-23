import Foundation

/// The two steps the first run asks of a person, the only ones that cannot wait: their agents connected, and how
/// careful Memnox is with them. The contract's `onboarding` list in `shared/ux/contract.json` names them `agents` and
/// `careful`; who Memnox is for and where it asks are answered from Home once Memnox opens.
public enum FirstRunStepID: String, CaseIterable, Sendable {
    case connect
    case rules

    /// The step's question, heading its page.
    public var title: String {
        switch self {
        case .connect: "Your agents"
        case .rules: "How careful should Memnox be?"
        }
    }

    /// The step's name in the stepper.
    public var label: String {
        switch self {
        case .connect: "Your agents"
        case .rules: "How careful"
        }
    }
}

/// How careful Memnox is with the agents, chosen once in the first run and changed any time under Rules. Each names
/// the mode it leaves this Mac in and the shipped pack it proposes, as the contract's `careful` says.
public enum CareLevel: String, CaseIterable, Sendable {
    case watch
    case ask
    case strict

    public var label: String {
        switch self {
        case .watch: "Just watch"
        case .ask: "Ask me before risky things"
        case .strict: "Ask me about almost everything"
        }
    }

    public var line: String {
        switch self {
        case .watch: "Memnox writes down what your agents do and stops nothing."
        case .ask: "Agents work freely and wait for you before they delete, publish or change somebody else's system."
        case .strict: "Agents read and explain freely and wait for you before they change anything."
        }
    }

    /// Whether this Mac stops what a rule holds rather than only writing it down.
    public var enforces: Bool { self != .watch }

    /// The shipped pack whose rules it proposes, each signed on its own; nil proposes nothing.
    public var packId: String? {
        switch self {
        case .watch: nil
        case .ask: "safe-defaults"
        case .strict: "read-only-agents"
        }
    }

    /// The one already chosen, so a press of Finish is always the sensible answer.
    public static let recommended = CareLevel.ask
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

    /// "Step 1 of 2", over every step, so a new person always knows how much is left.
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
