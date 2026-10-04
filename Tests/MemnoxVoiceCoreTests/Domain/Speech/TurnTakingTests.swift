import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// How long a pause ends what somebody says, and when a guess may start early.
final class TurnTakingTests: XCTestCase {
    func testWaitsLongerWhenSomebodyTrailsOff() {
        XCTAssertEqual(endOfSpeechPause(after: "What are my agents doing?"), 0.9)
        XCTAssertEqual(endOfSpeechPause(after: "what are my agents doing"), 1.7)
        XCTAssertEqual(endOfSpeechPause(after: "Okay, so are you able to uh"), 3.0)
        XCTAssertEqual(endOfSpeechPause(after: "Can Claude Code connect to"), 3.0)
        XCTAssertEqual(endOfSpeechPause(after: "My..."), 3.0)
        XCTAssertEqual(endOfSpeechPause(after: "OK so I was working on the feature and"), 3.0)
        XCTAssertEqual(endOfSpeechPause(after: "I wanted to know about my"), 3.0)
        XCTAssertEqual(endOfSpeechPause(after: "Yes."), 0.6)
        XCTAssertEqual(endOfSpeechPause(after: "Go ahead."), 0.6)
        // The recognizer marks "Can you?" as finished, but it is only how a request starts.
        XCTAssertEqual(endOfSpeechPause(after: "Can you?"), 3.0)
        XCTAssertEqual(endOfSpeechPause(after: "Is there"), 3.0)
        XCTAssertEqual(endOfSpeechPause(after: "Thank you."), 0.6)
        // Somebody explaining pauses between sentences, so the first one is not answered alone.
        XCTAssertEqual(endOfSpeechPause(after: "Can you open Cursor and start a new session within Memnox runtime and check the git status?"), 1.5)
        XCTAssertEqual(endOfSpeechPause(after: "Can you scan my entire computer and tell me?"), 1.5)
        XCTAssertEqual(endOfSpeechPause(after: "Open the last one."), 0.9)
    }

    func testGuessesAtAPauseOnlyBeforeItEndsWhatTheySaid() {
        // A finished question pauses long enough to start the answer, and is not over yet.
        XCTAssertTrue(mayGuess("What is Claude doing?", pausedFor: 0.4))
        // Too soon, and past the end, there is nothing to guess.
        XCTAssertFalse(mayGuess("What is Claude doing?", pausedFor: 0.2))
        XCTAssertFalse(mayGuess("What is Claude doing?", pausedFor: 1.0))
        // Trailing off on "and" is the middle of a thought, never worth an answer.
        XCTAssertFalse(mayGuess("Open the Claude session and", pausedFor: 0.6))
        XCTAssertFalse(mayGuess("", pausedFor: 0.6))
    }

    func testAVoiceStillTalkingKeepsTheTurnOpenWhileTheWordsLagBehind() {
        let word = Date(timeIntervalSince1970: 100)
        // Words stopped two seconds ago, but they were heard talking half a second ago.
        XCTAssertEqual(quietFor(now: word.addingTimeInterval(2), lastWord: word, lastVoice: word.addingTimeInterval(1.5)), 0.5, accuracy: 0.001)
        // Nothing heard since the words, so the quiet counts from them.
        XCTAssertEqual(quietFor(now: word.addingTimeInterval(2), lastWord: word, lastVoice: nil), 2, accuracy: 0.001)
        // A noisy room holds it open only so long past the last word.
        XCTAssertEqual(quietFor(now: word.addingTimeInterval(10), lastWord: word, lastVoice: word.addingTimeInterval(9.9)), 10 - voiceHoldsFor, accuracy: 0.001)
    }

    func testJoinsTheRecognizersSegmentsWithTheSpaceItLeftOut() {
        XCTAssertEqual(joinedSpeech("I guess so.", "Is there any of these sessions working?"), "I guess so. Is there any of these sessions working?")
        XCTAssertEqual(joinedSpeech("", " Can you"), "Can you")
        XCTAssertEqual(joinedSpeech("Can you ", ""), "Can you")
    }

    func testTakesWordsFromAListenOnlyWhenItWasLoudEnoughToBeSpeech() {
        XCTAssertFalse(soundedLikeSpeech(loudest: 0.05))
        XCTAssertTrue(soundedLikeSpeech(loudest: quietestSpeech))
        XCTAssertTrue(soundedLikeSpeech(loudest: 0.45))
    }
}
