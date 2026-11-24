import XCTest

@testable import MemnoxVoiceCore

/// Getting started on Home: three steps at most, worded for somebody who has never opened a terminal.
final class HomeStepsTests: XCTestCase {
    func testStartsNotSetUpWithConnectingTheAgentsAsTheNextStep() {
        var standing = HomeStanding()
        standing.agents = 2
        let setup = HomeSteps.setup(standing)
        XCTAssertEqual(setup.stage, .ungoverned)
        XCTAssertEqual(setup.stage.label, "Not set up yet")
        XCTAssertEqual(setup.next?.id, .protectAgents)
        XCTAssertTrue(setup.waiting.isEmpty)
        XCTAssertEqual(HomeSteps.progress(setup), "1 of 3 done")
        XCTAssertTrue(setup.standing.isEmpty)
    }

    func testNeverAsksMoreThanThreeThings() {
        XCTAssertEqual(HomeSteps.setup(HomeStanding()).total, 3)
        XCTAssertEqual(HomeStepID.allCases.count, 3)
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
        XCTAssertEqual(setup.stage.label, "Watching only")
        XCTAssertEqual(setup.next?.id, .answerAway)
        XCTAssertEqual(setup.completed, 2)
        XCTAssertEqual(setup.standing.map(\.label), ["Agents protected", "Rules in force", "Actions recorded"])
    }

    func testIsDoneOnceEveryStepIsDoneAndSaysProtecting() {
        var standing = HomeStanding()
        standing.agents = 1
        standing.agentsProtected = 1
        standing.phonesPaired = 1
        standing.mode = .enforce
        let setup = HomeSteps.setup(standing)
        XCTAssertEqual(setup.stage, .enforcing)
        XCTAssertEqual(HomeMode.enforce.badge, "Protecting")
        XCTAssertTrue(setup.climbed)
        XCTAssertEqual(HomeSteps.progress(setup), "3 of 3 done")
    }

    func testAMacWithNoAgentHasNotConnectedAny() {
        XCTAssertFalse(HomeSteps.setup(HomeStanding()).steps.first { $0.id == .protectAgents }?.done ?? true)
    }

    func testAsksHowCarefulToBeUntilSetupOrARuleSaysIt() {
        var standing = HomeStanding()
        standing.setupFinished = false
        standing.agents = 1
        standing.agentsProtected = 1
        let setup = HomeSteps.setup(standing)
        XCTAssertEqual(setup.next?.id, .chooseCare)
        XCTAssertEqual(HomeSteps.cardTitle, "Get set up")
    }
}
