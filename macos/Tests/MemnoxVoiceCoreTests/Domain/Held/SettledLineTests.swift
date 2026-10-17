import XCTest

@testable import MemnoxVoiceCore

/// What a card says for a moment when its call was settled elsewhere, from only what was reported.
final class SettledLineTests: XCTestCase {
    func testWhoWhereAndHow() {
        XCTAssertEqual(SettledLine.line(answer: "once", by: "Ana", on: "the build phone"), "Allowed once by Ana on the build phone")
        XCTAssertEqual(SettledLine.line(answer: "deny", by: "Ana", on: "console"), "Denied by Ana in the console")
        XCTAssertEqual(SettledLine.line(answer: "session", by: "Ana", on: "Slack"), "Allowed for the session by Ana in Slack")
    }

    func testADeviceThatAlreadySaysWhoseIsNotSaidTwice() {
        XCTAssertEqual(SettledLine.line(answer: nil, by: "Ana", on: "Ana's iPhone"), "Answered on Ana's iPhone")
    }

    func testOnlyWhatWasReported() {
        XCTAssertEqual(SettledLine.line(answer: nil, by: "Ana", on: nil), "Answered by Ana")
        XCTAssertEqual(SettledLine.line(answer: "deny", by: nil, on: "Ana's iPhone"), "Denied on Ana's iPhone")
        XCTAssertEqual(SettledLine.line(answer: "once", by: nil, on: nil), "Allowed once elsewhere")
    }

    func testNothingReportedClaimsNeitherAnAnswerNorWho() {
        XCTAssertEqual(SettledLine.line(answer: nil, by: nil, on: nil), SettledLine.unknown)
        XCTAssertEqual(SettledLine.line(answer: "maybe", by: " ", on: ""), SettledLine.unknown)
    }

    func testAnAnswerWordItDoesNotKnowIsLeftUnsaid() {
        XCTAssertEqual(SettledLine.line(answer: "maybe", by: "Ana", on: nil), "Answered by Ana")
    }
}
