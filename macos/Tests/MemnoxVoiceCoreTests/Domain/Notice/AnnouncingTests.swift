import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Which events are said, and which keep the microphone open.
final class AnnouncingTests: XCTestCase {
    private func notice(_ kind: String) throws -> DaemonEvent {
        try event(#"{"kind":"notice","notice":"\#(kind)","subject":"ntc_1","agent":"claude-code","summary":"It happened.","at":"2026-10-01T00:00:00Z"}"#)
    }

    func testReadsEveryNoticeTheRuntimeSendsAndANewOneAsUnknown() throws {
        XCTAssertEqual(try notice("would-have").noticeKind, .wouldHave)
        XCTAssertEqual(try notice("collision").noticeKind, .collision)
        XCTAssertEqual(try notice("message").noticeKind, .message)
        XCTAssertNil(try notice("something-newer").noticeKind)
    }

    func testSaysWhatTheyAskedForOrWhatWaitsOnThemWhateverTheSetting() throws {
        for kind in ["watched", "question", "collision", "message"] {
            XCTAssertTrue(try notice(kind).isSaid(speakUp: false), kind)
        }
        for kind in ["finished", "committed", "pushed", "would-have", "ended", "together", "something-newer"] {
            XCTAssertFalse(try notice(kind).isSaid(speakUp: false), kind)
            XCTAssertTrue(try notice(kind).isSaid(speakUp: true), kind)
        }
    }

    func testSaysEverythingThatIsNotANoticeEvenWithSpeakUpOff() throws {
        let held = try event(#"{"kind":"held","subject":"apr_1","agent":"claude-code","summary":"It wants to push.","at":"2026-10-01T00:00:00Z"}"#)
        XCTAssertTrue(held.isSaid(speakUp: false))
    }

    func testKeepsListeningOnlyForWhatWaitsOnTheirAnswer() throws {
        let held = try event(#"{"kind":"held","subject":"apr_1","agent":"claude-code","summary":"It wants to push.","at":"2026-10-01T00:00:00Z"}"#)
        XCTAssertTrue(held.awaitsAnswer)
        XCTAssertTrue(try notice("question").awaitsAnswer)
        XCTAssertTrue(try notice("collision").awaitsAnswer)
        XCTAssertTrue(try notice("message").awaitsAnswer)
        // An agent stopped in its terminal on their answer, so the microphone stays open for it.
        XCTAssertTrue(try notice("asking").awaitsAnswer)
        XCTAssertFalse(try notice("watched").awaitsAnswer)
        XCTAssertFalse(try notice("finished").awaitsAnswer)
    }

    func testNothingAPhoneHoldsOrAskedForIsSaidOrListenedFor() throws {
        let held = try event(#"{"kind":"held","subject":"apr_1","agent":"claude-code","summary":"It wants to push.","at":"t","heardOn":{"deviceId":"dev_1","name":"iPhone"}}"#)
        XCTAssertTrue(held.quietOnMac)
        XCTAssertFalse(held.isSaid(speakUp: true))
        XCTAssertFalse(held.awaitsAnswer)
        let asked = try event(#"{"kind":"notice","notice":"question","subject":"ntc_1","agent":"claude-code","summary":"Which one?","at":"t","origin":{"deviceId":"dev_1"}}"#)
        XCTAssertTrue(asked.quietOnMac)
        XCTAssertFalse(asked.isSaid(speakUp: true))
        XCTAssertFalse(asked.awaitsAnswer)
    }

    func testAPhonesTurnAndTheVoiceMovingAreShownOnlyWhateverTheSetting() throws {
        let turn = try event(#"{"kind":"notice","subject":"ask_1","agent":"memnox","summary":"s","at":"t","phoneTurn":{"deviceId":"dev_1","name":"iPhone","said":"what changed"}}"#)
        let moved = try event(#"{"kind":"notice","subject":"voc_1","agent":"memnox","summary":"s","at":"t","voiceOn":{"deviceId":"dev_1","name":"iPhone","holding":true}}"#)
        for shown in [turn, moved] {
            XCTAssertTrue(shown.isShownOnly)
            XCTAssertFalse(shown.isSaid(speakUp: true))
            XCTAssertFalse(shown.awaitsAnswer)
        }
    }

    func testAnEventWithNoPhoneMarkIsUnchanged() throws {
        let held = try event(#"{"kind":"held","subject":"apr_1","agent":"claude-code","summary":"It wants to push.","at":"t"}"#)
        XCTAssertFalse(held.quietOnMac)
        XCTAssertFalse(held.isShownOnly)
        XCTAssertTrue(held.isSaid(speakUp: false))
        XCTAssertTrue(held.awaitsAnswer)
    }
}
