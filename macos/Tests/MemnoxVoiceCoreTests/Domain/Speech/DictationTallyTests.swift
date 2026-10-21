import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// The totals the overview shows: every word counted, speed only from timed speech, and the streak as a person counts it.
final class DictationTallyTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!  // fixed, so the tests run the same anywhere
        return calendar
    }()

    private func at(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!  // a fixed valid date
    }

    private func entry(_ words: String, day: Int, seconds: Double? = nil) -> DictationEntry {
        DictationEntry(at: at(day), heard: words, written: words, app: nil, seconds: seconds)
    }

    func testCountsEveryWord() {
        var tally = DictationTally()
        tally.add(entry("one two three", day: 20), calendar: calendar)
        tally.add(entry("four five", day: 21, seconds: 2), calendar: calendar)
        XCTAssertEqual(tally.words, 5)
    }

    func testTakesSpeedOnlyFromTimedSpeechAndOnlyOnceThereIsEnough() {
        var tally = DictationTally()
        tally.add(entry(String(repeating: "word ", count: 30), day: 20, seconds: 15), calendar: calendar)
        XCTAssertNil(tally.wordsPerMinute)
        tally.add(entry(String(repeating: "word ", count: 30), day: 20, seconds: 15), calendar: calendar)
        tally.add(entry(String(repeating: "word ", count: 100), day: 20), calendar: calendar)
        XCTAssertEqual(tally.wordsPerMinute, 120)
    }

    func testCountsDaysInARowEndingToday() {
        var tally = DictationTally()
        for day in [17, 19, 20, 21] { tally.add(entry("hi", day: day), calendar: calendar) }
        XCTAssertEqual(tally.streak(today: at(21), calendar: calendar), 3)
    }

    func testKeepsTheStreakAliveBeforeTodaysFirstDictation() {
        var tally = DictationTally()
        for day in [19, 20] { tally.add(entry("hi", day: day), calendar: calendar) }
        XCTAssertEqual(tally.streak(today: at(21, hour: 8), calendar: calendar), 2)
    }

    func testEndsTheStreakAfterAWholeDayMissed() {
        var tally = DictationTally()
        tally.add(entry("hi", day: 18), calendar: calendar)
        XCTAssertEqual(tally.streak(today: at(21), calendar: calendar), 0)
    }

    func testCountsADayOnceHoweverOftenItIsDictated() {
        var tally = DictationTally()
        for _ in 0..<3 { tally.add(entry("hi", day: 21), calendar: calendar) }
        XCTAssertEqual(tally.days.count, 1)
    }

    func testStartsFromTheHistoryOfAMacThatDictatedBefore() {
        let history = [entry("newest one", day: 21), entry("older", day: 20)]
        let tally = DictationTally(history, calendar: calendar)
        XCTAssertEqual(tally.words, 3)
        XCTAssertEqual(tally.streak(today: at(21), calendar: calendar), 2)
    }
}
