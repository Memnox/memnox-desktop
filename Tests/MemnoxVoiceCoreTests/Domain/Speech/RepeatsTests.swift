import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Saying each thing once in a reply, however the brain tells it around a tool.
final class RepeatsTests: XCTestCase {
    func testLetsGoASentenceToldAgainOrNearlyAgain() {
        XCTAssertTrue(repeats("I will tell you when Codex finishes.", saidAlready: ["I will tell you when Codex finishes."]))
        XCTAssertTrue(repeats(
            "I can start Codex in memnox macos to review what Claude Code is doing now.",
            saidAlready: ["I can start Codex to review what Claude Code is doing now."]
        ))
    }

    func testKeepsWhatIsNewEvenWhenItSharesAFewWords() {
        XCTAssertFalse(repeats("Would you like me to go ahead?", saidAlready: ["Shall I begin?"]))
        XCTAssertFalse(repeats("Two are working at the moment.", saidAlready: ["All five sessions are now on your screen."]))
        XCTAssertFalse(repeats("Yes.", saidAlready: []))
    }
}
