import XCTest
@testable import MemnoxVoiceCore

final class HistoryTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testKeepsTheReplyWithItsQuestionNewestFirst() {
        var history = History()
        history.ask("what is Claude doing", at: start)
        history.reply("It is adding VAT")
        history.reply(" to invoices.")
        XCTAssertEqual(history.current?.answer, "It is adding VAT to invoices.")
        history.end(at: start.addingTimeInterval(4))
        XCTAssertNil(history.current)
        history.ask("and the tests?", at: start.addingTimeInterval(10))
        history.reply("They pass.")
        XCTAssertEqual(history.exchanges.map(\.question), ["and the tests?", "what is Claude doing"])
        XCTAssertEqual(history.exchanges[1].elapsed(now: start.addingTimeInterval(99)), 4)
    }

    func testANewQuestionEndsAReplyLeftOpen() {
        var history = History()
        history.ask("first", at: start)
        history.reply("Half an answer")
        history.ask("second", at: start.addingTimeInterval(3))
        XCTAssertEqual(history.exchanges[1].answeredAt, start.addingTimeInterval(3))
    }

    func testDropsAQuestionThatGotNoWords() {
        var history = History()
        history.ask("hello?", at: start)
        history.end(at: start.addingTimeInterval(1))
        XCTAssertTrue(history.exchanges.isEmpty)
        // A reply with no question open has nowhere to go.
        history.reply("stray")
        XCTAssertTrue(history.exchanges.isEmpty)
        history.ask("   ", at: start)
        XCTAssertTrue(history.exchanges.isEmpty)
    }

    func testKeepsAFailedQuestionWithItsReasonSoItCanBeAskedAgain() {
        var history = History()
        history.ask("what is Claude doing", at: start)
        history.end(at: start.addingTimeInterval(1), failure: "Memnox could not be reached")
        XCTAssertEqual(history.exchanges.first?.failure, "Memnox could not be reached")
        XCTAssertEqual(history.exchanges.first?.failed, true)
        XCTAssertNil(history.current)
    }

    func testFindsExchangesByTheirQuestionOrAnswerIgnoringCase() {
        var history = History()
        history.ask("what changed in shop", at: start)
        history.reply("The **Invoice** total.")
        history.end(at: start.addingTimeInterval(1))
        history.ask("is the build green", at: start.addingTimeInterval(5))
        history.reply("Yes.")
        history.end(at: start.addingTimeInterval(6))
        XCTAssertEqual(history.matching("invoice").map(\.question), ["what changed in shop"])
        XCTAssertEqual(history.matching("BUILD").map(\.question), ["is the build green"])
        XCTAssertEqual(history.matching("  ").count, 2)
        XCTAssertTrue(history.matching("deploy").isEmpty)
    }

    func testKeepsOnlyTheNewest() {
        var history = History()
        for index in 0..<(History.kept + 5) {
            history.ask("question \(index)", at: start.addingTimeInterval(TimeInterval(index)))
            history.reply("answer")
            history.end(at: start.addingTimeInterval(TimeInterval(index)))
        }
        XCTAssertEqual(history.exchanges.count, History.kept)
        XCTAssertEqual(history.exchanges.first?.question, "question \(History.kept + 4)")
    }

    func testSurvivesARoundTripThroughJSON() throws {
        var history = History()
        history.ask("what changed", at: start)
        history.reply("Two files.")
        history.end(at: start.addingTimeInterval(2))
        let data = try JSONEncoder().encode(history)
        XCTAssertEqual(try JSONDecoder().decode(History.self, from: data), history)
    }
}
