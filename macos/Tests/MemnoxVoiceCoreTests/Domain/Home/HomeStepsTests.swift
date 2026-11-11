import XCTest

@testable import MemnoxVoiceCore

/// Mirrors the cloud console's ladder in memnox-cloud's onboarding.ts: a stage, the next rung, waits and two tracks.
final class HomeStepsTests: XCTestCase {
    func testStartsUngovernedWithProtectingTheAgentsAsTheNextRung() {
        var standing = HomeStanding()
        standing.agents = 2
        let setup = HomeSteps.setup(standing)
        XCTAssertEqual(setup.stage, .ungoverned)
        XCTAssertEqual(setup.next?.id, .protectAgents)
        XCTAssertEqual(setup.waiting.map(\.id), [.actionsRecorded])
        XCTAssertEqual(HomeSteps.progress(setup), "1 of 9 done")
        XCTAssertTrue(setup.standing.isEmpty)
        XCTAssertFalse(setup.rest(of: .mac).contains { $0.id == .protectAgents || $0.id == .actionsRecorded })
        XCTAssertEqual(setup.rest(of: .work).count, 3)
    }

    func testMovesOnAsCountsArriveAndListsOnlyTheCountsWon() {
        var standing = HomeStanding()
        standing.agents = 2
        standing.agentsProtected = 2
        standing.rulesInForce = 6
        standing.actionsRecorded = 14
        standing.mode = .observe
        let setup = HomeSteps.setup(standing)
        XCTAssertEqual(setup.stage, .observing)
        XCTAssertEqual(setup.next?.id, .answerAway)
        XCTAssertTrue(setup.waiting.isEmpty)
        XCTAssertEqual(setup.completed, 4)
        XCTAssertEqual(setup.standing.map(\.label), ["Agents protected", "Rules in force", "Actions recorded"])
    }

    func testIsClimbedOnceEveryStepIsDone() {
        var standing = HomeStanding()
        standing.agents = 1
        standing.agentsProtected = 1
        standing.rulesInForce = 1
        standing.actionsRecorded = 1
        standing.phonesPaired = 1
        standing.mode = .enforce
        standing.appsConnected = 1
        standing.sourcesLinked = 1
        standing.skillsShared = 1
        let setup = HomeSteps.setup(standing)
        XCTAssertEqual(setup.stage, .enforcing)
        XCTAssertTrue(setup.climbed)
        XCTAssertEqual(HomeSteps.progress(setup), "9 of 9 done")
    }

    func testAMacWithNoAgentHasNotPutAnyUnderMemnox() {
        XCTAssertFalse(HomeSteps.setup(HomeStanding()).steps.first { $0.id == .protectAgents }?.done ?? true)
    }

    func testAsksToFinishSetupFirstUntilItIsDone() {
        var standing = HomeStanding()
        standing.setupFinished = false
        let setup = HomeSteps.setup(standing)
        XCTAssertEqual(setup.next?.id, .finishSetup)
        XCTAssertEqual(HomeSteps.progress(setup), "0 of 9 done")
        XCTAssertEqual(HomeSteps.cardTitle, "Do this next")
    }
}
