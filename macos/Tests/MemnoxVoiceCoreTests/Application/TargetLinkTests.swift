import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// The machine the voice talks to: a server is sent only what it may answer from afar, every yes to it is
/// signed, and nothing acts on a server's session from this Mac.
final class TargetLinkTests: XCTestCase {
    var local: ScriptedLink!
    var remote: ScriptedLink!
    var target: TargetLink!
    private let server = MachineTarget.server(machineId: "mch_vps", deviceId: "dev_mac", name: "hostinger-vps")

    override func setUp() {
        local = ScriptedLink()
        remote = ScriptedLink()
        target = TargetLink(local: local)
    }

    func testThisMacIsTheTargetUntilAServerIsPicked() async throws {
        XCTAssertEqual(target.target, .thisMac)
        _ = try? await target.request(DaemonRequest(id: 1, method: .registerKey))
        XCTAssertEqual(local.sent.map(\.method), ["register-key"])
    }

    func testAServerIsNeverSentWhatBelongsToThisMac() async throws {
        target.choose(server, link: remote)
        let localOnly: [DaemonMethod] = [.registerKey, .vocabulary, .delivered, .seen, .learnWords, .pairBegin, .pairPending,
                                         .pairAccept, .pairDecline, .devicesList, .deviceRevoke, .deviceGrant, .deviceUngrant,
                                         .locate, .chooseVoiceAgent]
        for (index, method) in localOnly.enumerated() {
            do {
                _ = try await target.request(DaemonRequest(id: index + 1, method: method))
                XCTFail("\(method.rawValue) reached a server")
            } catch {
                XCTAssertEqual(error as? ProtocolError, .refused(TargetLink.onlyHere(method.rawValue)))
            }
        }
        XCTAssertEqual(remote.sent, [])
        XCTAssertEqual(local.sent, [])
    }

    func testAServerIsAskedWhatItsAllowlistTakes() async throws {
        target.choose(server, link: remote)
        for (index, method) in [DaemonMethod.ask, .sessionsList, .sessionView, .confirm, .subscribe, .brief, .ping].enumerated() {
            _ = try? await target.request(DaemonRequest(id: index + 1, method: method))
        }
        XCTAssertEqual(remote.sent.map(\.method), ["ask", "sessions-list", "session-view", "confirm", "subscribe", "brief", "ping"])
        XCTAssertEqual(local.sent, [])
    }

    func testAServerIsAskedWhichVoiceIsSetButNeverToldOne() async {
        target.choose(server, link: remote)
        _ = try? await target.request(DaemonRequest(id: 1, method: .voiceChoice))
        var setting = DaemonRequest(id: 2, method: .voiceChoice)
        setting.voice = "af_heart"
        _ = try? await target.request(setting)
        XCTAssertEqual(remote.sent.map(\.id), [1])
        XCTAssertNil(remote.sent.first?.voice)
    }

    func testAServerWithNoLinkFallsBackToThisMac() {
        target.choose(server, link: nil)
        XCTAssertEqual(target.target, .thisMac)
        XCTAssertFalse(target.isRemote)
    }

    func testPickingAnotherMachineEndsWhatWasListeningOnTheOldOne() async throws {
        let quiet = QuietLink()
        target.choose(server, link: quiet)
        let ended = expectation(description: "the subscription on the server ended")
        let listening = Task {
            do {
                for try await _ in target.stream(DaemonRequest(id: 1, method: .ask)) {}
            } catch {}
            ended.fulfill()
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        target.choose(.thisMac)
        await fulfillment(of: [ended], timeout: 2)
        listening.cancel()
        XCTAssertEqual(quiet.sent.map(\.method), ["ask"])
        XCTAssertEqual(target.target, .thisMac)
    }

    func testEveryYesToAServerIsSignedEvenInsideItsSession() async throws {
        target.choose(server, link: remote)
        remote.answers["confirm"] = [try line(#"{"id":1,"ok":true,"outcome":"once"}"#)]
        let key = PersonKey()
        let conversation = Conversation(link: target, speaker: RecordingSpeaker(), key: key, face: RecordingFace(), owner: MemoryOwner(nil),
                                        signsEveryYes: { [target] subject in target!.reachesAnotherMachine(subject: subject) })
        let outcome = await conversation.answerHeld("apr_4", .once, reason: "delete old.ts", touchID: false)

        XCTAssertEqual(outcome, .answered)
        XCTAssertEqual(key.signed, ["memnox-confirm:v1:apr_4:once"])
        XCTAssertNotNil(remote.sent.last?.signature)
        // The key check stays home, so the server never hears register-key.
        XCTAssertFalse(remote.sent.contains { $0.method == "register-key" })
    }

    func testASpokenYesToAServerProposalInsideItsSessionIsSignedToo() async throws {
        target.choose(server, link: remote)
        remote.answers["confirm"] = [try line(#"{"id":1,"ok":true,"outcome":"confirmed"}"#)]
        let key = PersonKey()
        let conversation = Conversation(link: target, speaker: RecordingSpeaker(), key: key, face: RecordingFace(), owner: MemoryOwner(nil),
                                        signsEveryYes: { [target] subject in target!.reachesAnotherMachine(subject: subject) })
        await conversation.heard("yes delete it")
        await conversation.handle(try event(#"{"kind":"proposal","subject":"prp_9","agent":"a","summary":"delete old.ts","at":"t","withinSession":true}"#))

        XCTAssertEqual(key.signed, ["memnox-confirm:v1:prp_9:confirmed"])
        XCTAssertNotNil(remote.sent.last { $0.method == "confirm" }?.signature)
    }

    func testAServersSessionIsShownAndNeverActedOn() async {
        let hands = ActingPresenter()
        var remote = true
        let shown = TargetPresenter(hands) { remote }
        let host = DisplayHost(app: "iTerm", tty: "ttys004")
        let opened = await shown.open(host)
        let acts = [
            await shown.focus(session: "s1", host: host),
            await shown.type("run the tests", into: host, request: "dsp_1"),
            await shown.prefill("hi", session: "s1", host: host),
            await shown.launch("claude", in: "/srv"),
            await shown.close(session: "s1", host: host, request: "dsp_2"),
        ]
        let folder = await shown.openFolder("/srv", in: .finder)
        await shown.card(SummaryCard(title: "Billing", text: "Two files."))
        await shown.live(session: "s1", host: host)
        XCTAssertFalse(opened)
        XCTAssertFalse(folder)
        XCTAssertEqual(acts.map(\.outcome), Array(repeating: .failed, count: acts.count))
        XCTAssertEqual(hands.acts, [])
        XCTAssertEqual(hands.cards, ["Billing"])
        XCTAssertEqual(hands.lives, ["s1"])

        remote = false
        let typed = await shown.type("run the tests", into: host, request: "dsp_3")
        XCTAssertEqual(typed, .landed)
        XCTAssertEqual(hands.acts, ["type"])
    }
}
