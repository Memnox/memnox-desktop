import Foundation

/// Starting one agent on a shipped rule pack, so a reviewer and a builder on the same computer are careful in different
/// ways. The runtime names each rule it starts for an agent after it, which is how the pack it started on is read back.
public enum AgentPresets {
    public static let title = "Start it on"
    public static let waits = "Each rule waits for your signature on the island."

    /// The pack this agent was started on, by id, or nil where none was; the last one in the list wins.
    public static func started(_ rules: [PolicyRuleView], agent: String, packs: [RulePackView]) -> RulePackView? {
        let mine = rules.map(\.name).filter { $0.hasSuffix("-for-\(agent)") }
        return packs.last { pack in mine.contains { $0.hasPrefix("pack-\(pack.id)-") } }
    }

    /// The line under the presets: what it was started on, or that it follows the general rules.
    public static func line(_ started: RulePackView?) -> String {
        guard let started else { return "Follows your general rules." }
        return "Started on \(started.name)."
    }
}
