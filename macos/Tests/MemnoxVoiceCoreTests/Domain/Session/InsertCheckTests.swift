import XCTest

@testable import MemnoxVoiceCore

/// Words put in at once are called in only when the box shows them, and tried another way only when the box never moved.
final class InsertCheckTests: XCTestCase {
    private let words = "Start a React Native Expo app"

    func testLandsWhenTheBoxNowHoldsTheWords() {
        XCTAssertEqual(InsertCheck.landing(words, valueBefore: "", valueNow: words, caretBefore: 0, caretNow: 29), .landed)
    }

    func testLandsAfterWordsTheBoxAlreadyHeld() {
        XCTAssertEqual(InsertCheck.landing(words, valueBefore: "Please", valueNow: "Please " + words, caretBefore: 6, caretNow: 36), .landed)
    }

    func testIsUnchangedWhenNothingMoved() {
        XCTAssertEqual(InsertCheck.landing(words, valueBefore: "", valueNow: "", caretBefore: 0, caretNow: 0), .unchanged)
    }

    func testIsNotLandedWhenTheBoxHeldTheWordsAlready() {
        XCTAssertEqual(InsertCheck.landing(words, valueBefore: words, valueNow: words, caretBefore: 29, caretNow: 29), .unchanged)
    }

    func testIsChangedWhenTheBoxTookSomethingElse() {
        XCTAssertEqual(InsertCheck.landing(words, valueBefore: "", valueNow: "Start a", caretBefore: 0, caretNow: 7), .changed)
    }

    func testTrustsTheCaretOnlyWhenTheValueCannotBeRead() {
        XCTAssertEqual(InsertCheck.landing(words, valueBefore: nil, valueNow: nil, caretBefore: 4, caretNow: 4 + words.count), .landed)
        XCTAssertEqual(InsertCheck.landing(words, valueBefore: nil, valueNow: nil, caretBefore: 4, caretNow: 9), .changed)
        XCTAssertEqual(InsertCheck.landing(words, valueBefore: "", valueNow: "", caretBefore: 0, caretNow: words.count), .changed)
    }
}
