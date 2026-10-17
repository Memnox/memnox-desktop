import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Resting between rounds of listening for its name, longer while the recognizer keeps failing.
final class WakeRestTests: XCTestCase {
    func testRestsBrieflyAfterARoundThatWorked() {
        var rest = WakeRest()
        XCTAssertEqual(rest.after(failed: false), WakeRest.afterWorking)
        XCTAssertEqual(rest.after(failed: false), WakeRest.afterWorking)
    }

    func testDoublesTheRestWithEachFailureInARow() {
        var rest = WakeRest()
        XCTAssertEqual(rest.after(failed: true), 1)
        XCTAssertEqual(rest.after(failed: true), 2)
        XCTAssertEqual(rest.after(failed: true), 4)
        XCTAssertEqual(rest.after(failed: true), 8)
    }

    func testNeverRestsLongerThanHalfAMinute() {
        var rest = WakeRest()
        for _ in 0..<20 { _ = rest.after(failed: true) }
        XCTAssertEqual(rest.after(failed: true), WakeRest.longest)
    }

    func testARoundThatWorkedStartsTheCountAgain() {
        var rest = WakeRest()
        _ = rest.after(failed: true)
        _ = rest.after(failed: true)
        XCTAssertEqual(rest.after(failed: false), WakeRest.afterWorking)
        XCTAssertEqual(rest.after(failed: true), WakeRest.afterFirstFailure)
    }
}
