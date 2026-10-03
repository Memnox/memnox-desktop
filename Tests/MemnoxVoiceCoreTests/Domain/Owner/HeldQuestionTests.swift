import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// A held call put the way a colleague would ask it.
final class HeldQuestionTests: XCTestCase {
    func testAsksTheWayAColleagueWould() throws {
        let held = try event(#"{"kind":"held","subject":"apr_1","agent":"claude-code","summary":"claude-code wants to git.push main","at":"t","agentName":"Claude","what":"push main","why":"Pushing to main needs a person.","task":"add order cancellation","place":"shop"}"#)
        XCTAssertEqual(
            heldQuestion(owner: "Moise", event: held),
            "Moise, Claude in shop, working on add order cancellation, wants to push main. Pushing to main needs a person. Allow it, or deny?"
        )
    }

    func testSaysOnlyWhatItKnows() throws {
        let held = try event(#"{"kind":"held","subject":"apr_1","agent":"codex","summary":"codex wants to rm build","at":"t","why":"deletes need a person"}"#)
        XCTAssertEqual(
            heldQuestion(owner: nil, event: held),
            "codex wants to rm build. deletes need a person. Allow it, or deny?"
        )
    }

    func testSuggestsTheFirstName() {
        XCTAssertEqual(suggestedName(fullName: "Moise Rushanika"), "Moise")
        XCTAssertEqual(suggestedName(fullName: "Cher"), "Cher")
    }
}
