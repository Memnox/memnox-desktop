import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Streamed text cut into the sentences the voice speaks.
final class SentenceSplitterTests: XCTestCase {
    func testSpeaksWholeSentencesAsTheyArrive() {
        var splitter = SentenceSplitter()
        XCTAssertEqual(splitter.push("Two sessions are "), [])
        XCTAssertEqual(splitter.push("open. Which one? Checkout"), ["Two sessions are open."])
        XCTAssertEqual(splitter.push(" or api"), [])
        // "Which one?" is too short to say alone, so it runs on into what follows it.
        XCTAssertEqual(splitter.flush(), "Which one? Checkout or api")
    }

    func testSaysAShortSentenceTogetherWithTheNext() {
        var splitter = SentenceSplitter()
        XCTAssertEqual(splitter.push("Proposed. It needs your Touch ID on the Mac. "), ["Proposed. It needs your Touch ID on the Mac."])
    }

    func testANumberIsNotTheEndOfASentence() {
        var splitter = SentenceSplitter()
        XCTAssertEqual(splitter.push("It spent 3.5 minutes. Then"), ["It spent 3.5 minutes."])
    }

    func testTheFirstPieceOfAReplyIsSaidAtItsFirstClause() {
        var splitter = SentenceSplitter()
        // A courtesy too short to say alone waits, then the first clause long enough goes at once.
        XCTAssertEqual(splitter.push("Very well, sir. I have opened the Claude session, "), ["Very well, sir. I have opened the Claude session,"])
        // After that only whole sentences, since the rest streams in while the first is spoken.
        XCTAssertEqual(splitter.push("and the tests pass, which is the point. Shall"), ["and the tests pass, which is the point."])
        XCTAssertEqual(splitter.flush(), "Shall")
        // A number's comma has no space after it, so it never ends a piece.
        XCTAssertEqual(splitter.push("It changed 1,200 lines in two files"), [])
    }
}
