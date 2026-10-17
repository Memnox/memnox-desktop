import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Handing the home's ready action over: the daemon proposes the rule, and only that proposal is treated as asked
/// for, so it waits on the rule card for a place and Touch ID while anything else unasked is still declined.
final class HandOverTests: XCTestCase {
    var link: ScriptedLink!
    var face: RecordingFace!
    var key: PersonKey!
    var conversation: Conversation!

    private func proposal(_ id: String) -> String {
        #"{"kind":"proposal","subject":"\#(id)","agent":"agt_memnox-operator","summary":"allow git.push","at":"2026-10-06T00:00:00Z","rule":{"summary":"allow git.push","effect":"allow","action":"git.push","reason":"said yes 14 times","scopes":[{"id":"machine","kind":"machine","label":"This Mac","suggested":true}]}}"#
    }

    override func setUp() {
        link = ScriptedLink()
        face = RecordingFace()
        key = PersonKey()
        conversation = Conversation(link: link, speaker: RecordingSpeaker(), key: key, face: face, owner: MemoryOwner(nil))
    }

    func testReadsTheHome() async throws {
        link.answers["home"] = [try line(#"{"id":1,"ok":true,"home":{"machine":"m","mode":"observe","waiting":1,"working":[],"today":{"actions":2,"asked":1,"allowed":1,"refused":0},"notCovered":{"unprotected":1,"dormant":0}}}"#)]
        let home = await conversation.home()
        XCTAssertEqual(home?.waiting, 1)
        XCTAssertEqual(link.sent.last?.method, "home")
    }

    func testAnOlderDaemonGivesNoHome() async throws {
        link.answers["home"] = [try line(#"{"id":1,"ok":true}"#)]
        let home = await conversation.home()
        XCTAssertNil(home)
        link.unreachable = true
        let away = await conversation.home()
        XCTAssertNil(away)
    }

    func testSendsTheActionAndPutsTheProposalItMadeOnTheRuleCard() async throws {
        link.answers["hand-over"] = [try line(#"{"id":1,"ok":true,"proposed":"prp_9"}"#)]
        let handed = await conversation.handOver("git.push")
        XCTAssertEqual(handed, .proposed("prp_9"))
        XCTAssertEqual(link.sent.last?.action, "git.push")
        await conversation.handle(try event(proposal("prp_9")))
        XCTAssertEqual(face.rules.map(\.0), ["prp_9"])
        XCTAssertFalse(link.sent.contains { $0.method == "confirm" })
        XCTAssertEqual(key.signed, [])
    }

    func testStillDeclinesAProposalTheHandOverDidNotMake() async throws {
        link.answers["hand-over"] = [try line(#"{"id":1,"ok":true,"proposed":"prp_9"}"#)]
        link.answers["confirm"] = [try line(#"{"id":2,"ok":true}"#)]
        _ = await conversation.handOver("git.push")
        await conversation.handle(try event(proposal("prp_other")))
        XCTAssertTrue(face.rules.isEmpty)
        XCTAssertEqual(link.sent.last?.method, "confirm")
        XCTAssertEqual(link.sent.last?.answer, "declined")
    }

    func testTheSameProposalIsTakenAsAskedOnlyOnce() async throws {
        link.answers["hand-over"] = [try line(#"{"id":1,"ok":true,"proposed":"prp_9"}"#)]
        link.answers["confirm"] = [try line(#"{"id":2,"ok":true}"#)]
        _ = await conversation.handOver("git.push")
        await conversation.handle(try event(proposal("prp_9")))
        await conversation.handle(try event(proposal("prp_9")))
        XCTAssertEqual(face.rules.count, 1)
        XCTAssertEqual(link.sent.last?.answer, "declined")
    }

    func testSaysWhyAHandOverWasRefused() async throws {
        link.answers["hand-over"] = [try line(#"{"id":1,"ok":false,"error":"git.push is not ready to hand over.","reason":"git.push is not ready to hand over."}"#)]
        let refused = await conversation.handOver("git.push")
        XCTAssertEqual(refused, .refused("git.push is not ready to hand over."))
        link.unreachable = true
        let away = await conversation.handOver("git.push")
        XCTAssertEqual(away, .unreachable)
    }

    func testAProposalArrivingBeforeTheAnswerWaitsForItRatherThanBeingDeclined() async throws {
        let slow = SlowHandOverLink(proposed: "prp_9")
        conversation = Conversation(link: slow, speaker: RecordingSpeaker(), key: key, face: face, owner: MemoryOwner(nil))
        let conversation = self.conversation!
        let handing = Task { await conversation.handOver("git.push") }
        while !slow.asked { await Task.yield() }
        await conversation.handle(try event(proposal("prp_9")))
        XCTAssertEqual(face.rules.map(\.0), ["prp_9"])
        XCTAssertFalse(slow.sent.contains { $0.method == "confirm" })
        let handed = await handing.value
        XCTAssertEqual(handed, .proposed("prp_9"))
    }
}

/// A daemon whose answer to hand-over comes a moment after the proposal event, as it can on two sockets.
private final class SlowHandOverLink: DaemonLink {
    let proposed: String
    var sent: [DaemonRequest] = []
    var asked = false
    init(proposed: String) { self.proposed = proposed }

    func stream(_ request: DaemonRequest) -> AsyncThrowingStream<DaemonResponse, Error> {
        sent.append(request)
        let handing = request.method == DaemonMethod.handOver.rawValue
        if handing { asked = true }
        let answer = #"{"id":\#(request.id),"ok":true,"proposed":"\#(proposed)"}"#
        return AsyncThrowingStream { continuation in
            Task {
                if handing {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    if let response = try? line(answer) { continuation.yield(response) }
                }
                continuation.finish()
            }
        }
    }
}
