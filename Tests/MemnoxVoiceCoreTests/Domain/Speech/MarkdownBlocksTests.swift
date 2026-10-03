import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// A card summary laid out as blocks the way it was written.
final class MarkdownBlocksTests: XCTestCase {
    func testLaysOutASummaryAsWritten() {
        let blocks = MarkdownBlock.parse("""
        ## Pushed the voice branch

        - Ran `pnpm test`, **all green**
        1. Committed six times
        ```
        git push origin feat/voice-answers
        ```
        It is waiting on you now.
        """)
        XCTAssertEqual(blocks, [
            .heading("Pushed the voice branch"),
            .bullet("Ran `pnpm test`, **all green**"),
            .bullet("Committed six times"),
            .code("git push origin feat/voice-answers"),
            .text("It is waiting on you now."),
        ])
    }

    func testKeepsAnUnclosedFenceAsCode() {
        XCTAssertEqual(MarkdownBlock.parse("```\nnpm test"), [.code("npm test")])
        XCTAssertEqual(MarkdownBlock.parse("#hashtag"), [.text("#hashtag")])
    }

    func testNeverCallsARunningLoginDone() {
        XCTAssertEqual(Conversation.afterConfirm(.confirmed, outcome: "started"),
                       "Very well. It is under way, and I will tell you if anything goes wrong.")
        XCTAssertEqual(Conversation.afterConfirm(.confirmed, outcome: "confirmed"), "Very well. It is done.")
        XCTAssertEqual(Conversation.afterConfirm(.declined, outcome: nil), "Very well. I have left it as it was.")
    }
}
