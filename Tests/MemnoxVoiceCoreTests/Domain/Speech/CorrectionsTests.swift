import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Finding the words a person fixed in a message the app typed for them.
final class CorrectionsTests: XCTestCase {
    func testFindsAWordSwappedForOneThatSoundsAlike() {
        XCTAssertEqual(
            correctedWords(typed: "Is any of these surgeons working?", sent: "Is any of these sessions working?"),
            [WordCorrection(heard: "surgeons", meant: "sessions")]
        )
        XCTAssertEqual(
            correctedWords(typed: "tell closed code to push", sent: "tell Claude Code to push"),
            [WordCorrection(heard: "closed", meant: "Claude")]
        )
    }

    func testLearnsNothingFromARewriteAnAdditionOrACaseFix() {
        XCTAssertEqual(correctedWords(typed: "add a cancel button", sent: "remove the whole checkout page please"), [])
        XCTAssertEqual(correctedWords(typed: "add a cancel button", sent: "add a cancel button and a test"), [])
        XCTAssertEqual(correctedWords(typed: "push to main", sent: "Push to main."), [])
    }

    func testLearnsNothingFromAWordSwappedForOneThatSoundsNothingAlike() {
        XCTAssertEqual(correctedWords(typed: "run the unit tests now", sent: "run the integration tests now"), [])
    }

    func testLearnsNothingFromWordsTooShortToBeAName() {
        XCTAssertEqual(correctedWords(typed: "open it in the editor", sent: "open at in the editor"), [])
    }
}
