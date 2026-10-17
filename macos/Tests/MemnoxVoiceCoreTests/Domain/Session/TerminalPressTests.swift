import XCTest
@testable import MemnoxVoiceCore

final class TerminalPressTests: XCTestCase {
    func testReadsTheKeysThatPickTheSecondChoiceOfAList() {
        XCTAssertEqual(TerminalPress.parse("down enter"), [.key(.down), .key(.enter)])
        XCTAssertEqual(TerminalPress.parse("2"), [.character("2")])
        XCTAssertEqual(TerminalPress.parse("Y, Enter"), [.character("y"), .key(.enter)])
    }

    func testPressesNothingWhenAnyWordIsNotAKey() {
        // A sentence typed a key at a time is an instruction, which is never sent this way.
        XCTAssertNil(TerminalPress.parse("rm -rf enter"))
        XCTAssertNil(TerminalPress.parse("yes enter"))
        XCTAssertNil(TerminalPress.parse(""))
        XCTAssertNil(TerminalPress.parse(Array(repeating: "down", count: TerminalPress.mostKeys + 1).joined(separator: " ")))
    }

    func testHandsATerminalTheSequenceItReadsForEachKey() {
        XCTAssertEqual(TerminalPress.parse("down enter")?.map(\.sequence).joined(), "\u{1B}[B\r")
    }
}
