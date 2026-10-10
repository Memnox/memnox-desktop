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

    func testDoesWhatAPhoneAskedOnTheMacWithoutASound() async throws {
        let speaker = RecordingSpeaker()
        let chimes = RecordingChimes()
        let quiet = Conversation(link: link, speaker: speaker, key: key, face: face, owner: MemoryOwner(nil),
                                 presenter: PhoneHands(), chimes: chimes)
        // An unheard delivery and a hint would both be said for an ask made on this Mac.
        link.answers["delivered"] = [try line(#"{"id":1,"ok":false}"#)]
        let typing = try event(#"{"kind":"show","subject":"dsp_9","agent":"claude-code","summary":"run the tests","at":"2026-10-05T00:00:00Z","display":"type","host":{"app":"iTerm","tty":"ttys004"},"needsMac":true,"origin":{"deviceId":"dev_1"}}"#)
        await quiet.handle(typing)
        XCTAssertEqual(speaker.said, [])
        XCTAssertEqual(chimes.played, [])
        XCTAssertEqual(link.sent.map(\.method), ["delivered"])
        XCTAssertEqual(link.sent.first?.answer, "failed")
        XCTAssertTrue(face.shown.contains { $0.1 == "typing it in" })
        let folder = try event(#"{"kind":"show","subject":"dsp_10","agent":"memnox","summary":"finder","at":"2026-10-05T00:00:00Z","display":"folder","title":"finder","host":{"cwd":"shop"},"needsMac":true,"origin":{"deviceId":"dev_1"}}"#)
        await quiet.handle(folder)
        XCTAssertEqual(speaker.said, [])
    }

    func testStillSpeaksForTheSameActionAskedOnThisMac() async throws {
        let speaker = RecordingSpeaker()
        let local = Conversation(link: link, speaker: speaker, key: key, face: face, owner: MemoryOwner(nil), presenter: PhoneHands())
        link.answers["delivered"] = [try line(#"{"id":1,"ok":false}"#)]
        await local.handle(try event(#"{"kind":"show","subject":"dsp_9","agent":"claude-code","summary":"run the tests","at":"2026-10-05T00:00:00Z","display":"type","host":{"app":"iTerm","tty":"ttys004"},"needsMac":true}"#))
        XCTAssertFalse(speaker.said.isEmpty)
    }

    func testShowsADriveForItsGrantAndEndsItWhenTheNoticeSaysItStopped() async throws {
        let speaker = RecordingSpeaker()
        let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-05T10:00:00Z"))
        let driven = Conversation(link: link, speaker: speaker, key: key, face: face, owner: MemoryOwner(nil), now: { start })
        await driven.handle(try event(#"{"kind":"notice","subject":"drv_1","agent":"memnox","summary":"Sam's iPhone is driving this Mac","at":"2026-10-05T10:00:00Z","drivenBy":{"deviceId":"dev_1","name":"Sam's iPhone","until":"2026-10-05T10:15:00.000Z"}}"#))
        let until = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-05T10:15:00Z"))
        XCTAssertEqual(face.drives, [DriveGrant(deviceId: "dev_1", name: "Sam's iPhone", until: until)])
        await driven.handle(try event(#"{"kind":"notice","subject":"drv_1","agent":"memnox","summary":"Sam's iPhone stopped driving this Mac","at":"2026-10-05T10:04:00Z","drivenBy":{"deviceId":"dev_1","name":"Sam's iPhone"}}"#))
        XCTAssertEqual(face.drives.count, 2)
        XCTAssertNil(face.drives.last ?? nil)
        // Shown, never briefed or said, so a drive never wakes an empty room.
        XCTAssertTrue(link.sent.isEmpty)
        XCTAssertEqual(speaker.said, [])
    }

    func testShowsAPhonesTurnAsItStreamsAndNeverSpeaksIt() async throws {
        let speaker = RecordingSpeaker()
        let chimes = RecordingChimes()
        let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-05T10:00:00Z"))
        let watching = Conversation(link: link, speaker: speaker, key: key, face: face, owner: MemoryOwner(nil),
                                    chimes: chimes, now: { start })
        let turn = #"{"kind":"notice","subject":"ask_1","agent":"memnox","summary":"s","at":"2026-10-05T10:00:00Z","phoneTurn":"#
        await watching.handle(try event(turn + #"{"deviceId":"dev_1","name":"Sam's iPhone","said":"what changed"}}"#))
        await watching.handle(try event(turn + #"{"deviceId":"dev_1","name":"Sam's iPhone","answer":"Two files, "}}"#))
        await watching.handle(try event(turn + #"{"deviceId":"dev_1","name":"Sam's iPhone","answer":"both tests."}}"#))
        await watching.handle(try event(turn + #"{"deviceId":"dev_1","name":"Sam's iPhone","ended":true}}"#))
        XCTAssertEqual(face.phones.map(\.answer), ["", "Two files, ", "Two files, both tests.", "Two files, both tests."])
        XCTAssertEqual(face.phones.last?.said, "what changed")
        XCTAssertEqual(face.phones.last?.label, "From Sam's iPhone")
        XCTAssertEqual(face.phones.map(\.isAnswering), [true, true, true, false])
        // Shown only: nothing said, nothing chimed, nothing briefed, and the orb left as it was.
        XCTAssertEqual(speaker.said, [])
        XCTAssertEqual(chimes.played, [])
        XCTAssertTrue(link.sent.isEmpty)
        XCTAssertTrue(face.shown.isEmpty)
        XCTAssertTrue(face.asks.isEmpty)
        XCTAssertEqual(face.reply, "")
    }

    func testAHeldCallAPhoneHoldsIsNeitherBriefedNorSaidNorChimed() async throws {
        let speaker = RecordingSpeaker()
        let chimes = RecordingChimes()
        let quiet = Conversation(link: link, speaker: speaker, key: key, face: face, owner: MemoryOwner(nil), chimes: chimes)
        link.answers["brief"] = [try line(#"{"id":1,"ok":true,"chunk":{"kind":"text","text":"Claude wants to push."}}"#)]
        let held = try event(#"{"kind":"held","subject":"apr_1","agent":"claude-code","summary":"push to main","at":"t","heardOn":{"deviceId":"dev_1","name":"Sam's iPhone"}}"#)
        await quiet.handle(held)
        XCTAssertEqual(speaker.said, [])
        XCTAssertEqual(chimes.played, [])
        XCTAssertTrue(link.sent.isEmpty)
        // The Mac voice is not asking, so nothing waits on an answer said at the Mac.
        XCTAssertFalse(quiet.stillAsking("apr_1"))
        XCTAssertFalse(face.states.contains(.listening))
    }

    func testAProposalAPhoneHoldsIsLeftForItAndNeverDeclinedHere() async throws {
        let quiet = Conversation(link: link, speaker: RecordingSpeaker(), key: key, face: face, owner: MemoryOwner(nil))
        await quiet.handle(try event(#"{"kind":"proposal","subject":"prp_1","agent":"memnox","summary":"allow the push","at":"t","heardOn":{"deviceId":"dev_1","name":"iPhone"}}"#))
        XCTAssertTrue(link.sent.isEmpty)
        XCTAssertEqual(key.signed, [])
    }

    func testANoticeOrAPauseAPhoneHoldsIsNotSaid() async throws {
        let speaker = RecordingSpeaker()
        let quiet = Conversation(link: link, speaker: speaker, key: key, face: face, owner: MemoryOwner(nil))
        await quiet.handle(try event(#"{"kind":"notice","notice":"question","subject":"ntc_1","agent":"claude-code","summary":"Which one?","at":"t","heardOn":{"deviceId":"dev_1","name":"iPhone"}}"#))
        await quiet.handle(try event(#"{"kind":"paused","subject":"ses_1","agent":"claude-code","summary":"looping","at":"t","origin":{"deviceId":"dev_1"}}"#))
        XCTAssertEqual(speaker.said, [])
        XCTAssertTrue(link.sent.isEmpty)
    }

    func testAShowWhileAPhoneHoldsTheVoiceIsDoneWithoutASound() async throws {
        let speaker = RecordingSpeaker()
        let chimes = RecordingChimes()
        let quiet = Conversation(link: link, speaker: speaker, key: key, face: face, owner: MemoryOwner(nil),
                                 presenter: PhoneHands(), chimes: chimes)
        link.answers["delivered"] = [try line(#"{"id":1,"ok":false}"#)]
        await quiet.handle(try event(#"{"kind":"show","subject":"dsp_9","agent":"claude-code","summary":"run the tests","at":"t","display":"type","host":{"app":"iTerm","tty":"ttys004"},"heardOn":{"deviceId":"dev_1","name":"iPhone"}}"#))
        XCTAssertEqual(speaker.said, [])
        XCTAssertEqual(chimes.played, [])
        XCTAssertEqual(link.sent.map(\.method), ["delivered"])
    }

    func testTellsTheFaceWhichPhoneHoldsTheVoiceAndWhenItIsBackWithoutASound() async throws {
        let speaker = RecordingSpeaker()
        let chimes = RecordingChimes()
        let watching = Conversation(link: link, speaker: speaker, key: key, face: face, owner: MemoryOwner(nil), chimes: chimes)
        let moved = #"{"kind":"notice","subject":"voc_1","agent":"memnox","summary":"s","at":"t","voiceOn":"#
        await watching.handle(try event(moved + #"{"deviceId":"dev_1","name":"Sam's iPhone","holding":true}}"#))
        await watching.handle(try event(moved + #"{"deviceId":"dev_1","name":"Sam's iPhone","holding":false}}"#))
        XCTAssertEqual(face.voices, [PhoneVoice(deviceId: "dev_1", name: "Sam's iPhone"), nil])
        XCTAssertEqual(speaker.said, [])
        XCTAssertEqual(chimes.played, [])
        XCTAssertTrue(link.sent.isEmpty)
    }

    func testAHeldCallWithNoPhoneMarkIsStillBriefedAndAsked() async throws {
        let chimes = RecordingChimes()
        let local = Conversation(link: link, speaker: RecordingSpeaker(), key: key, face: face, owner: MemoryOwner(nil), chimes: chimes)
        link.answers["brief"] = [
            try line(#"{"id":1,"ok":true,"chunk":{"kind":"text","text":"Claude wants to push."}}"#),
            try line(#"{"id":1,"ok":true,"chunk":{"kind":"done"}}"#),
        ]
        await local.handle(try event(#"{"kind":"held","subject":"apr_1","agent":"claude-code","summary":"push to main","at":"t"}"#))
        XCTAssertEqual(link.sent.map(\.method), ["brief"])
        XCTAssertEqual(chimes.played, [.held])
        XCTAssertTrue(local.stillAsking("apr_1"))
    }
}

/// Hands that never land, so every failure line a local ask would hear is there to be left unsaid.
private final class PhoneHands: Presenter, @unchecked Sendable {
    func live(session: String, host: DisplayHost?) async {}
    func open(_ host: DisplayHost?) async -> Bool { false }
    func type(_ text: String, into host: DisplayHost?, request: String) async -> Typed { Typed(.failed, "no tab", hint: .allowTyping) }
    func focus(session: String, host: DisplayHost?) async -> Typed { Typed(.failed) }
    func card(_ card: SummaryCard) async {}
    func prefill(_ text: String, session: String, host: DisplayHost?) async -> Typed { Typed(.failed) }
    func launch(_ command: String, in folder: String?) async -> Typed { Typed(.failed) }
    func walk(_ walk: WalkCard) async {}
    func scan(_ agents: [AgentNode], title: String) async {}
    func trace(_ trace: TraceData, title: String) async {}
    func board(title: String) async {}
    func openFolder(_ path: String, in opener: FolderOpener) async -> Bool { false }
}
