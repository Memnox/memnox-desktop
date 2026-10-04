import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// What reaches the notch: the question, the reply as written, and a drafted message with its signed Send.
final class ShowingTests: XCTestCase {
    var link: ScriptedLink!
    var face: RecordingFace!
    var key: PersonKey!
    var conversation: Conversation!

    override func setUp() {
        link = ScriptedLink()
        face = RecordingFace()
        key = PersonKey()
        conversation = Conversation(link: link, speaker: RecordingSpeaker(), key: key, face: face, owner: MemoryOwner(nil))
    }

    func testShowsTheQuestionAndTheReplyAsWrittenThenEndsIt() async throws {
        link.answers["ask"] = [
            try line(#"{"id":1,"ok":true,"chunk":{"kind":"text","text":"Two files:\n- `invoice.ts`\n"}}"#),
            try line(#"{"id":1,"ok":true,"chunk":{"kind":"text","text":"- `types.ts`"}}"#),
            try line(#"{"id":1,"ok":true,"chunk":{"kind":"done"}}"#),
        ]
        await conversation.heard("  what changed  ")
        XCTAssertEqual(face.asks, ["what changed"])
        // The markdown stays for the notch to lay out, unlike what is spoken.
        XCTAssertEqual(face.reply, "Two files:\n- `invoice.ts`\n- `types.ts`")
        XCTAssertEqual(face.replies, 1)
        XCTAssertEqual(face.failures, [nil])
    }

    func testEndsTheReplyEvenWhenMemnoxCannotBeReached() async {
        link.unreachable = true
        await conversation.heard("what is claude doing")
        XCTAssertEqual(face.asks, ["what is claude doing"])
        XCTAssertEqual(face.failures, ["Memnox could not be reached on this Mac"])
    }

    func testABriefNeverReachesTheAnswerCard() async throws {
        link.answers["brief"] = [
            try line(#"{"id":1,"ok":true,"chunk":{"kind":"text","text":"Claude finished the invoices."}}"#),
            try line(#"{"id":1,"ok":true,"chunk":{"kind":"done"}}"#),
        ]
        await conversation.handle(try event(#"{"kind":"notice","notice":"finished","subject":"ses_1","agent":"claude-code","summary":"Finished.","at":"2026-10-01T00:00:00Z"}"#))
        XCTAssertEqual(face.reply, "")
        XCTAssertTrue(face.asks.isEmpty)
    }

    func testPutsADraftInFrontOfThePersonWithNoPresenter() async throws {
        await conversation.handle(try event(#"{"kind":"show","subject":"drf_1","agent":"memnox","summary":"Reply to Sam","at":"2026-10-01T00:00:00Z","display":"draft","draft":{"service":"gmail","mode":"reply","to":["sam@example.com"],"subject":"Re: launch","body":"Hi Sam,\n\nHere is the link.","thread":1}}"#))
        let (subject, draft) = try XCTUnwrap(face.drafts.first)
        XCTAssertEqual(subject, "drf_1")
        XCTAssertEqual(draft.draftMode, .reply)
        XCTAssertEqual(draft.mailService, .gmail)
        XCTAssertEqual(draft.to, ["sam@example.com"])
        XCTAssertTrue(link.sent.isEmpty)
    }

    func testSendsADraftOnlyWithTheFingerprintForThatDraft() async throws {
        link.answers["confirm"] = [try line(#"{"id":1,"ok":true}"#)]
        let outcome = await conversation.answerDraft("drf_1", send: true, reason: "send the reply to Sam")
        XCTAssertEqual(outcome, .answered)
        XCTAssertEqual(key.signed, ["memnox-confirm:v1:drf_1:confirmed"])
        let sent = try XCTUnwrap(link.sent.last)
        XCTAssertEqual(sent.method, "confirm")
        XCTAssertEqual(sent.answer, "confirmed")
        XCTAssertNotNil(sent.signature)
    }

    func testClosingADraftGoesUnsignedAndCancellingTouchIDSendsNothing() async throws {
        link.answers["confirm"] = [try line(#"{"id":1,"ok":true}"#)]
        let closed = await conversation.answerDraft("drf_1", send: false, reason: "send it")
        XCTAssertEqual(closed, .answered)
        XCTAssertEqual(key.signed, [])
        XCTAssertEqual(link.sent.last?.answer, "declined")
        XCTAssertNil(link.sent.last?.signature)

        key.touches = false
        let before = link.sent.filter { $0.method == "confirm" }.count
        let cancelled = await conversation.answerDraft("drf_2", send: true, reason: "send it")
        XCTAssertEqual(cancelled, .cancelled)
        XCTAssertEqual(link.sent.filter { $0.method == "confirm" }.count, before)
    }
}
