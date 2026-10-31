import XCTest

@testable import MemnoxVoiceCore

/// When a dictation's polish starts at a pause, before the key comes up.
final class EarlyPolishPlanTests: XCTestCase {
    func testStartsAtAPauseAfterEnoughWords() {
        XCTAssertTrue(EarlyPolishPlan.mayStart("send the report", pausedFor: 0.5, after: []))
        XCTAssertFalse(EarlyPolishPlan.mayStart("send the report", pausedFor: 0.2, after: []))
        XCTAssertFalse(EarlyPolishPlan.mayStart("send it", pausedFor: 1, after: []))
    }

    func testStartsAgainOnlyOnceEnoughWordsChangedAndNoMoreThanTwice() {
        let first = dictationWordKey("send the report")
        XCTAssertFalse(EarlyPolishPlan.mayStart("send the report to", pausedFor: 1, after: [first]))
        XCTAssertTrue(EarlyPolishPlan.mayStart("send the report to the team", pausedFor: 1, after: [first]))
        let second = dictationWordKey("send the report to the team")
        XCTAssertFalse(EarlyPolishPlan.mayStart("send the report to the whole team today please", pausedFor: 1,
                                                after: [first, second]))
    }

    func testTheSameWordsHaveTheSameKeyWhateverTheirPunctuationOrCase() {
        XCTAssertEqual(dictationWordKey("Send the report, please."), dictationWordKey("send the report please"))
        XCTAssertEqual(dictationWordsChanged(from: "a b c", to: "a b x y"), 2)
    }
}
