import XCTest

@testable import MemnoxVoiceCore

/// Finding a session's tab by what is on screen in it.
final class TabMatchTests: XCTestCase {
    private let marks = ["fix the flaky auth test", "The test now waits for the token"]

    func testPicksTheTabShowingTheSessionsOwnLinesEvenWrapped() {
        let tabs = [
            "~/work/memnox-cloud $ npm run build",
            "> fix the flaky auth\ntest\n⏺ The test now waits for the\ntoken before it asserts",
            "> push the voice branch",
        ]
        XCTAssertEqual(TabMatch.best(tabs, marks: marks), 1)
    }

    func testIsCertainOnlyWhenEveryLineIsShown() {
        XCTAssertTrue(TabMatch.isCertain("> fix the flaky auth test\n⏺ The test now waits for the token", marks: marks))
        XCTAssertFalse(TabMatch.isCertain("> fix the flaky auth test", marks: marks))
        XCTAssertFalse(TabMatch.isCertain("anything", marks: []))
    }

    func testPicksNothingWhenNoTabOrTwoTabsShowIt() {
        XCTAssertNil(TabMatch.best(["$ ls", "$ git status"], marks: marks))
        XCTAssertNil(TabMatch.best(["fix the flaky auth test", "fix the flaky auth test"], marks: marks))
        XCTAssertNil(TabMatch.best(["anything"], marks: []))
    }
}
