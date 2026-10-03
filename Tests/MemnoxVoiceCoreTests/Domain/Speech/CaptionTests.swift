import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// The one line under the orb, and tool names as a person reads them.
final class CaptionTests: XCTestCase {
    func testTheCaptionIsCutAtAWord() {
        XCTAssertEqual(caption("short"), "short")
        XCTAssertEqual(
            caption("claude-code wants to push to main on the shop repository", limit: 30),
            "claude-code wants to push to…"
        )
    }

    func testNamesAToolTheWayAPersonReadsIt() {
        XCTAssertEqual(toolWord("mcp__memnox-operator__sessions"), "sessions")
        XCTAssertEqual(toolWord(nil), "the machine")
    }
}
