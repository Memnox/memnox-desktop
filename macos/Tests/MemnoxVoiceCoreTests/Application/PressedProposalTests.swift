import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// A press in this app's own window that the daemon answers with a proposal: only that proposal is taken as asked
/// for and put to the key, while one nobody pressed or spoke for is still declined.
final class PressedProposalTests: XCTestCase {
    var link: ScriptedLink!
    var key: PersonKey!
    var clock: Date!
    var conversation: Conversation!

    private func proposal(_ id: String) -> String {
        #"{"kind":"proposal","subject":"\#(id)","agent":"agt_memnox-operator","summary":"keep GITHUB_TOKEN","at":"2026-10-06T00:00:00Z"}"#
    }

    override func setUp() {
        link = ScriptedLink()
        key = PersonKey()
        clock = Date(timeIntervalSince1970: 1_800_000_000)
        link.answers["confirm"] = [try! line(#"{"id":9,"ok":true}"#)]
        conversation = Conversation(link: link, speaker: RecordingSpeaker(), key: key, face: RecordingFace(),
                                    owner: MemoryOwner(nil), now: { [unowned self] in self.clock })
    }

    private func declined() -> Bool {
        link.sent.contains { $0.method == "confirm" && $0.answer == ProposalAnswer.declined.rawValue }
    }

    func testAProposalAWindowPressRaisedGoesToTheKey() async throws {
        let window = ScriptedLink()
        window.answers["mcp-secret-set"] = [try line(#"{"id":1,"ok":true,"proposed":"prp_secret"}"#)]
        let hub = McpHub(link: PressingLink(link: window, presses: conversation.presses), ids: RequestIds())
        let outcome = await hub.setSecret("GITHUB_TOKEN", value: "v")
        XCTAssertEqual(outcome, .proposed("prp_secret"))

        await conversation.handle(try event(proposal("prp_secret")))

        XCTAssertFalse(declined())
        XCTAssertEqual(key.signed.count, 1)
        XCTAssertTrue(key.signed[0].hasPrefix("memnox-confirm:v1:prp_secret:"))
    }

    func testEveryProposalAnAnswerNamesIsPressedFor() async throws {
        let window = ScriptedLink()
        window.answers["rule-pack-import"] = [try line(#"{"id":1,"ok":true,"packProposed":["prp_a","prp_b"]}"#)]
        let pressing = PressingLink(link: window, presses: conversation.presses)
        _ = try await pressing.request(DaemonRequest(id: 1, method: .rulePackImport))

        await conversation.handle(try event(proposal("prp_b")))

        XCTAssertFalse(declined())
        XCTAssertTrue(key.signed.contains { $0.hasPrefix("memnox-confirm:v1:prp_b:") })
    }

    func testAProposalNobodyPressedIsStillDeclined() async throws {
        let window = ScriptedLink()
        window.answers["mcp-secret-set"] = [try line(#"{"id":1,"ok":true,"proposed":"prp_secret"}"#)]
        let hub = McpHub(link: PressingLink(link: window, presses: conversation.presses), ids: RequestIds())
        _ = await hub.setSecret("GITHUB_TOKEN", value: "v")

        await conversation.handle(try event(proposal("prp_other")))

        XCTAssertTrue(declined())
        XCTAssertEqual(key.signed, [])
    }

    func testAPressAnsweredAfterTheEventIsStillHonoured() async throws {
        let slow = SlowWindowLink(proposed: "prp_late")
        let pressing = PressingLink(link: slow, presses: conversation.presses)
        let pressed = Task { try await pressing.request(DaemonRequest(id: 1, method: .mcpSecretSet)) }
        while !slow.asked { await Task.yield() }

        await conversation.handle(try event(proposal("prp_late")))

        XCTAssertFalse(declined())
        XCTAssertTrue(key.signed.contains { $0.hasPrefix("memnox-confirm:v1:prp_late:") })
        _ = try await pressed.value
    }

    func testAPressedProposalThatWaitedTooLongIsDeclined() async throws {
        let window = ScriptedLink()
        window.answers["mcp-secret-set"] = [try line(#"{"id":1,"ok":true,"proposed":"prp_old"}"#)]
        _ = try await PressingLink(link: window, presses: conversation.presses).request(DaemonRequest(id: 1, method: .mcpSecretSet))
        clock = clock.addingTimeInterval(Presses.lifetime + 1)

        await conversation.handle(try event(proposal("prp_old")))

        XCTAssertTrue(declined())
        XCTAssertEqual(key.signed, [])
    }

    func testOnlyTheNewestPressesAreKept() async throws {
        let presses = Presses(now: { [unowned self] in self.clock })
        presses.raised(["prp_first"])
        clock = clock.addingTimeInterval(1)
        presses.raised((0..<Presses.most).map { "prp_\($0)" })
        let first = await presses.take("prp_first")
        let last = await presses.take("prp_\(Presses.most - 1)")
        XCTAssertFalse(first)
        XCTAssertTrue(last)
    }
}

/// A daemon whose answer to a window's press comes a moment after the proposal event, as it can on two sockets.
private final class SlowWindowLink: DaemonLink {
    let proposed: String
    var asked = false
    init(proposed: String) { self.proposed = proposed }

    func stream(_ request: DaemonRequest) -> AsyncThrowingStream<DaemonResponse, Error> {
        asked = true
        let answer = #"{"id":\#(request.id),"ok":true,"proposed":"\#(proposed)"}"#
        return AsyncThrowingStream { continuation in
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if let response = try? line(answer) { continuation.yield(response) }
                continuation.finish()
            }
        }
    }
}
