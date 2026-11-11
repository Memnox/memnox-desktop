import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// What a session shows at a glance.
final class SessionStatusTests: XCTestCase {
    func testAPauseOrAQuestionOutranksWhateverTheSessionIsDoing() {
        XCTAssertEqual(SessionStatus(state: .working, thinking: true, paused: true).label, "Stopped")
        XCTAssertEqual(SessionStatus(state: .paused, thinking: true).label, "Stopped")
        XCTAssertEqual(SessionStatus(state: .working, thinking: true, waitingOnYou: 1).label, "Needs you")
        XCTAssertEqual(SessionStatus(state: .open, thinking: true).label, "Working")
    }

    func testNamesEachStateTheWayAPersonSaysIt() {
        XCTAssertEqual(SessionStatus(state: .working, thinking: false).label, "Working")
        XCTAssertEqual(SessionStatus(state: .open, thinking: false).label, "Finished")
        XCTAssertEqual(SessionStatus(state: .ended, thinking: false).label, "Idle")
        XCTAssertEqual(SessionStatus(state: .idle, thinking: false).label, "Idle")
        XCTAssertEqual(SessionStatus(state: nil, thinking: false).label, "Idle")
    }

    func testACardAndTheLiveWindowReadTheSameState() {
        let card = SessionCard(sessionId: "ses_1", agentName: "Codex", state: "working")
        XCTAssertEqual(card.sessionState, .working)
        XCTAssertEqual(card.status, .working)
        XCTAssertTrue(card.status.isActive)
        XCTAssertNil(SessionCard(sessionId: "ses_2", agentName: "Codex", state: "something-newer").sessionState)
    }
}
