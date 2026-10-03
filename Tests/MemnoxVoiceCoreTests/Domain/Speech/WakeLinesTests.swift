import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// What it says back when called by name.
final class WakeLinesTests: XCTestCase {
    func testGreetsTheFirstCallInAWhileForTheHourAndNeverRepeatsALine() {
        var lines = WakeLines()
        let first = { (choices: [String]) in choices.first }
        XCTAssertEqual(lines.line(address: "sir", hour: 20, sinceLastCall: nil, pick: first), "Good evening, sir. How shall we proceed?")
        XCTAssertEqual(lines.line(address: nil, hour: 8, sinceLastCall: 5 * 60 * 60, pick: first), "Good morning. How shall we proceed?")
        // Called again soon after, a word or two, and never the line said last.
        XCTAssertEqual(lines.line(address: "sir", hour: 20, sinceLastCall: 30, pick: first), "Yes, sir?")
        XCTAssertEqual(lines.line(address: "sir", hour: 20, sinceLastCall: 30, pick: first), "Sir?")
        // No address chosen, no honorific guessed.
        XCTAssertFalse(lines.line(address: "  ", hour: 20, sinceLastCall: 30).contains("sir"))
    }
}
