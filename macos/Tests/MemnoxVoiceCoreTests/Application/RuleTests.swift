import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// A rule said with the rule keys: sent whole with how it was asked, shown with where it could hold,
/// and put in force only where the person picked, with that pick signed.
final class RuleTests: XCTestCase {
    var link: ScriptedLink!
    var speaker: RecordingSpeaker!
    var face: RecordingFace!
    var key: PersonKey!
    var conversation: Conversation!

    private let proposal = #"{"kind":"proposal","subject":"prp_1","agent":"agt_memnox-operator","summary":"deny git.push on main","at":"2026-10-04T00:00:00Z","rule":{"summary":"deny git.push on main","effect":"deny","action":"git.push","branches":["main"],"reason":"nobody pushes to main by hand","scopes":[{"id":"machine","kind":"machine","label":"This Mac"},{"id":"repository-1","kind":"repository","label":"shop","folder":"/code/shop","suggested":true}]}}"#

    override func setUp() {
        link = ScriptedLink()
        speaker = RecordingSpeaker()
        face = RecordingFace()
        key = PersonKey()
        conversation = Conversation(link: link, speaker: speaker, key: key, face: face, owner: MemoryOwner(nil))
    }

    func testSendsTheRuleWholeWithTheIntentTheKeysChose() async throws {
        link.answers["ask"] = [try line(#"{"id":1,"ok":true,"chunk":{"kind":"done"}}"#)]
        await conversation.heard("never let any agent push to main", intent: .rule)
        let sent = try XCTUnwrap(link.sent.first)
        XCTAssertEqual(sent.said, "never let any agent push to main")
        XCTAssertEqual(sent.intent, "rule")
        await conversation.heard("what is claude doing")
        XCTAssertNil(link.sent.last?.intent)
    }

    func testPutsAProposedRuleOnTheCardRatherThanStraightToTouchID() async throws {
        link.answers["ask"] = [try line(#"{"id":1,"ok":true,"chunk":{"kind":"done"}}"#)]
        await conversation.heard("never let any agent push to main", intent: .rule)
        let before = link.sent.filter { $0.method == "confirm" }.count
        await conversation.handle(try event(proposal))
        let (subject, rule) = try XCTUnwrap(face.rules.first)
        XCTAssertEqual(subject, "prp_1")
        XCTAssertEqual(rule.ruleEffect, .deny)
        XCTAssertEqual(rule.suggestedScope?.label, "shop")
        XCTAssertEqual(key.signed, [])
        XCTAssertEqual(link.sent.filter { $0.method == "confirm" }.count, before)
    }

    func testDeclinesARuleNobodyAskedFor() async throws {
        link.answers["confirm"] = [try line(#"{"id":1,"ok":true}"#)]
        await conversation.handle(try event(proposal))
        XCTAssertTrue(face.rules.isEmpty)
        XCTAssertEqual(link.sent.last?.answer, "declined")
        XCTAssertEqual(key.signed, [])
    }

    func testSignsExactlyThePlacePickedAndSaysWhereItHolds() async throws {
        link.answers["confirm"] = [try line(#"{"id":1,"ok":true,"outcome":"confirmed"}"#)]
        let shop = RuleScope(id: "repository-1", kind: "repository", label: "shop", folder: "/code/shop")
        let outcome = await conversation.answerRule("prp_1", scope: shop, reason: "deny git push on main in shop")
        XCTAssertEqual(outcome, .answered)
        XCTAssertEqual(key.signed, ["memnox-confirm:v1:prp_1:repository-1"])
        let sent = try XCTUnwrap(link.sent.last)
        XCTAssertEqual(sent.method, "confirm")
        XCTAssertEqual(sent.answer, "repository-1")
        XCTAssertNotNil(sent.signature)
        XCTAssertEqual(speaker.said.last, "Very well. That rule is in force in shop.")
    }

    func testLeavingItOutGoesUnsignedAndCancellingTouchIDSendsNothing() async throws {
        link.answers["confirm"] = [try line(#"{"id":1,"ok":true}"#)]
        let left = await conversation.answerRule("prp_1", scope: nil, reason: "a rule")
        XCTAssertEqual(left, .answered)
        XCTAssertEqual(link.sent.last?.answer, "declined")
        XCTAssertNil(link.sent.last?.signature)
        XCTAssertEqual(key.signed, [])

        key.touches = false
        let before = link.sent.filter { $0.method == "confirm" }.count
        let machine = RuleScope(id: "machine", kind: "machine", label: "This Mac")
        let cancelled = await conversation.answerRule("prp_2", scope: machine, reason: "a rule")
        XCTAssertEqual(cancelled, .cancelled)
        XCTAssertEqual(link.sent.filter { $0.method == "confirm" }.count, before)
    }
}
