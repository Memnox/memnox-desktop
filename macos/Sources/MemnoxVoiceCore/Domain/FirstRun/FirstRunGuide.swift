import Foundation

/// The pages the first run walks through, as the guide speaks them.
public enum FirstRunPage: Int, CaseIterable, Sendable {
    case connect
    case rules
    /// The end, once the steps are done.
    case ready
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
        case .rules: return rules
        case .ready: return ready
        }
    }

    /// Said once a pack is chosen, while its rules wait on the island.
    public static let packProposed = "Your starting rules are waiting on the island at the top of your screen. Confirm each one with Touch ID."

    /// Said over the full screen scan once setup closes, with what it counted, before the person opens Memnox.
    public static func scanned(_ tally: ScanTally) -> [String] {
        [
            "Now I am scanning this Mac for your agents, their skills, tools, memory sources and connected apps.",
            "Your memory stays local. Instruction files and notes are linked where they are, and read only on this Mac.",
            ScanLines.summary(tally),
            "From now on, everything your agents do is kept in the activity record, with the rule that decided it.",
            "Press Escape or click to close, and Memnox opens on Home, where your next steps wait.",
        ]
    }

    private static let connect = [
        "Setup takes two short steps, and I will talk you through both.",
        "First I connect this Mac. The Memnox service installs and starts by itself, and keeps itself up to date.",
        "I put myself under the agents I find, like Claude Code, Codex and Cursor, so everything they do passes your rules first.",
        "Touch ID signs what you approve, and the key never leaves this Mac.",
        "Press Continue as soon as the service shows a tick.",
    ]

    private static let rules = [
        "Last, your starting rules.",
        "Every action an agent takes meets a rule: allow, ask or deny. Ask waits for you on the notch island.",
        "I chose the pack I recommend. Press Finish, and confirm its rules with Touch ID on the island.",
        "You can change any rule later, under Rules.",
    ]

    private static let ready = [
        "That is setup done. Paste the prompt on screen into your agent, and I will ask you before the delete runs.",
        "Below it is what I can and cannot do for each of your agents, in plain words.",
        "Memnox can also act in your apps, like Gmail, Slack and GitHub, through connectors. Nothing goes out until you approve it.",
        "You can pair your iPhone or sign in to Memnox Cloud later, from Home and Settings, once Memnox opens.",
    ]

    private static func greeting(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "" : " \(trimmed)"
    }
}
