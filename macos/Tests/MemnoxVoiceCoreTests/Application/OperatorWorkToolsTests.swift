import XCTest
@testable import MemnoxVoiceCore

/// The operator's agent work verbs by the runtime's names: starting work and answering a handoff act and are listed
/// in the side panel, and showing work is a lookup said as talk.
final class OperatorWorkToolsTests: XCTestCase {
    func testListsStartingWorkAndAnsweringAHandoffButNotALookup() {
        XCTAssertTrue(Conversation.actingTools.contains("start_agent_work"))
        XCTAssertTrue(Conversation.listedTools.contains("answer_handoff"))
        XCTAssertFalse(Conversation.listedTools.contains("show_agent_work"))
    }
}
