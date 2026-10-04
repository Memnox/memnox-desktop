import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Telling the person cutting in from the voice hearing its own echo.
final class EchoTests: XCTestCase {
    func testTakesTheTailOfItsOwnSentenceOffWhatItHeard() {
        let spoken = "My apologies, that was not confirmed: memnox login is not something a voice may run."
        XCTAssertEqual(withoutEchoRuns("Confirmed Memnox login", spoken: spoken), "")
        // One word at an end could be theirs, so it stays.
        XCTAssertEqual(withoutEchoRuns("Yes, login", spoken: spoken), "Yes, login")
    }

    func testKeepsThePersonsWordsThatItsSentenceOnlyHoldsOutOfOrder() {
        // "can" and "you" are both in its greeting, but not one after the other, so they are the person's.
        let spoken = "Good morning. What can I do for you?"
        XCTAssertEqual(withoutEchoRuns("Can you?", spoken: spoken), "Can you?")
        XCTAssertEqual(withoutEchoRuns("do for you show my sessions", spoken: spoken), "show my sessions")
    }

    func testTellsThePersonTalkingOverItFromItsOwnEcho() {
        let spoken = "Claude Code finished checkout, four files changed and the tests pass."
        XCTAssertFalse(isBargeIn(heard: "four files changed and the tests", spoken: spoken))
        XCTAssertFalse(isBargeIn(heard: "the", spoken: spoken))
        XCTAssertTrue(isBargeIn(heard: "wait, what about codex", spoken: spoken))
        XCTAssertTrue(isBargeIn(heard: "stop open it", spoken: ""))
    }

    func testHearsThePersonWhoseShortWordsSoundLikeItsOwn() {
        // "so" is a letter from "to" and "them" holds "the": the person, not its echo.
        let spoken = "Two are working at the moment."
        XCTAssertTrue(isBargeIn(heard: "Okay, so can you close all of them?", spoken: spoken, speaking: true))
        XCTAssertEqual(withoutEchoRuns("Okay, so can you close all of them?", spoken: spoken), "Okay, so can you close all of them?")
    }

    func testDoesNotTakeItsOwnSentenceMisheardAtTheEndForThePerson() {
        let spoken = "I missed that. Which repository would you like the session on, and what should it check for?"
        XCTAssertFalse(isBargeIn(heard: "I missed that we were positive", spoken: spoken, speaking: true))
        XCTAssertTrue(isBargeIn(heard: "no the memnox client folder please", spoken: spoken, speaking: true))
    }

    func testDoesNotTakeItsOwnVoiceMisheardForThePerson() {
        XCTAssertFalse(isBargeIn(heard: "Possession is running", spoken: "The session's running but its window isn't tracked", speaking: true))
        XCTAssertFalse(isBargeIn(heard: "Let me log everything", spoken: "Let me look. Everything's quiet.", speaking: true))
        XCTAssertFalse(isBargeIn(heard: "Which one menu bar", spoken: "Which one, MenuBar, Showing, or the renderer tweak?", speaking: true))
        XCTAssertFalse(isBargeIn(heard: "There is", spoken: "There's a card on your screen with the summary.", speaking: true))
        XCTAssertTrue(isBargeIn(heard: "Nothing's working now the fingerprint can you tell me what", spoken: "Nothing's working now. The fingerprint task was the last one.", speaking: true))
        // A long reply heard back first, then the person: the newest words decide, not the whole of it.
        let reply = "I keep an eye on your agent sessions and tell you what each is doing"
        XCTAssertTrue(isBargeIn(heard: "\(reply) wait stop which one is working", spoken: reply, speaking: true))
        XCTAssertFalse(isBargeIn(heard: reply, spoken: reply, speaking: true))
        XCTAssertEqual(withoutEcho("Nothing's working now the fingerprint can you tell me what", spoken: "Nothing's working now. The fingerprint task was the last one."), "can you tell me what")
    }

    func testStopOrWaitCutsInAtOnceButItsOwnWordsNeverDo() {
        let spoken = "Claude Code has been building the voice bridge for the Mac app"
        XCTAssertTrue(isBargeIn(heard: "Claude Code has been shut up", spoken: spoken, speaking: true))
        XCTAssertTrue(isBargeIn(heard: "stop", spoken: spoken, speaking: true))
        XCTAssertTrue(isBargeIn(heard: "wait", spoken: spoken, speaking: true))
        // Its own words echoed back are never the person, even when they are long.
        XCTAssertFalse(isBargeIn(heard: "the voice bridge for the Mac", spoken: spoken, speaking: true))
        // It said "stop" itself, so hearing "stop" is its own echo.
        XCTAssertFalse(isBargeIn(heard: "stop", spoken: "I can stop the session", speaking: true))
    }
}
