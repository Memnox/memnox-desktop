import Foundation

/// Where one agent meets the others, said on its card in plain words: the files it holds so nobody changes them under
/// it, the files it is in with another agent right now, and the writes it was held back from because another had them.
public enum AgentMeetings {
    public static let title = "Working alongside others"

    /// One line each, the shared files first since they are the ones a person may need to settle.
    public static func lines(_ view: AgentOverlapsView, agent: String, name: (String) -> String) -> [String] {
        let together = view.together.filter { $0.agents.contains(agent) }.map { each -> String in
            let others = each.agents.filter { $0 != agent }.map(name)
            return "In \(file(each.target)) with \(listed(others)) right now."
        }
        let holds = view.holds.filter { $0.agent == agent }.map { "Holds \(file($0.path)), so no other agent changes it." }
        let held = view.heldBack.filter { $0.agent == agent }.map { "Waited for \(file($0.what)), which another agent had." }
        return together + holds + held
    }

    /// The last part of a path, which is how a person knows the file; anything else as it was said.
    static func file(_ path: String) -> String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        return trimmed.split(separator: "/").last.map(String.init) ?? path
    }

    private static func listed(_ names: [String]) -> String {
        switch names.count {
        case 0: return "another agent"
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
        }
    }
}
