import XCTest
@testable import MemnoxVoiceCore

final class HomeOpenerTests: XCTestCase {
    func testSaysWorkingWaitingAndStoppedInOneSentence() {
        XCTAssertEqual(HomeOpener.line(working: 3, needsYou: 1, stoppedToday: 0),
                       "3 agents working. 1 needs you. Nothing was stopped today.")
    }

    func testAQuietDaySaysSo() {
        XCTAssertEqual(HomeOpener.line(working: 0, needsYou: 0, stoppedToday: 2),
                       "No agent is working right now. Nothing needs you. Memnox stopped 2 risky actions today.")
    }

    func testCountsEachWorkingAgentOnce() {
        let working = ["a", "a", "b"].enumerated().map { index, agent in
            TodayItem(id: "\(index)", kind: .working, title: "t", agent: agent, agentName: agent, state: .working)
        }
        let line = HomeOpener.line([(.waiting, []), (.working, working)], stoppedToday: 1)
        XCTAssertEqual(line, "2 agents working. Nothing needs you. Memnox stopped 1 risky action today.")
    }
}
