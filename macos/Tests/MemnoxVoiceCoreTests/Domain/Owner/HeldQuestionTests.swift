import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// A held call put the way a colleague would ask it.
final class HeldQuestionTests: XCTestCase {
    func testAsksTheWayAColleagueWould() throws {
        let held = try event(#"{"kind":"held","subject":"apr_1","agent":"claude-code","summary":"claude-code wants to git.push main","at":"t","agentName":"Claude","what":"push main","why":"Pushing to main needs a person.","task":"add order cancellation","place":"shop"}"#)
        XCTAssertEqual(
            heldQuestion(owner: "Maya", event: held),
            "Maya, Claude in shop, working on add order cancellation, wants to push main. Pushing to main needs a person. Allow it, or deny?"
        )
    }

    func testSpeaksOfTheLastFollowUpRatherThanCallingItTheMission() throws {
        let held = try event(#"{"kind":"held","subject":"apr_1","agent":"claude-code","summary":"s","at":"t","agentName":"Claude Code","what":"delete /private/tmp/claude-501/scratchpad/b/src","task":"review the current git history","lastAsk":"go ahead","place":"memnox-macos"}"#)
        XCTAssertEqual(
            heldQuestion(owner: nil, event: held),
            "Claude Code in memnox-macos, after you said go ahead, wants to delete src. Allow it, or deny?"
        )
    }

    func testSaysOnlyWhatItKnows() throws {
        let held = try event(#"{"kind":"held","subject":"apr_1","agent":"codex","summary":"codex wants to rm build","at":"t","why":"deletes need a person"}"#)
        XCTAssertEqual(
            heldQuestion(owner: nil, event: held),
            "codex wants to rm build. deletes need a person. Allow it, or deny?"
        )
    }

    func testSaysTheCallsOneLabelInPlaceOfTheBareAgent() throws {
        let held = try event(#"{"kind":"held","subject":"apr_1","agent":"claude-code","summary":"s","at":"t","agentName":"Claude","what":"push main","place":"shop"}"#)
        XCTAssertEqual(
            heldQuestion(owner: nil, event: held, label: "Claude on your Mac"),
            "Claude on your Mac in shop wants to push main. Allow it, or deny?"
        )
    }

    func testATeamCallIsAskedWithItsLabelAndEndsOnTheQuestionEveryCallEndsOn() throws {
        let call = try JSONDecoder().decode(WorkspaceHeldCall.self, from: Data(heldJSON(ownerName: "Ana").utf8))
        XCTAssertEqual(
            teamQuestion(owner: "Maya", call: call),
            "Maya, codex on build-box, from Ana's team is waiting on you. Codex wants to push to main. Pushes to main are held. Allow it, or deny?"
        )
    }

    func testSuggestsTheFirstName() {
        XCTAssertEqual(suggestedName(fullName: "Maya Okafor"), "Maya")
        XCTAssertEqual(suggestedName(fullName: "Cher"), "Cher")
    }

    func testSaysOnlyTheLastPartOfAPath() {
        XCTAssertEqual(
            withShortPaths("delete /private/tmp/claude-501/-Users-maya-Documents/scratchpad/b/src."),
            "delete src."
        )
        XCTAssertEqual(
            withShortPaths("Audio.swift is outside /Users/maya/Documents/Memnox-saas/memnox-macos, where it works"),
            "Audio.swift is outside memnox-macos, where it works"
        )
        XCTAssertEqual(withShortPaths("read and/or write ~/notes.md or /src"), "read and/or write notes.md or /src")
    }
}
