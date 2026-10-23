import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// What it says back when called by name.
final class WakeLinesTests: XCTestCase {
    func testGreetsTheFirstCallInAWhileForTheHourAndNeverRepeatsALine() {
        var lines = WakeLines()
        let first = { (choices: [String]) in choices.first }
        XCTAssertEqual(lines.line(address: "sir", hour: 20, sinceLastCall: nil, pick: first), "Good evening, sir. What can I do for you?")
        XCTAssertEqual(lines.line(address: nil, hour: 8, sinceLastCall: 5 * 60 * 60, pick: first), "Good morning. What can I do for you?")
        // Called again soon after, a word or two, and never the line said last.
        XCTAssertEqual(lines.line(address: "sir", hour: 20, sinceLastCall: 30, pick: first), "How may I help, sir?")
        XCTAssertEqual(lines.line(address: "sir", hour: 20, sinceLastCall: 30, pick: first), "I'm listening, sir.")
        // No address chosen, no honorific guessed.
        XCTAssertFalse(lines.line(address: "  ", hour: 20, sinceLastCall: 30).contains("sir"))
        // Never "Yes", which sounds like agreeing to something nobody asked.
        for _ in 0..<20 { XCTAssertFalse(lines.line(address: "sir", hour: 20, sinceLastCall: 30).hasPrefix("Yes")) }
    }

    func testGreetsByNameThenSaysTheTitleUntilTheNameHasRested() {
        var lines = WakeLines()
        let first = { (choices: [String]) in choices.first }
        let start = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(lines.line(address: "sir", name: "Moiz", hour: 8, sinceLastCall: nil, at: start, pick: first),
                       "Good morning, Moiz. What can I do for you?")
        XCTAssertEqual(lines.line(address: "sir", name: "Moiz", hour: 8, sinceLastCall: 60, at: start.addingTimeInterval(60), pick: first),
                       "How may I help, sir?")
        XCTAssertEqual(lines.line(address: "sir", name: "Moiz", hour: 9, sinceLastCall: 60, at: start.addingTimeInterval(31 * 60), pick: first),
                       "How may I help, Moiz?")
        // A name with no address chosen is never used to address them.
        var bare = WakeLines()
        XCTAssertEqual(bare.line(address: nil, name: "Moiz", hour: 8, sinceLastCall: 60, pick: first), "How may I help?")
    }
}
