import XCTest

@testable import MemnoxVoiceCore

/// What was said, written the way the person would have typed it.
final class DictationTextTests: XCTestCase {
    func testDropsHesitationsAndClosesTheSentence() {
        XCTAssertEqual(cleanedDictation("so um I think we should uh ship it on friday"), "So I think we should ship it on friday.")
        XCTAssertEqual(cleanedDictation("Um, can you look at this?"), "Can you look at this?")
    }

    func testScratchThatTakesBackTheSentenceBefore() {
        XCTAssertEqual(
            cleanedDictation("Let's meet on Monday. Let's meet on Tuesday scratch that let's meet on Wednesday"),
            "Let's meet on Monday. Let's meet on Wednesday."
        )
    }

    func testKeepsBreaksSaidOutLoud() {
        XCTAssertEqual(cleanedDictation("hi Sam new paragraph the build is green new line thanks"), "Hi Sam\n\nThe build is green\nThanks.")
    }

    func testSpellsNamesTheirWay() {
        let dictionary = ["Postgres", "GitHub", "WakoAI"]
        XCTAssertEqual(
            cleanedDictation("move it to post gres and push to git hub for wako AI", dictionary: dictionary),
            "Move it to Postgres and push to GitHub for WakoAI."
        )
    }

    func testLaysOutItemsCountedOffAsAList() {
        XCTAssertEqual(
            cleanedDictation("I need three things first fix the login, second ship the docs and third tell Sam"),
            "I need three things:\n- Fix the login\n- Ship the docs\n- Tell Sam"
        )
        // One "first" in a sentence is not a list.
        XCTAssertEqual(cleanedDictation("the first build failed"), "The first build failed.")
    }

    func testWritesAChatMessageWithoutAFullStop() {
        XCTAssertEqual(cleanedDictation("on my way", style: DictationStyle(appName: "Messages")), "On my way")
        XCTAssertEqual(cleanedDictation("are you there?", style: DictationStyle(appName: "Slack")), "Are you there?")
        XCTAssertEqual(DictationStyle(appName: "Mail"), .written)
    }

    func testLeavesADotInsideAWordAlone() {
        XCTAssertEqual(cleanedDictation("open server.py in the editor"), "Open server.py in the editor.")
    }
}
