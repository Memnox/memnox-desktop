import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// A phone's turn put together from the daemon's notices: said starts it, chunks add to it, ended closes it.
final class PhoneConversationTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)
    private let later = Date(timeIntervalSince1970: 1_004)

    private func turn(said: String? = nil, answer: String? = nil, ended: Bool? = nil, device: String = "dev_1") -> PhoneTurn {
        PhoneTurn(deviceId: device, name: "Sam's iPhone", said: said, answer: answer, ended: ended)
    }

    func testAssemblesSaidThenChunksThenEnded() throws {
        var conversation = PhoneConversation()
        let opened = try XCTUnwrap(conversation.take(turn(said: "what changed"), at: start))
        XCTAssertEqual(opened.said, "what changed")
        XCTAssertEqual(opened.answer, "")
        XCTAssertTrue(opened.isAnswering)
        _ = conversation.take(turn(answer: "Two files, "), at: start)
        let more = try XCTUnwrap(conversation.take(turn(answer: "both tests."), at: start))
        XCTAssertEqual(more.answer, "Two files, both tests.")
        XCTAssertEqual(more.id, opened.id)
        let ended = try XCTUnwrap(conversation.take(turn(ended: true), at: later))
        XCTAssertFalse(ended.isAnswering)
        XCTAssertEqual(ended.endedAt, later)
        XCTAssertEqual(ended.answer, "Two files, both tests.")
    }

    func testReadsAsAnExchangeForTheAnswerCard() throws {
        var conversation = PhoneConversation()
        _ = conversation.take(turn(said: "what changed"), at: start)
        let ended = try XCTUnwrap(conversation.take(turn(answer: "Two files", ended: true), at: later))
        let exchange = ended.exchange
        XCTAssertEqual(exchange.id, ended.id)
        XCTAssertEqual(exchange.question, "what changed")
        XCTAssertEqual(exchange.answer, "Two files")
        XCTAssertEqual(exchange.askedAt, start)
        XCTAssertEqual(exchange.answeredAt, later)
    }

    func testANewSaidStartsANewTurn() throws {
        var conversation = PhoneConversation()
        let first = try XCTUnwrap(conversation.take(turn(said: "one"), at: start))
        _ = conversation.take(turn(answer: "first answer", ended: true), at: start)
        let second = try XCTUnwrap(conversation.take(turn(said: "two"), at: later))
        XCTAssertNotEqual(second.id, first.id)
        XCTAssertEqual(second.answer, "")
        XCTAssertTrue(second.isAnswering)
    }

    func testShowsAnAnswerWhoseStartWasMissedUnderNoQuestion() throws {
        var conversation = PhoneConversation()
        let missed = try XCTUnwrap(conversation.take(turn(answer: "Two files"), at: start))
        XCTAssertNil(missed.said)
        XCTAssertEqual(missed.exchange.question, "")
        XCTAssertEqual(missed.answer, "Two files")
    }

    func testIgnoresAnEndOrAnEmptyChunkWithNoTurnOpen() {
        var conversation = PhoneConversation()
        XCTAssertNil(conversation.take(turn(ended: true), at: start))
        XCTAssertNil(conversation.take(turn(answer: ""), at: start))
        XCTAssertNil(conversation.take(turn(said: "   "), at: start))
        XCTAssertNil(conversation.current)
    }

    func testAChunkAfterTheEndStartsNoNewTurnUnderTheOldQuestion() throws {
        var conversation = PhoneConversation()
        _ = conversation.take(turn(said: "one", answer: "done", ended: true), at: start)
        let stray = try XCTUnwrap(conversation.take(turn(answer: "late"), at: later))
        XCTAssertNil(stray.said)
        XCTAssertEqual(stray.answer, "late")
    }

    func testAnotherPhoneDoesNotAddToThisPhonesTurn() throws {
        var conversation = PhoneConversation()
        _ = conversation.take(turn(said: "one"), at: start)
        let other = try XCTUnwrap(conversation.take(turn(answer: "elsewhere", device: "dev_2"), at: start))
        XCTAssertEqual(other.deviceId, "dev_2")
        XCTAssertNil(other.said)
    }

    func testSaysWhoIsTalkingWithAPlainWordForNoName() {
        XCTAssertEqual(PhoneExchange(deviceId: "dev_1", name: "Sam's iPhone", said: nil, startedAt: start).label, "From Sam's iPhone")
        XCTAssertEqual(PhoneExchange(deviceId: "dev_1", name: " ", said: nil, startedAt: start).label, "From your phone")
    }
}
