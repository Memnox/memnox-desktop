import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Hearing its name, however the recognizer spells it, and what follows it.
final class WakeWordTests: XCTestCase {
    func testWakesOnItsNameAndHandsOnWhatFollowed() {
        XCTAssertEqual(afterWakeWord("Memnox"), "")
        XCTAssertEqual(afterWakeWord("Hey Memnox, what's going on?"), "what's going on?")
        XCTAssertEqual(afterWakeWord("mem nox are they done"), "are they done")
        XCTAssertEqual(afterWakeWord("Men knocks."), "")
        XCTAssertNil(afterWakeWord("what are my agents doing"))
        XCTAssertNil(afterWakeWord("the memo knocks twice"))
        XCTAssertEqual(afterWakeWord("Ma'am Knox"), "")
        XCTAssertEqual(afterWakeWord("ma'am knox what changed"), "what changed")
    }

    func testWakesOnTheWaysItsNameWasMisheard() {
        XCTAssertEqual(afterWakeWord("Emma Knox, can you start a session?"), "can you start a session?")
        XCTAssertEqual(afterWakeWord("MM Nox. Can you open up all my sessions?"), "Can you open up all my sessions?")
        XCTAssertNotNil(afterWakeWord("Minnox"))
    }

    func testWakesOnItsNameSaidTheirOwnWay() {
        // Heard from people who say it their own way: the first half and the second run together.
        XCTAssertEqual(afterWakeWord("Mennix, what changed?"), "what changed?")
        XCTAssertEqual(afterWakeWord("mim nax are they done"), "are they done")
        XCTAssertEqual(afterWakeWord("Memnex"), "")
        XCTAssertEqual(afterWakeWord("Emma nucks open my sessions"), "open my sessions")
        // Ordinary words that only sound near it never wake it.
        XCTAssertNil(afterWakeWord("a man nicks the bike"))
        XCTAssertNil(afterWakeWord("my mom knocks first"))
        XCTAssertNil(afterWakeWord("the next ten minutes"))
    }

    func testTakesItsNameSaidTwiceAsOneCall() {
        XCTAssertTrue(nameAlone("Memnox Manox"))
        XCTAssertEqual(withoutLeadingName("Memnox Manox, what changed?"), "what changed?")
        XCTAssertEqual(afterWakeWord("Mnox"), "")
    }

    func testHearsItsNameCutToItsEndOnlyAtEitherEnd() {
        XCTAssertEqual(withoutLeadingName("OK Knox can you please close all these panels"), "can you please close all these panels")
        XCTAssertEqual(withoutLeadingName("OK ma'am Knox, can you commit?"), "can you commit?")
        XCTAssertEqual(withoutLeadingName("Hey Mem nox, which one is working?"), "which one is working?")
        XCTAssertNil(afterWakeWord("the gold sits in Fort Knox these days"))
        XCTAssertNil(afterWakeWord("move it to the Knox folder"))
    }

    func testTakesItsNameOffTheEndWhenTheyCalledItThere() {
        XCTAssertEqual(
            withoutTrailingName("OK, so why are you taking longer to reply? memnox memnox"),
            "OK, so why are you taking longer to reply?"
        )
        XCTAssertEqual(withoutTrailingName("Can you Knox? Knox?"), "Can you Knox?")
        XCTAssertEqual(withoutTrailingName("commit that, ma'am Knox."), "commit that")
        XCTAssertEqual(withoutTrailingName("are you there memnox memnox"), "are you there")
        // Named as a place, the name is part of what they asked.
        XCTAssertEqual(withoutTrailingName("start a session in Memnox"), "start a session in Memnox")
        XCTAssertEqual(withoutTrailingName("start a session in Memnox. Memnox."), "start a session in Memnox.")
        XCTAssertEqual(withoutTrailingName("Memnox memnox"), "Memnox memnox")
        XCTAssertFalse(nameAlone("Do it. Knox."))
    }

    func testTakesItsNameAtTheEndOfAQuestionAsPartOfTheQuestion() {
        XCTAssertTrue(nameAlone("Memnox"))
        XCTAssertTrue(nameAlone("Hey Memnox."))
        XCTAssertFalse(nameAlone("Can you open Codex and start a new session within Memnox?"))
    }

    func testTakesItsNameOffTheFrontButNotFromTheMiddle() {
        XCTAssertEqual(withoutLeadingName("Mem Nox. I've closed it."), "I've closed it.")
        XCTAssertEqual(withoutLeadingName("Hey Memnox, which one is working?"), "which one is working?")
        XCTAssertEqual(withoutLeadingName("is the Memnox runtime on main"), "is the Memnox runtime on main")
        XCTAssertEqual(withoutLeadingName("Memnox"), "Memnox")
    }

    func testDoesNotWakeOnItsOwnGreeting() {
        let spoken = "Hi Maya, I am Memnox. Press Option Space whenever you want me."
        XCTAssertNil(afterWakeWord("Hi Maya I am Memnox press option space whenever you want me", spoken: spoken))
        // The person calling it after its own sentence still wakes it.
        XCTAssertEqual(afterWakeWord("whenever you want me Memnox what changed today", spoken: spoken), "what changed today")
        XCTAssertEqual(afterWakeWord("Memnox are they done", spoken: ""), "are they done")
    }
}
