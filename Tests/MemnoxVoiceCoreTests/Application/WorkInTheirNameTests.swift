import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Something going out in the person's name in one of their tools: drawn on its card as that tool draws
/// it rather than put straight to Touch ID, sent only with the fingerprint for that proposal, and the
/// tools still to sign in to shown as icons with nothing to present.
final class WorkInTheirNameTests: XCTestCase {
    var link: ScriptedLink!
    var face: RecordingFace!
    var key: PersonKey!
    var conversation: Conversation!

    private let proposal = #"{"kind":"proposal","subject":"prp_work","agent":"agt_memnox-operator","summary":"As moise10r on GitHub: reply on 412","at":"2026-10-09T09:00:00Z","work":{"toolkit":"github","tool":"GITHUB_CREATE_A_REVIEW_COMMENT_FOR_A_PULL_REQUEST","kind":"comment","account":{"key":"42","handle":"moise10r","check":"matched"},"where":"memnox/runtime#412","body":"Fixed in the last push","fields":[{"name":"line","value":"88"}]}}"#

    override func setUp() {
        link = ScriptedLink()
        face = RecordingFace()
        key = PersonKey()
        conversation = Conversation(link: link, speaker: RecordingSpeaker(), key: key, face: face, owner: MemoryOwner(nil))
    }

    func testPutsWhatGoesOutOnItsToolsCardRatherThanStraightToTouchID() async throws {
        link.answers["ask"] = [try line(#"{"id":1,"ok":true,"chunk":{"kind":"done"}}"#)]
        await conversation.heard("reply on that review that it is fixed")
        let before = link.sent.filter { $0.method == "confirm" }.count
        await conversation.handle(try event(proposal))
        let (subject, work) = try XCTUnwrap(face.works.first)
        XCTAssertEqual(subject, "prp_work")
        XCTAssertEqual(work.draftKind, .comment)
        XCTAssertEqual(work.where, "memnox/runtime#412")
        XCTAssertEqual(work.account?.shown, "moise10r")
        XCTAssertEqual(work.account?.accountCheck, .matched)
        XCTAssertEqual(work.fields, [WorkField(name: "line", value: "88")])
        XCTAssertEqual(work.touchIDReason, "send this on GitHub as moise10r")
        XCTAssertEqual(key.signed, [])
        XCTAssertEqual(link.sent.filter { $0.method == "confirm" }.count, before)
    }

    func testDeclinesWhatNobodyAskedToSend() async throws {
        link.answers["confirm"] = [try line(#"{"id":1,"ok":true}"#)]
        await conversation.handle(try event(proposal))
        XCTAssertTrue(face.works.isEmpty)
        XCTAssertEqual(link.sent.last?.answer, "declined")
        XCTAssertEqual(key.signed, [])
    }

    func testSendsOnlyWithTheFingerprintForThatProposal() async throws {
        link.answers["confirm"] = [try line(#"{"id":1,"ok":true}"#)]
        let outcome = await conversation.answerDraft("prp_work", send: true, reason: "send this on GitHub as moise10r")
        XCTAssertEqual(outcome, .answered)
        XCTAssertEqual(key.signed, ["memnox-confirm:v1:prp_work:confirmed"])
        XCTAssertNotNil(link.sent.last?.signature)
    }

    func testShowsTheToolsStillToSignInToWithNothingToPresent() async throws {
        await conversation.handle(try event(#"{"kind":"show","subject":"dsp_1","agent":"agt_memnox-operator","summary":"Sign in to use","at":"2026-10-09T09:00:00Z","display":"signin","signIn":[{"toolkit":"linear","url":"https://consent/linear"},{"toolkit":"slack","url":"https://consent/slack","again":true}]}"#))
        let tools = try XCTUnwrap(face.signIns.first)
        XCTAssertEqual(tools.map(\.toolkit), ["linear", "slack"])
        XCTAssertEqual(tools.map(\.signsInAgain), [false, true])
        XCTAssertTrue(link.sent.isEmpty)
    }

    private let signedIn = #"{"kind":"notice","subject":"ntc_signed-in_1","agent":"memnox","summary":"Signed in to Gmail as me@home.test.","at":"2026-10-09T09:00:30Z","notice":"signed-in","signedIn":{"toolkit":"gmail","account":{"key":"me@home.test","handle":"me@home.test","check":"unverified"},"resume":"email Sara a summary"}}"#

    func testCarriesOnWithWhatWasAskedOnceTheSignInFinishes() async throws {
        let conversation = at("2026-10-09T09:00:40Z")
        await conversation.handle(try event(signedIn))
        let notice = try XCTUnwrap(face.signedIns.first)
        XCTAssertEqual(notice.resume, "email Sara a summary")
        XCTAssertNil(notice.confirm)
        XCTAssertTrue(notice.finished)
        // Shown and carried on with, never briefed as news.
        XCTAssertTrue(link.sent.isEmpty)
    }

    func testNeverCarriesOnWithAnOldRequestOnceTheConversationMovedOn() async throws {
        let late = at("2026-10-09T09:03:30Z")
        await late.handle(try event(signedIn))
        XCTAssertNil(try XCTUnwrap(face.signedIns.first).resume)
        link.answers["ask"] = [try line(#"{"id":1,"ok":true,"chunk":{"kind":"done"}}"#)]
        let spoken = at("2026-10-09T09:00:40Z")
        await spoken.heard("OK, I did")
        await spoken.handle(try event(signedIn))
        XCTAssertNil(face.signedIns.last?.resume)
    }

    func testThatsMeSaidAloudGoesToTouchIDLikeAnyProposal() async throws {
        link.answers["confirm"] = [try line(#"{"id":1,"ok":true,"outcome":"confirmed"}"#)]
        await conversation.heard("yes, me@home.test is me")
        await conversation.handle(try event(#"{"kind":"proposal","subject":"prp_mine","agent":"memnox","summary":"Is me@home.test on Gmail you?","at":"2026-10-09T09:00:30Z","claim":{"toolkit":"gmail","label":"me@home.test on Gmail"}}"#))
        XCTAssertEqual(key.signed, ["memnox-confirm:v1:prp_mine:confirmed"])
    }

    /// A conversation whose clock reads this moment, so how long ago a sign in finished is known.
    private func at(_ moment: String) -> Conversation {
        let clock = readInstant(moment) ?? Date()
        return Conversation(link: link, speaker: RecordingSpeaker(), key: key, face: face, owner: MemoryOwner(nil), now: { clock })
    }
}
