import CryptoKit
import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Teammates' held calls routed to this person: read from the workspace's inbox, a yes signed with
/// Touch ID over exactly that call, a deny unsigned, and every answer through the workspace alone.
final class WorkspaceAnsweringTests: XCTestCase {
    var cloud: ScriptedTransport!
    var store: MemoryPersonCredential!
    var key: PersonKey!
    var answering: WorkspaceAnswering!

    private let heldRoute = "GET /v1/workspaces/ws_1/me/held"
    private let answerRoute = "POST /v1/workspaces/ws_1/me/held/apr_1"

    override func setUp() {
        cloud = ScriptedTransport()
        store = MemoryPersonCredential(signedInCredential())
        key = PersonKey()
        answering = WorkspaceAnswering(inbox: HttpWorkspaceInbox(transport: cloud), store: store, key: key, now: { morning })
    }

    private func showing(_ calls: String...) async -> InboxChange {
        cloud.answer(heldRoute, 200, "[\(calls.joined(separator: ","))]")
        return await answering.refresh()
    }

    func testTheInboxIsReadWithTheCredentialAndEachCallNamesItsMachine() async throws {
        let change = await showing(heldJSON("apr_1"), heldJSON("apr_2", machineLabel: nil, agent: "claude-code"))

        XCTAssertEqual(cloud.sent(heldRoute).first?.authorization, "Bearer mnx_person")
        XCTAssertEqual(change.arrived.map(\.id), ["apr_1", "apr_2"])
        XCTAssertEqual(change.arrived.map(\.who), ["codex on build-box, from your team", "claude-code on mch_91c2, from your team"])
        let first = try XCTUnwrap(change.arrived.first)
        XCTAssertEqual(first.what, "Codex wants to push to main.")
        XCTAssertEqual(first.whyHeld, "Pushes to main are held.")
        XCTAssertEqual(first.machineClass, "server")
        XCTAssertEqual(first.approvalsNeeded, 1)
        XCTAssertTrue(answering.owns("apr_1"))
    }

    func testACallWithoutTheOptionalFieldsStillDecodes() throws {
        let json = """
        {"id":"apr_9","machineId":"mch_1","machineClass":"workstation","agent":"codex","operation":"fs.delete",\
        "reason":"deletes are held","askedAt":"2026-10-06T10:00:00.000Z","expiresAt":"2026-10-06T10:30:00.000Z",\
        "escalated":true,"approvalsNeeded":2,"approvedByYou":false}
        """
        let call = try JSONDecoder().decode(WorkspaceHeldCall.self, from: Data(json.utf8))
        XCTAssertEqual(call.what, "fs.delete")
        XCTAssertEqual(call.whyHeld, "deletes are held")
        XCTAssertEqual(call.who, "codex on mch_1, from your team")
        XCTAssertTrue(call.escalated)
        XCTAssertNotNil(call.expiry)
    }

    func testAPollSaysWhatCameAndWentAndSkipsWhatIsDoneOrRunOut() async {
        _ = await showing(heldJSON("apr_1"), heldJSON("apr_2"))

        let change = await showing(heldJSON("apr_2"), heldJSON("apr_3"), heldJSON("apr_4", approvedByYou: true),
                                   heldJSON("apr_5", expiresAt: "2026-10-06T10:01:00.000Z"))

        XCTAssertEqual(change.arrived.map(\.id), ["apr_3"])
        XCTAssertEqual(change.gone, ["apr_1"])
        XCTAssertFalse(answering.owns("apr_4"))
        XCTAssertFalse(answering.owns("apr_5"))
    }

    func testAWorkspaceThatDidNotAnswerKeepsItsCallsShowing() async {
        _ = await showing(heldJSON("apr_1"))
        cloud.offline = true

        let change = await answering.refresh()

        XCTAssertEqual(change, InboxChange())
        XCTAssertTrue(answering.owns("apr_1"))
    }

