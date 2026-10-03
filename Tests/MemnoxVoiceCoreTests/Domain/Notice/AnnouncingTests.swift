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
        XCTAssertNil(try notice("something-newer").noticeKind)
    }

    func testSaysWhatTheyAskedForOrWhatWaitsOnThemWhateverTheSetting() throws {
        for kind in ["watched", "question", "collision"] {
            XCTAssertTrue(try notice(kind).isSaid(speakUp: false), kind)
        }
        for kind in ["finished", "committed", "pushed", "would-have", "ended", "something-newer"] {
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
        XCTAssertFalse(try notice("watched").awaitsAnswer)
        XCTAssertFalse(try notice("finished").awaitsAnswer)
    }
}
