import XCTest

@testable import MemnoxVoiceCore

/// Words typed while the person is still speaking, and only the part that changed taken back.
final class LiveDictationTests: XCTestCase {
    func testTheWordStillBeingSaidWaits() {
        XCTAssertEqual(liveDictation("send the report to", final: false), "Send the report")
        XCTAssertEqual(liveDictation("send the report to ", final: false), "Send the report to")
        XCTAssertEqual(liveDictation("send", final: false), "")
    }

    func testEveryWordGoesInOnceFinal() {
        XCTAssertEqual(liveDictation("send the report to Sam", final: true), "Send the report to Sam")
    }

    func testHesitationsNeverReachTheField() {
        XCTAssertEqual(liveDictation("um so uh we ship today", final: true), "So we ship today")
    }

    func testNoListOrClosingStopWhileSpeaking() {
        let live = liveDictation("first buy milk second call Sam third ship it", final: true)
        XCTAssertFalse(live.contains("\n- "))
        XCTAssertFalse(live.hasSuffix("."))
    }

    func testTheirSpellingHoldsLive() {
        XCTAssertEqual(liveDictation("ask post gres about it", final: true, dictionary: ["Postgres"]), "Ask Postgres about it")
    }

    func testOnlyTheChangedEndIsRetyped() {
        let revision = liveRevision(from: "Send the repo", to: "Send the report")
        XCTAssertEqual(revision.kept, "Send the repo")
        XCTAssertEqual(revision.removed, "")
        XCTAssertEqual(revision.added, "rt")
    }

    func testARevisedWordIsTakenBackFromWhereItDiffers() {
        let revision = liveRevision(from: "We need to sea it", to: "We need to see it")
        XCTAssertEqual(revision.kept, "We need to se")
        XCTAssertEqual(revision.removed, "a it")
        XCTAssertEqual(revision.added, "e it")
    }

    func testNothingToDoWhenTheSame() {
        XCTAssertTrue(liveRevision(from: "Hello", to: "Hello").isEmpty)
    }

    func testAccentsAreNeverSplit() {
        let revision = liveRevision(from: "Zoëy", to: "Zoey")
        XCTAssertEqual(revision.removed, "ëy")
        XCTAssertEqual(revision.added, "ey")
    }

    func testCursorHintsKeepNamesAndCodes() {
        let hints = cursorHints(before: "Thanks for the update on ORB-12, I asked Pacilinja and the Postgres team.", after: "The deploy is fine")
        XCTAssertEqual(hints, ["ORB-12", "Pacilinja", "Postgres"])
    }

    func testCursorHintsAreCapped() {
        let many = (1...40).map { "Name\($0)" }.joined(separator: " ")
        XCTAssertEqual(cursorHints(before: many, after: nil).count, cursorHintLimit)
    }
}
