import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// A yes to a held call bound to the exact call shown, mirroring the v4 half of shared/tauri-core/test/held-calls.test.ts.
final class HeldDigestTests: XCTestCase {
    var link: ScriptedLink!
    var key: PersonKey!
    var conversation: Conversation!
    private let digest = "e1b4"

    override func setUp() {
        link = ScriptedLink()
        key = PersonKey()
        conversation = Conversation(link: link, speaker: RecordingSpeaker(), key: key, face: RecordingFace(), owner: MemoryOwner("Maya"))
    }

    func testSignsTheV4WordsOverTheCallItWasShownAndSendsItsDigest() async throws {
        link.answers["confirm"] = [try line(#"{"id":1,"ok":true,"outcome":"once"}"#)]
        let outcome = await conversation.answerHeld("hld_1", .once, reason: "push to main", actionDigest: digest)

        XCTAssertEqual(outcome, .answered)
        XCTAssertEqual(key.signed, ["memnox-confirm:v4:hld_1:once:e1b4"])
        let sent = try XCTUnwrap(link.sent.last)
        XCTAssertEqual(sent.actionDigest, digest)
        XCTAssertNotNil(sent.signature)
    }

    func testSendsTheDigestWithADenyTooUnsignedSoTheDaemonKnowsWhichCallWasRefused() async throws {
        link.answers["confirm"] = [try line(#"{"id":1,"ok":true,"outcome":"deny"}"#)]
        _ = await conversation.answerHeld("hld_1", .deny, reason: "push to main", actionDigest: digest)

        XCTAssertEqual(key.signed, [])
        let sent = try XCTUnwrap(link.sent.last)
        XCTAssertEqual(sent.answer, "deny")
        XCTAssertEqual(sent.actionDigest, digest)
        XCTAssertNil(sent.signature)
    }

    func testSendsTheDigestUnsignedForACallInsideItsSession() async throws {
        link.answers["confirm"] = [try line(#"{"id":1,"ok":true,"outcome":"once"}"#)]
        _ = await conversation.answerHeld("hld_1", .once, reason: "edit a file", touchID: false, actionDigest: digest)

        XCTAssertEqual(key.signed, [])
        XCTAssertEqual(link.sent.last?.actionDigest, digest)
    }

    func testFallsBackToTheOlderWordsForADaemonThatGaveNoDigest() async throws {
        link.answers["confirm"] = [try line(#"{"id":1,"ok":true,"outcome":"once"}"#)]
        _ = await conversation.answerHeld("hld_1", .session, reason: "push to main")

        XCTAssertEqual(key.signed, ["memnox-confirm:v1:hld_1:session"])
        XCTAssertNil(link.sent.last?.actionDigest)
    }

    func testReadsTheDigestOffAHeldEventAndAWaitingList() throws {
        let held = try event(#"{"kind":"held","subject":"hld_1","agent":"claude-code","summary":"push","at":"t","actionDigest":"e1b4"}"#)
        XCTAssertEqual(held.actionDigest, digest)
        let waiting = try line(#"{"id":1,"ok":true,"waiting":[{"kind":"held","subject":"hld_2","agent":"a","summary":"s","at":"t","actionDigest":"ff00"}]}"#)
        XCTAssertEqual(waiting.waiting?.first?.actionDigest, "ff00")
    }
}
