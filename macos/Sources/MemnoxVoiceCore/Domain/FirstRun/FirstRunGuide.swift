import Foundation

/// The pages the first run walks through, as the guide speaks them.
public enum FirstRunPage: Int, CaseIterable, Sendable {
    case connect
    case workspace
    case boundaries
    case optional
}

/// Everything the spoken guide says from the first step until setup is finished and the scan after it, written to be heard: short
/// sentences, one idea each, and only what Memnox does today. Each page's lines are said in order the first time it
/// opens; the lines that follow what was found are said once the runtime has answered.
public enum FirstRunGuide {
    /// Said over the opening, with the same words it shows.
    public static let askName = "Welcome to Memnox. I'm the voice over your agents. So, what should I call you?"

    /// The greeting at the first step, with the person's name when they gave one.
    public static func welcome(name: String) -> String {
        "Hi\(greeting(name)), I'm Memnox. I live in your notch and watch over your AI agents, so they can work on their own inside the boundaries you set."
    }

    /// What each page says when it first opens, in the order it is said.
    public static func lines(_ page: FirstRunPage) -> [String] {
        switch page {
        case .connect: return connect
        case .workspace: return workspace
        case .boundaries: return boundaries
        case .optional: return optional
        }
    }

    /// Said on the second step once the agents' own servers and skills are counted, so the person hears how many.
    public static func found(_ found: FoundToImport) -> String {
        if found.isEmpty { return "None of your agents keeps skills or MCP servers of its own yet, so there is nothing to bring in. Press Continue." }
        return "\(FirstRunLines.foundLine(found)) They are grouped by agent. Search the list, or untick any you want to leave where they are."
    }

    /// Said once Import has run, so the person knows what changed before moving on.
    public static func imported(_ count: Int) -> String {
        "Done. \(counted(count, "item is", "items are")) now kept once in Memnox, and shared with the agents you choose. Press Continue."
    }

    /// Said once a pack is chosen, while its rules wait on the island.
    public static let packProposed = "Your rules are waiting on the island at the top of your screen. Confirm each one with Touch ID, then press Finish."

    /// Said over the full screen scan once setup closes, with what it counted, before the person opens Memnox.
    public static func scanned(_ tally: ScanTally) -> [String] {
        [
            "Now I am scanning this Mac for your agents, their skills, MCP servers, memory sources and connected apps.",
            "Your memory stays local. Instruction files and notes are linked where they are, and read only on this Mac.",
            ScanLines.summary(tally),
            "From now on, everything your agents do is kept in the activity record, with the rule that decided it.",
            "Press Escape or click to close, and Memnox opens on Home, where your next steps wait.",
        ]
    }

    private static let connect = [
        "Setup has three steps, then a few optional extras. I will talk you through each one.",
        "Step one connects your agents. I install the Memnox service in your home folder, and keep it running and up to date.",
        "Then I put myself under the agents I find, like Claude Code, Codex and Cursor. Everything they do passes your rules first.",
        "From you I need one thing now: Touch ID. Your approval signs what agents ask, and the key never leaves this Mac.",
        "Once your agents show a tick, press Continue.",
    ]

    private static let workspace = [
        "Step two sets up your workspace.",
        "Your agents already keep skills and MCP servers of their own, each in its own folder.",
        "Bring them into Memnox once, and every agent you choose can share them.",
        "A server brought in runs behind Memnox, so every call it makes is ruled on and recorded.",
    ]

    private static let boundaries = [
        "Step three chooses your boundaries.",
        "Every action an agent takes meets a rule: allow, ask or deny.",
        "Allow runs on its own. Ask stops and waits for you on the notch island. Deny never runs.",
        "Pick a pack of rules to start from. Nothing holds until you confirm each rule with Touch ID on the island.",
        "You can change any rule later, under Governance.",
    ]

    private static let optional = [
        "That is the three steps done. Your agents now work inside your boundaries.",
        "The rest is optional, and waits in Settings.",
        "Allow the microphone, and talk to your agents from anywhere. Press Option Space, ask, and let go.",
        "Memnox can also act in your apps for you, like Gmail, Slack and GitHub, through connectors. Nothing goes out until you approve it.",
        "Pair your iPhone to answer your agents when you are away from this Mac.",
        "When you are ready, press Start using Memnox, and I will scan this Mac.",
    ]

    private static func greeting(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "" : " \(trimmed)"
    }

    private static func counted(_ count: Int, _ one: String, _ many: String) -> String {
        count == 1 ? "1 \(one)" : "\(count) \(many)"
    }
}