    func testARevokedCredentialSignsOutAndTakesEveryCallDown() async {
        _ = await showing(heldJSON("apr_1"))
        cloud.answer(heldRoute, 401, #"{"message":"Unauthorized"}"#)

        let change = await answering.refresh()

        XCTAssertTrue(change.signedOut)
        XCTAssertEqual(change.gone, ["apr_1"])
        XCTAssertFalse(answering.owns("apr_1"))
    }

    func testAYesIsSignedWithTouchIDOverExactlyThatCallAndAnswer() async throws {
        _ = await showing(heldJSON("apr_1"))
        cloud.answer(answerRoute, 200, #"{"id":"apr_1","status":"answered","answer":"once","approvalsNeeded":0}"#)

        let outcome = await answering.answer("apr_1", .once, reason: "Codex wants to push to main.")

        XCTAssertEqual(outcome, .answered)
        XCTAssertEqual(key.signed, ["memnox-confirm:v1:apr_1:once"])
        let sent = try XCTUnwrap(cloud.sent(answerRoute).first)
        XCTAssertEqual(sent.authorization, "Bearer mnx_person")
        XCTAssertEqual(sent.body["answer"], "once")
        XCTAssertEqual(sent.body["deviceId"], "pdv_mac")
        let signature = try P256.Signing.ECDSASignature(derRepresentation: XCTUnwrap(Data(base64Encoded: XCTUnwrap(sent.body["signature"]))))
        let point = try P256.Signing.PublicKey(x963Representation: XCTUnwrap(Data(base64Encoded: key.publicPoint)))
        XCTAssertTrue(point.isValidSignature(signature, for: Data("memnox-confirm:v1:apr_1:once".utf8)))
        XCTAssertFalse(answering.owns("apr_1"))
    }

    func testAYesForTheSessionSignsThatAnswer() async throws {
        _ = await showing(heldJSON("apr_1"))
        cloud.answer(answerRoute, 200, #"{"id":"apr_1","status":"counted","approvalsNeeded":1}"#)

        let outcome = await answering.answer("apr_1", .session, reason: "push")

        XCTAssertEqual(outcome, .answered)
        XCTAssertEqual(key.signed, ["memnox-confirm:v1:apr_1:session"])
        XCTAssertEqual(cloud.sent(answerRoute).first?.body["answer"], "session")
    }

    func testADenyGoesUnsignedWithNoTouchID() async throws {
        _ = await showing(heldJSON("apr_1"))
        cloud.answer(answerRoute, 200, #"{"id":"apr_1","status":"answered","answer":"deny","approvalsNeeded":0}"#)

        let outcome = await answering.answer("apr_1", .deny, reason: "push")

        XCTAssertEqual(outcome, .answered)
        XCTAssertEqual(key.signed, [])
        XCTAssertEqual(cloud.sent(answerRoute).first?.body, ["answer": "deny", "deviceId": "pdv_mac"])
    }

    func testTouchIDCancelledSendsNothingAndTheCallStays() async {
        _ = await showing(heldJSON("apr_1"))
        key.touches = false

        let outcome = await answering.answer("apr_1", .once, reason: "push")

        XCTAssertEqual(outcome, .cancelled)
        XCTAssertTrue(cloud.sent(answerRoute).isEmpty)
        XCTAssertTrue(answering.owns("apr_1"))
    }

    func testAYesTheWorkspaceWouldNotTakeFailsAndTheCallStays() async {
        _ = await showing(heldJSON("apr_1"))
        cloud.answer(answerRoute, 403, #"{"message":"That signature does not verify."}"#)

        let outcome = await answering.answer("apr_1", .once, reason: "push")

        XCTAssertEqual(outcome, .failed(WorkspaceLines.notReached))
        XCTAssertTrue(answering.owns("apr_1"))
    }

    func testACallAlreadySettledIsReportedAsAnsweredElsewhereAndNotShownAgain() async {
        _ = await showing(heldJSON("apr_1"))
        cloud.answer(answerRoute, 409, #"{"message":"already answered"}"#)

        let outcome = await answering.answer("apr_1", .deny, reason: "push")

        XCTAssertEqual(outcome, .answeredElsewhere(EarlierAnswer(word: nil)))
        XCTAssertFalse(answering.owns("apr_1"))
        // Still listed for a moment by the cloud, and still not put back on the island.
        let change = await showing(heldJSON("apr_1"))
        XCTAssertEqual(change.arrived, [])
    }

    func testTheInboxAsksForRecentSettledCallsToo() async {
        _ = await showing(heldJSON("apr_1"))
        XCTAssertEqual(cloud.sent(heldRoute).first?.query, "include=recent")
    }

    func testACallSettledElsewhereSaysWhoAnsweredItAndWhere() async {
        _ = await showing(heldJSON("apr_1"), heldJSON("apr_2"))

        let change = await showing(settledJSON("apr_1", answer: "deny", by: "Ana", on: "console"), heldJSON("apr_2"))

        XCTAssertEqual(change.gone, ["apr_1"])
        XCTAssertEqual(change.answeredElsewhere, ["apr_1": "Denied by Ana in the console"])
        XCTAssertFalse(answering.owns("apr_1"))
    }

    func testARecentSettledCallIsNeverShownAsWaiting() async {
        let change = await showing(settledJSON("apr_7"), heldJSON("apr_1"))
        XCTAssertEqual(change.arrived.map(\.id), ["apr_1"])
        XCTAssertEqual(change.answeredElsewhere, [:])
        XCTAssertFalse(answering.owns("apr_7"))
    }

    func testACallThatSimplyWentSaysNothingAboutWhoAnswered() async {
        _ = await showing(heldJSON("apr_1"))
        let change = await showing()
        XCTAssertEqual(change.gone, ["apr_1"])
        XCTAssertEqual(change.answeredElsewhere, [:])
    }

    func testOneCallTheAppCannotReadNeverHidesTheOthers() async {
        let change = await showing(#"{"machineId":"mch_1"}"#, heldJSON("apr_1"))
        XCTAssertEqual(change.arrived.map(\.id), ["apr_1"])
    }

    func testACallAnsweredHereIsNotReportedAsAnsweredElsewhere() async {
        _ = await showing(heldJSON("apr_1"))
        cloud.answer(answerRoute, 200, #"{"id":"apr_1","status":"answered","answer":"deny","approvalsNeeded":0}"#)
        _ = await answering.answer("apr_1", .deny, reason: "push")

        let change = await showing(settledJSON("apr_1", answer: "deny", by: "Ana", on: "Ana's Mac"))

        XCTAssertEqual(change.gone, [])
        XCTAssertEqual(change.answeredElsewhere, [:])
    }

    func testTheInboxMapsTheContractsStatuses() {
        XCTAssertEqual(HttpWorkspaceInbox.failure(401, Data()), .signedOut)
        XCTAssertEqual(HttpWorkspaceInbox.failure(403, Data(#"{"message":"not yours"}"#.utf8)), .notReached("not yours"))
        XCTAssertEqual(HttpWorkspaceInbox.failure(404, Data()), .notFound("status 404"))
        XCTAssertEqual(HttpWorkspaceInbox.failure(409, Data(#"{"error":"expired"}"#.utf8)), .settled("expired"))
        XCTAssertEqual(HttpWorkspaceInbox.failure(500, Data()), .refused(500, "status 500"))
    }
}

/// A workspace subject belongs to the workspace: the island's buttons answer it through the inbox, and
/// no daemon link, this Mac's or a server's, is ever sent it.
final class WorkspaceRoutingTests: XCTestCase {
    var cloud: ScriptedTransport!
    var local: ScriptedLink!
    var server: ScriptedLink!
    var target: TargetLink!
    var answering: WorkspaceAnswering!
    var key: PersonKey!
    var conversation: Conversation!

    override func setUp() {
        cloud = ScriptedTransport()
        local = ScriptedLink()
        server = ScriptedLink()
        target = TargetLink(local: local)
        target.choose(.server(machineId: "mch_vps", deviceId: "dev_mac", name: "hostinger-vps"), link: server)
        key = PersonKey()
        answering = WorkspaceAnswering(inbox: HttpWorkspaceInbox(transport: cloud), store: MemoryPersonCredential(signedInCredential()),
                                       key: key, now: { morning })
        conversation = Conversation(link: target, speaker: RecordingSpeaker(), key: key, face: RecordingFace(), owner: MemoryOwner(nil),
                                    signsEveryYes: { [target] subject in target!.reachesAnotherMachine(subject: subject) },
                                    workspace: answering)
    }

    private func showing(_ id: String) async {
        cloud.answer("GET /v1/workspaces/ws_1/me/held", 200, "[\(heldJSON(id))]")
        for call in await answering.refresh().arrived { target.rememberWorkspace(subject: call.id) }
    }

    func testAYesOnAWorkspaceCallGoesThroughTheInboxAndNeverADaemon() async {
        await showing("apr_1")
        cloud.answer("POST /v1/workspaces/ws_1/me/held/apr_1", 200, #"{"id":"apr_1","status":"answered","answer":"once","approvalsNeeded":0}"#)

        // Even a card that claims a tap would do is signed, since a teammate's call always reaches another machine.
        let outcome = await conversation.answerHeld("apr_1", .once, reason: "push to main", touchID: false)

        XCTAssertEqual(outcome, .answered)
        XCTAssertEqual(cloud.sent("POST /v1/workspaces/ws_1/me/held/apr_1").count, 1)
        XCTAssertEqual(key.signed, ["memnox-confirm:v1:apr_1:once"])
        XCTAssertEqual(local.sent, [])
        XCTAssertEqual(server.sent, [])
    }

    func testADenyOnAWorkspaceCallGoesThroughTheInboxUnsigned() async {
        await showing("apr_1")
        cloud.answer("POST /v1/workspaces/ws_1/me/held/apr_1", 200, #"{"id":"apr_1","status":"answered","answer":"deny","approvalsNeeded":0}"#)

        let outcome = await conversation.answerHeld("apr_1", .deny, reason: "push to main")

        XCTAssertEqual(outcome, .answered)
        XCTAssertNil(cloud.sent("POST /v1/workspaces/ws_1/me/held/apr_1").first?.body["signature"])
        XCTAssertEqual(key.signed, [])
        XCTAssertEqual(local.sent, [])
        XCTAssertEqual(server.sent, [])
    }

    func testTheTargetLinkRefusesToCarryAWorkspaceSubjectToAnyDaemon() async {
        target.rememberWorkspace(subject: "apr_team")
        var request = DaemonRequest(id: 1, method: .confirm)
        request.subject = "apr_team"
        request.answer = HoldAnswer.once.rawValue

        do {
            for try await _ in target.stream(request) {}
            XCTFail("a workspace subject reached a daemon")
        } catch {}

        XCTAssertTrue(target.belongsToWorkspace(subject: "apr_team"))
        XCTAssertEqual(local.sent, [])
        XCTAssertEqual(server.sent, [])
    }

    func testAMachinesOwnCallStillGoesToItsDaemon() async throws {
        await showing("apr_1")
        target.remember(subject: "apr_local", from: .thisMac)
        local.answers["confirm"] = [try line(#"{"id":1,"ok":true,"outcome":"deny"}"#)]

        _ = await conversation.answerHeld("apr_local", .deny, reason: "push")

        XCTAssertEqual(local.sent.map(\.method), ["confirm"])
        XCTAssertTrue(cloud.sent("POST /v1/workspaces/ws_1/me/held/apr_local").isEmpty)
    }

    func testATeamCallIsAnnouncedAloudWithItsLabelAndSendsTheAnswerToTheIsland() async throws {
        let speaker = RecordingSpeaker()
        let face = RecordingFace()
        let chimes = RecordingChimes()
        let voice = Conversation(link: target, speaker: speaker, key: key, face: face, owner: MemoryOwner(nil), chimes: chimes,
                                 workspace: answering)
        cloud.answer("GET /v1/workspaces/ws_1/me/held", 200, "[\(heldJSON("apr_1", ownerName: "Ana"))]")
        let arrived = await answering.refresh().arrived
        let call = try XCTUnwrap(arrived.first)

        await voice.announceTeam(call)

        XCTAssertEqual(chimes.played, [.held])
        XCTAssertTrue(face.shown.contains { $0.1 == caption("codex on build-box, from Ana's team needs you") }, "\(face.shown)")
        let said = speaker.said.joined(separator: " ")
        XCTAssertTrue(said.contains("from Ana's team is waiting on you"), said)
        XCTAssertTrue(said.hasSuffix(heldAsk), said)
        // Left listening, since a spoken answer now reaches the call through the brain.
        XCTAssertEqual(face.states.last, .listening)
        // Nothing is asked of any daemon, and nothing is answered or signed by being said.
        XCTAssertEqual(local.sent, [])
        XCTAssertEqual(server.sent, [])
        XCTAssertEqual(key.signed, [])
        XCTAssertTrue(cloud.sent("POST /v1/workspaces/ws_1/me/held/apr_1").isEmpty)
        XCTAssertTrue(voice.stillAsking("apr_1"))
    }

    func testATeamCallNoLongerOwnedIsNotAnnounced() async throws {
        let speaker = RecordingSpeaker()
        let voice = Conversation(link: target, speaker: speaker, key: key, face: RecordingFace(), owner: MemoryOwner(nil),
                                 workspace: answering)
        let call = try JSONDecoder().decode(WorkspaceHeldCall.self, from: Data(heldJSON("apr_gone").utf8))

        await voice.announceTeam(call)

        XCTAssertEqual(speaker.said, [])
    }

    func testATeamCallSettledElsewhereStopsTheVoiceAndSaysWho() async throws {
        let speaker = RecordingSpeaker()
        let face = RecordingFace()
        let voice = Conversation(link: target, speaker: speaker, key: key, face: face, owner: MemoryOwner(nil), workspace: answering)
        await showing("apr_1")
        let call = try XCTUnwrap(answering.call("apr_1"))
        await voice.announceTeam(call)

        voice.teamSettled("apr_1", line: "Allowed once on Ana's iPhone")

        XCTAssertEqual(speaker.stopped, 1)
        XCTAssertEqual(face.shown.last?.1, "Allowed once on Ana's iPhone")
        XCTAssertFalse(voice.stillAsking("apr_1"))
        // A second word about it changes nothing.
        voice.teamSettled("apr_1", line: nil)
        XCTAssertEqual(speaker.stopped, 1)
    }

    func testAnsweringATeamCallByHandStopsItBeingAsked() async throws {
        let speaker = RecordingSpeaker()
        let voice = Conversation(link: target, speaker: speaker, key: key, face: RecordingFace(), owner: MemoryOwner(nil), workspace: answering)
        await showing("apr_1")
        await voice.announceTeam(try XCTUnwrap(answering.call("apr_1")))
        cloud.answer("POST /v1/workspaces/ws_1/me/held/apr_1", 200, #"{"id":"apr_1","status":"answered","answer":"deny","approvalsNeeded":0}"#)

        _ = await voice.answerHeld("apr_1", .deny, reason: "push")

        XCTAssertFalse(voice.stillAsking("apr_1"))
        XCTAssertEqual(speaker.stopped, 1)
        XCTAssertEqual(key.signed, [])
    }
}
