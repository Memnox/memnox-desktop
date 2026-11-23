import XCTest

@testable import MemnoxVoiceCore

/// One agent started on a shipped pack, read back off the rules the runtime names after it.
final class AgentPresetsTests: XCTestCase {
    private let packs = [RulePackView(id: "safe-defaults", name: "Safe defaults", description: "", ruleCount: 2, toml: ""),
                         RulePackView(id: "read-only-agents", name: "Read-only agents", description: "", ruleCount: 2, toml: "")]

    private func rule(_ name: String) -> PolicyRuleView {
        PolicyRuleView(name: name, effect: "ask", match: PolicyRuleMatch(actions: ["*"]), sentence: name, source: "machine", editable: true)
    }

    func testReadsThePackAnAgentWasStartedOn() {
        let rules = [rule("pack-read-only-agents-write-ask-for-cursor"), rule("pack-safe-defaults-delete-ask")]
        XCTAssertEqual(AgentPresets.started(rules, agent: "cursor", packs: packs)?.id, "read-only-agents")
        XCTAssertNil(AgentPresets.started(rules, agent: "claude-code", packs: packs))
        XCTAssertEqual(AgentPresets.line(nil), "Follows your general rules.")
        XCTAssertEqual(AgentPresets.line(packs[1]), "Started on Read-only agents.")
    }
}
