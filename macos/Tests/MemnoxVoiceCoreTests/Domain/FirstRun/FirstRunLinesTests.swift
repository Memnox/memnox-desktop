import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Mirrors shared/tauri-core/test/onboarding-steps.test.ts and the steps in onboarding-guide.test.ts.
final class FirstRunLinesTests: XCTestCase {
    private func pack(_ id: String) -> RulePackView {
        RulePackView(id: id, name: id, description: "", ruleCount: 3, toml: "")
    }

    func testRunsFiveShortStepsCountedOnEveryOne() {
        XCTAssertEqual(FirstRunLines.steps, ["Who it is for", "Your agents", "This Mac", "Where you are asked", "Starting rules"])
        XCTAssertEqual(FirstRunStepID.allCases.map(\.rawValue), ["who", "agents", "connect", "ask-where", "rules"])
        XCTAssertEqual((0..<5).map { FirstRunLines.progressLabel(step: $0) },
                       ["Step 1 of 5", "Step 2 of 5", "Step 3 of 5", "Step 4 of 5", "Step 5 of 5"])
        XCTAssertEqual(FirstRunLines.progressLabel(step: 7), "Step 5 of 5")
        XCTAssertEqual(FirstRunLines.progress(step: 0, done: false), 1.0 / 5.0, accuracy: 0.0001)
        XCTAssertEqual(FirstRunLines.progress(step: 4, done: false), 1)
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

    func testSuggestsAskingWhereWhoItIsForPointsFirst() {
        XCTAssertEqual(FirstRunAudience.allCases.map(\.suggested), [.here, .phone, .cloud])
        XCTAssertEqual(FirstRunAudience.away.title, "Just me, with agents working while I'm away")
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
