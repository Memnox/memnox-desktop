import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// The home said in plain words, from counts and names alone.
final class HomeLinesTests: XCTestCase {
    func testSaysTodayAsFourCounts() {
        XCTAssertEqual(HomeLines.today(HomeToday(actions: 41, asked: 6, allowed: 5, refused: 1)),
                       "41 actions, 6 asked you, 5 allowed, 1 refused")
        XCTAssertEqual(HomeLines.today(HomeToday(actions: 1, asked: 0, allowed: 0, refused: 0)),
                       "1 action, 0 asked you, 0 allowed, 0 refused")
        XCTAssertEqual(HomeLines.today(HomeToday(actions: 0, asked: 0, allowed: 0, refused: 0)), "Nothing has run today.")
    }

    func testAsksAboutTheReadyActionNamingTheAgentOnlyWhenThereIsOne() {
        let one = HomeReady(action: "git.push", approvals: 14, agentName: "Claude Code", targets: ["feature/*"], because: "b")
        XCTAssertEqual(HomeLines.ready(one), "You have said yes to git.push 14 times, for Claude Code. Let it run on its own?")
        let many = HomeReady(action: "npm.install", approvals: 2, because: "b")
        XCTAssertEqual(HomeLines.ready(many), "You have said yes to npm.install twice. Let it run on its own?")
    }

    func testCountsWhatWaits() {
        XCTAssertEqual(HomeLines.waiting(0), "Nothing waits on you.")
        XCTAssertEqual(HomeLines.waiting(1), "1 call waits on you.")
        XCTAssertEqual(HomeLines.waiting(3), "3 calls wait on you.")
    }

    func testSaysWhatNothingCoversOrThatEverythingIsCovered() {
        XCTAssertEqual(HomeLines.notCovered(HomeNotCovered(unprotected: 0, dormant: 0)), ["Every agent here is under Memnox."])
        XCTAssertEqual(HomeLines.notCovered(HomeNotCovered(unprotected: 2, dormant: 1)), [
            "2 agents here run outside Memnox.",
            "1 agent has been quiet for a month and still holds its reach.",
        ])
    }

    func testSaysAWorkingSessionWithWhateverItHas() {
        XCTAssertEqual(HomeLines.working(HomeWorking(sessionId: "s", agent: "a", agentName: "A", task: "fix it", repository: "shop")), "fix it in shop")
        XCTAssertEqual(HomeLines.working(HomeWorking(sessionId: "s", agent: "a", agentName: "A", repository: "shop")), "Working in shop")
        XCTAssertEqual(HomeLines.working(HomeWorking(sessionId: "s", agent: "a", agentName: "A")), "Working")
    }

    func testNoLineCarriesADash() {
        let lines = [
            HomeLines.today(HomeToday(actions: 3, asked: 1, allowed: 1, refused: 0)),
            HomeLines.ready(HomeReady(action: "x", approvals: 3, agentName: "A", because: "b")),
            HomeLines.waiting(2),
        ] + HomeLines.notCovered(HomeNotCovered(unprotected: 1, dormant: 2))
        for line in lines {
            XCTAssertFalse(line.contains("\u{2014}") || line.contains("\u{2013}") || line.contains(" - "), line)
        }
    }
}
