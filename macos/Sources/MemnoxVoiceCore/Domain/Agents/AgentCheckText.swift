import Foundation

/// How setup words one agent's check on its row. The daemon's reason is written to be spoken whole, with the
/// agent's own reply inside it, so the row says it shorter and quotes the reply on a line of its own.
public enum AgentCheckText {
    /// The line under the agent's name.
    public static func status(_ agent: VoiceAgentStatus, checking: Bool) -> String {
        guard let works = agent.works else { return checking ? "Asking it one question" : "Not asked yet" }
        if works {
            guard agent.chosen else { return "Ready to answer" }
            return agent.sealed ? "Answers when you talk, kept to reading" : "Answers when you talk, and can run shell commands"
        }
        if reply(agent) != nil { return "Its own account answered in place of Memnox" }
        return sentence(agent.because) ?? "Did not answer"
    }

    /// The agent's own words worth quoting, such as a plan asking to be upgraded.
    public static func reply(_ agent: VoiceAgentStatus) -> String? {
        guard agent.works == false else { return nil }
        let words = agent.reply?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return words.isEmpty ? nil : words
    }

    /// Asked and could not answer, which is what sets a row apart from the ones that can.
    public static func notReady(_ agent: VoiceAgentStatus) -> Bool { agent.installed && agent.works == false }

    /// Names read as a sentence says them: one alone, two joined by and, more with commas before the and.
    public static func names(_ labels: [String]) -> String {
        guard let last = labels.last else { return "" }
        return labels.count == 1 ? last : labels.dropLast().joined(separator: ", ") + " and " + last
    }

    /// Starts with a capital, since the daemon writes its reasons to follow a name in a spoken sentence.
    static func sentence(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), let first = text.first else { return nil }
        return first.uppercased() + text.dropFirst()
    }
}
