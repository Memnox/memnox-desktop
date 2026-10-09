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

    func testTakesOffWhatIsLeftOfItsEchoWhereTheRecognizerSplitAWord() {
        let spoken = "Very well. That rule is in force in HireMe.AI."
        XCTAssertEqual(withoutEchoRuns("Very well that rule is enforced in hire me AI", spoken: spoken), "")
        // The person answering straight after it is kept.
        XCTAssertEqual(withoutEchoRuns("Very well that rule is in force, now push it", spoken: spoken), "now push it")
        // A word of theirs on its own, with nothing of the echo beside it, is never taken.
        XCTAssertEqual(withoutEchoRuns("rule", spoken: spoken), "rule")
        // What the person said after a name it split is theirs, and the split name is not.
        XCTAssertEqual(withoutEchoRuns("Very well that rule is enforced in hire me AI so can you", spoken: spoken), "so can you")
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

    func testPausesOnTheFirstWordsThatAreNotItsOwn() {
        let spoken = "Claude Code finished setting up the voice picker in memnox macos"
        XCTAssertTrue(mayBeCuttingIn(heard: "Claude Code finished setting why not", spoken: spoken))
        // One stray word is its own voice misheard as often as it is the person.
        XCTAssertFalse(mayBeCuttingIn(heard: "Claude Code finished setting why", spoken: spoken))
        XCTAssertTrue(mayBeCuttingIn(heard: "Claude Code finished stop", spoken: spoken))
        XCTAssertFalse(mayBeCuttingIn(heard: "Claude Code finished setting up", spoken: spoken))
        // A stray word of its own misheard, followed by more of its own, is past and no reason to pause.
        XCTAssertFalse(mayBeCuttingIn(heard: "Claude Code polished setting up the voice", spoken: spoken))
        XCTAssertFalse(mayBeCuttingIn(heard: "", spoken: spoken))
    }

    func testCarriesOnOverItsOwnWordsHeardWrongOrHalfHeard() {
        // Each of these paused the voice for a second and a half on 2026-10-04, which is what cut it.
        let rules = "Two rules are on a card on the Mac, one to ask before you push, the other to ask before you create a pull request."
        XCTAssertFalse(mayBeCuttingIn(heard: "Two rules are on a card on the Mac want", spoken: rules))
        XCTAssertFalse(mayBeCuttingIn(heard: "The other to ask before you create a pool", spoken: rules))
        let starting = "Shall I start Cursor in memnox runtime to review your changes?"
        XCTAssertFalse(mayBeCuttingIn(heard: "Shall I start cursor in me", spoken: starting))
        XCTAssertFalse(mayBeCuttingIn(heard: "Shall I start cur", spoken: starting))
        let finished = "Claude Code in memnox runtime finished a moment ago and is waiting on you."
        XCTAssertFalse(mayBeCuttingIn(heard: "Claude Code in memory", spoken: finished))
        XCTAssertFalse(mayBeCuttingIn(heard: "Claude Code in Memnox runtime finished a moment ago and he", spoken: finished))
        // Its own name, said in its own sentence, is no call to stop; the person saying it over another is.
        XCTAssertFalse(mayBeCuttingIn(heard: "Claude is open in Memnox", spoken: "Claude is open in memnox-runtime with your request in it."))
        XCTAssertTrue(mayBeCuttingIn(heard: "Five agents on your Memnox", spoken: "Five agents on your Mac."))
    }

    func testTakesOnlyWhatCameOnceItWentQuietForThePerson() {
        // Its own heads up read a path the recognizer turned into "Galo Shanaka": that paused it, nothing more.
        let spoken = "Moïse, Claude Code in memnox macos wants to delete src. Allow it, or deny?"
        let pausedOn = "My Claude Code in memnox macos wants to delete and Galo"
        XCTAssertFalse(isPersonAfterPause(sincePause("\(pausedOn) Shanaka", pausedOn: pausedOn), spoken: spoken))
        // The person carrying on once it is quiet is them, and only their words are kept.
        let heard = "\(pausedOn) wait which folder is that"
        XCTAssertTrue(isPersonAfterPause(sincePause(heard, pausedOn: pausedOn), spoken: spoken))
        XCTAssertEqual(sincePause(heard, pausedOn: pausedOn), "and Galo wait which folder is that")
        // "Stop" alone is enough, even as the word it paused on.
        XCTAssertTrue(isPersonAfterPause(sincePause("Claude Code stop", pausedOn: "Claude Code stop"), spoken: spoken))
    }
    /// The voice log of 2026-10-05: its own "a write there asks first" came back as "right there ask for"
    /// once it paused, was taken for the person, and the held call it was asking about was dropped.
    func testTakesItsOwnWordsSaidAlikeAfterAPauseForItsEcho() {
        let spoken = "index dot J S is outside memnox runtime, where this session works, so a write there asks first. Allow it, or deny?"
        let pausedOn = "index.JS is outside Memnox runtime where the session works so we're right"
        let heard = "\(pausedOn) there ask for"
        XCTAssertFalse(isPersonAfterPause(sincePause(heard, pausedOn: pausedOn), spoken: spoken))
        // The person saying something of their own after the same pause still cuts in.
        XCTAssertTrue(isPersonAfterPause(sincePause("\(pausedOn) open the billing session", pausedOn: pausedOn), spoken: spoken))
    }
    /// The voice log of 2026-10-08: they were talking while it thought, it paused only once it spoke over
    /// them, and everything before the last two words was dropped, leaving "to talk you said".
    func testKeepsWhatTheySaidWhileItWasQuiet() {
        let spoken = "Codex is open, and your words are on the clipboard, since I could not type them in. Press Command V, then Return, in its chat. The Mac couldn't type into Codex a moment ago, so the message is on your clipboard. Shall I try typing it again?"
        let pausedOn = "On the clipboard since I could not type them in press command V then return and it's chat so I think sometimes you don't understand so I ask you many times to talk"
        let heard = "\(pausedOn) you said"
        XCTAssertEqual(
            cutInWords(heard, pausedOn: pausedOn, spoken: spoken, spokeInQuiet: true),
            "I think sometimes you don't understand so I ask you many times to talk you said"
        )
        // Without words of theirs in the quiet, only what came from the pause on is theirs, as before.
        XCTAssertEqual(cutInWords(heard, pausedOn: pausedOn, spoken: spoken, spokeInQuiet: false), "to talk you said")
    }
}
