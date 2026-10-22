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

    func testKeepsWhatAnActionLeftBesideTheAnswerThatTookIt() {
        var history = History()
        history.ask("tell claude to push", at: start)
        history.prove(Proof(checked: "the words in its iTerm tab", seen: "> push", image: "/p/1.png"))
        history.reply("Sent, and I saw it land.")
        history.end(at: start.addingTimeInterval(2))
        XCTAssertEqual(history.exchanges.first?.proofs, [Proof(checked: "the words in its iTerm tab", seen: "> push", image: "/p/1.png")])
    }

    func testReadsAHistorySavedBeforeProofsWereKept() throws {
        let saved = #"{"exchanges":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","question":"hi","answer":"Hello.","askedAt":0}]}"#
        let history = try JSONDecoder().decode(History.self, from: Data(saved.utf8))
        XCTAssertEqual(history.exchanges.first?.proofs, [])
    }

    func testKeepsATurnThatOnlyActed() {
        var history = History()
        history.ask("open the docs", at: start)
        history.act(TakenAction(tool: "open_link", at: start))
        history.end(at: start.addingTimeInterval(1))
        XCTAssertEqual(history.exchanges.first?.actions.map(\.tool), ["open_link"])
    }

    func testFindsAnExchangeByWhatItDid() {
        var history = History()
        history.ask("tell the team", at: start)
        history.reply("Sent.")
        history.end(at: start.addingTimeInterval(1))
        history.act(TakenAction(tool: "SLACK_SEND_MESSAGE", toolkit: "slack", kind: "message", about: "#launch", at: start))
        XCTAssertEqual(history.matching("launch").count, 1)
        XCTAssertEqual(history.matching("calendar").count, 0)
    }
}
