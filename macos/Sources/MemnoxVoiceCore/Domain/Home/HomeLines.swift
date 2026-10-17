import Foundation

/// The home's blocks in plain words, built only from the daemon's counts and names, so the window never says more
/// than the record does and never puts a score where a count belongs.
public enum HomeLines {
    /// "41 actions, 6 asked you, 5 allowed, 1 refused", or a quiet line before anything ran today.
    public static func today(_ today: HomeToday) -> String {
        guard today.actions + today.asked + today.allowed + today.refused > 0 else { return "Nothing has run today." }
        return [
            counted(today.actions, "action", "actions"),
            "\(today.asked) asked you",
            "\(today.allowed) allowed",
            "\(today.refused) refused",
        ].joined(separator: ", ")
    }

    /// What waits on the person, said as a count.
    public static func waiting(_ count: Int) -> String {
        switch count {
        case 0: return "Nothing waits on you."
        case 1: return "1 call waits on you."
        default: return "\(count) calls wait on you."
        }
    }

    /// The question on the ready card, naming the agent only when every yes came from one.
    public static func ready(_ ready: HomeReady) -> String {
        let agent = ready.agentName.map { ", for \($0)" } ?? ""
        return "You have said yes to \(ready.action) \(times(ready.approvals))\(agent). Let it run on its own?"
    }

    /// What nothing covers, one line per count that is not zero, or one line saying everything is covered.
    public static func notCovered(_ notCovered: HomeNotCovered) -> [String] {
        var lines: [String] = []
        if notCovered.unprotected > 0 {
            lines.append(notCovered.unprotected == 1
                ? "1 agent here runs outside Memnox."
                : "\(notCovered.unprotected) agents here run outside Memnox.")
        }
        if notCovered.dormant > 0 {
            lines.append(notCovered.dormant == 1
                ? "1 agent has been quiet for a month and still holds its reach."
                : "\(notCovered.dormant) agents have been quiet for a month and still hold their reach.")
        }
        return lines.isEmpty ? ["Every agent here is under Memnox."] : lines
    }

    /// A working session's line under its agent's name: its task and where, whichever of them it has.
    public static func working(_ working: HomeWorking) -> String {
        switch (working.task, working.repository) {
        case let (task?, repository?): return "\(task) in \(repository)"
        case let (task?, nil): return task
        case let (nil, repository?): return "Working in \(repository)"
        case (nil, nil): return "Working"
        }
    }

    private static func times(_ count: Int) -> String {
        switch count {
        case 1: return "once"
        case 2: return "twice"
        default: return "\(count) times"
        }
    }

    private static func counted(_ count: Int, _ one: String, _ many: String) -> String {
        "\(count) \(count == 1 ? one : many)"
    }
}
