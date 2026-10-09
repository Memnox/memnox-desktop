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
        let spoken = "Hi Moïse, I am Memnox. Press Option Space whenever you want me."
        XCTAssertNil(afterWakeWord("Hi Moise I am Memnox press option space whenever you want me", spoken: spoken))
        // The person calling it after its own sentence still wakes it.
        XCTAssertEqual(afterWakeWord("whenever you want me Memnox what changed today", spoken: spoken), "what changed today")
        XCTAssertEqual(afterWakeWord("Memnox are they done", spoken: ""), "are they done")
    }
}
