import XCTest

@testable import MemnoxVoiceCore

/// Reading the answer that came first out of the daemon's reply to a second one.
final class EarlierAnswerTests: XCTestCase {
    func testReadsTheFirstAnswerToAHeldCall() {
        let first = EarlierAnswer(ok: true, outcome: "already answered deny", error: nil)
        XCTAssertEqual(first?.word, "deny")
        XCTAssertEqual(first?.line, "That was already answered elsewhere: it was denied.")
    }

    func testReadsTheFirstAnswerToAProposal() {
        let first = EarlierAnswer(ok: true, outcome: "already declined", error: nil)
        XCTAssertEqual(first?.word, "declined")
        XCTAssertTrue(first?.matches("declined") == true)
        XCTAssertFalse(first?.matches("confirmed") == true)
    }

    func testKnowsItWasAnsweredWithoutKnowingHow() {
        XCTAssertEqual(EarlierAnswer(ok: true, outcome: "already answered ", error: nil)?.word, nil)
        XCTAssertEqual(EarlierAnswer(ok: true, outcome: "already answered", error: nil)?.word, nil)
        let gone = EarlierAnswer(ok: false, outcome: nil, error: "pnd_4 is no longer held")
        XCTAssertNotNil(gone)
        XCTAssertEqual(gone?.line, "That was settled before your answer arrived, so nothing changed.")
    }

    func testAnAnswerThatCountedHadNoneBeforeIt() {
        XCTAssertNil(EarlierAnswer(ok: true, outcome: "once", error: nil))
        XCTAssertNil(EarlierAnswer(ok: true, outcome: "started", error: nil))
        XCTAssertNil(EarlierAnswer(ok: false, outcome: nil, error: "prp_9 has expired"))
        XCTAssertNil(EarlierAnswer(nil))
    }
}
