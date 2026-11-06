import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Mirrors shared/tauri-core/test/onboarding-steps.test.ts and the steps in onboarding-guide.test.ts.
final class FirstRunLinesTests: XCTestCase {
    private func entry(_ json: String) throws -> McpHubEntryView {
        try JSONDecoder().decode(McpHubEntryView.self, from: Data(json.utf8))
    }

    private func pack(_ id: String) -> RulePackView {
        RulePackView(id: id, name: id, description: "", ruleCount: 3, toml: "")
    }

    func testRunsThreeShortStepsCountedOnEveryOne() {
        XCTAssertEqual(FirstRunLines.steps, ["Connect", "Bring in what your agents use", "Starting rules"])
        XCTAssertEqual((0..<3).map { FirstRunLines.progressLabel(step: $0) }, ["Step 1 of 3", "Step 2 of 3", "Step 3 of 3"])
        XCTAssertEqual(FirstRunLines.progressLabel(step: 7), "Step 3 of 3")
        XCTAssertEqual(FirstRunLines.progress(step: 0, done: false), 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(FirstRunLines.progress(step: 2, done: false), 1)
        XCTAssertEqual(FirstRunLines.progress(step: 0, done: true), 1)
    }

    func testMovesOnFromConnectAsSoonAsTheServiceRuns() {
        XCTAssertTrue(FirstRunLines.canContinueConnect(serviceRunning: true))
        XCTAssertFalse(FirstRunLines.canContinueConnect(serviceRunning: false))
        XCTAssertTrue(FirstRunLines.connectWaiting.contains("by itself"))
    }

    func testRecommendsTheSafeDefaultsAndKeepsTheOtherPacksBehindIt() {
        let packs = [pack("read-only-agents"), pack("safe-defaults"), pack("no-outward-writes")]
        XCTAssertEqual(FirstRunLines.recommendedPack(packs)?.id, "safe-defaults")
        XCTAssertEqual(FirstRunLines.otherPacks(packs).map(\.id), ["read-only-agents", "no-outward-writes"])
        // A runtime that ships other packs still has one chosen for the person, its first.
        XCTAssertEqual(FirstRunLines.recommendedPack([pack("careful"), pack("open")])?.id, "careful")
        XCTAssertNil(FirstRunLines.recommendedPack([]))
        XCTAssertEqual(FirstRunLines.otherPacks([]), [])
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
        XCTAssertEqual(FirstRunLines.foundLine(found), "We found 2 tools and 1 skill across 2 agents.")
    }

    func testSaysPlainlyWhenThereIsNothingToBringIn() {
        XCTAssertEqual(FirstRunLines.foundLine(FirstRunLines.found(servers: [], skills: [])),
                       "Nothing to bring in: no agent here keeps tools or skills of its own yet.")
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
