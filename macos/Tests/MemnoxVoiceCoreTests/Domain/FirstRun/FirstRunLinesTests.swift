import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Mirrors shared/tauri-core/test/onboarding-steps.test.ts and the steps in onboarding-guide.test.ts.
final class FirstRunLinesTests: XCTestCase {
    private func entry(_ json: String) throws -> McpHubEntryView {
        try JSONDecoder().decode(McpHubEntryView.self, from: Data(json.utf8))
    }

    func testRunsThreeStepsForAFreshMacWithWhatIsOptionalAfterThem() {
        XCTAssertEqual(FirstRunLines.steps, ["Connect your agents", "Set up your workspace", "Choose your boundaries"])
        XCTAssertEqual(FirstRunLines.progress(step: 0, optional: false), 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(FirstRunLines.progress(step: 2, optional: false), 1)
        XCTAssertEqual(FirstRunLines.progress(step: 2, optional: true), 1)
    }

    func testCountsWhatOneAgentKeepsAndLeavesARepositoryFileWhereItIs() throws {
        let servers = [
            try entry(#"{"agent":"cursor","path":"~/.cursor/mcp.json","name":"notion"}"#),
            try entry(#"{"agent":"claude-code","path":"~/.claude.json","name":"github"}"#),
            try entry(#"{"path":"/code/app/.mcp.json","name":"playwright"}"#),
        ]
        let skills = [
            FoundSkillView(id: "f1", name: "frontend-design", agent: "claude-code", kind: "skill", path: "p", tools: [], grant: "g", imported: false),
            FoundSkillView(id: "f2", name: "old", agent: "codex-cli", kind: "skill", path: "p", tools: [], grant: "g", imported: true),
        ]
        let found = FirstRunLines.found(servers: servers, skills: skills)
        XCTAssertEqual(found.servers.map(\.name), ["notion", "github"])
        XCTAssertEqual(found.skills.map(\.id), ["f1"])
        XCTAssertEqual(found.agents, 2)
        XCTAssertEqual(FirstRunLines.foundLine(found), "We found 2 MCP servers and 1 skill across 2 agents.")
    }

    func testSaysPlainlyWhenThereIsNothingToBringIn() {
        XCTAssertEqual(FirstRunLines.foundLine(FirstRunLines.found(servers: [], skills: [])),
                       "Nothing to bring in: no agent here keeps MCP servers or skills of its own yet.")
    }

    func testSaysWhatAnImportBroughtInAndWhatItLeft() {
        XCTAssertEqual(FirstRunLines.importedLine(3, failed: []), "Brought in 3, now set up once in Memnox.")
        XCTAssertEqual(FirstRunLines.importedLine(1, failed: ["notion: no such file"]),
                       "Brought in 1, now set up once in Memnox. 1 could not be, and stay where they are: notion: no such file")
    }

    func testListsAPackWithItsRuleCount() {
        XCTAssertEqual(FirstRunLines.packTitle(RulePackView(id: "careful", name: "Careful", description: "", ruleCount: 6, toml: "")), "Careful · 6 rules")
        XCTAssertEqual(FirstRunLines.packTitle(RulePackView(id: "open", name: "Open", description: "", ruleCount: 1, toml: "")), "Open · 1 rule")
    }

    func testSaysWhichAgentsStillRunOutsideMemnox() {
        XCTAssertEqual(FirstRunLines.agentsFound(count: 2, open: 1), "Found 2 agents. 1 still runs outside Memnox until you protect it.")
        XCTAssertEqual(FirstRunLines.agentsFound(count: 1, open: 0), "Found 1 agent. Every one passes your boundaries first.")
        XCTAssertEqual(FirstRunLines.agentsFound(count: 0, open: 0),
                       "No agent found yet. Install Claude Code, Codex, Cursor or another agent, then check again.")
    }
}
