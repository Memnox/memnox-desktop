import XCTest

@testable import MemnoxVoiceCore

/// Choosing the few names the recognizer is told to expect.
final class RecognizerHintsTests: XCTestCase {
    func testKeepsTheNamesSaidMostAheadOfTheMachinesOwn() {
        let hints = chosenHints(["Memnox", "VS Code"], ["memnox", "memnox-runtime", "iTerm"], most: 3)
        XCTAssertEqual(hints, ["Memnox", "VS Code", "memnox-runtime"])
    }

    func testNeverHandsTheRecognizerMoreThanItWeighsWell() {
        let many = (1...600).map { "name\($0)" }
        XCTAssertEqual(chosenHints(["Memnox"], many).count, mostRecognizerHints)
        XCTAssertEqual(chosenHints(["Memnox"], many).first, "Memnox")
    }
}
