import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// The two steps this Mac asks before Memnox opens; the contract's other questions are answered from Home.
final class FirstRunLinesTests: XCTestCase {
    private func pack(_ id: String) -> RulePackView {
        RulePackView(id: id, name: id, description: "", ruleCount: 3, toml: "")
    }

    func testRunsTwoShortStepsCountedOnBoth() {
        XCTAssertEqual(FirstRunLines.steps, ["This Mac", "Starting rules"])
        XCTAssertEqual(FirstRunStepID.allCases.map(\.rawValue), ["connect", "rules"])
        XCTAssertEqual(FirstRunStepID.allCases.map(\.title), ["Connect this machine", "Your starting rules"])
        XCTAssertEqual((0..<2).map { FirstRunLines.progressLabel(step: $0) }, ["Step 1 of 2", "Step 2 of 2"])
        XCTAssertEqual(FirstRunLines.progressLabel(step: 7), "Step 2 of 2")
        XCTAssertEqual(FirstRunLines.progress(step: 0, done: false), 1.0 / 2.0, accuracy: 0.0001)
        XCTAssertEqual(FirstRunLines.progress(step: 1, done: false), 1)
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
