import CryptoKit
import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// A team's question answered by voice: every ask names the questions, and the answer the brain proposes is
/// carried out with the workspace first, then confirmed to the daemon that raised the proposal and no other.
final class TeamAnswerByVoiceTests: XCTestCase {
    var cloud: ScriptedTransport!
    var local: ScriptedLink!
    var vps: ScriptedLink!
    var other: ScriptedLink!
    var target: TargetLink!
    var key: PersonKey!
    var answering: WorkspaceAnswering!
    var conversation: Conversation!
    var carried: [(String, HeldOutcome)] = []
    private let vpsMachine = MachineTarget.server(machineId: "mch_vps", deviceId: "dev_mac", name: "hostinger-vps")
    private let otherMachine = MachineTarget.server(machineId: "mch_other", deviceId: "dev_mac2", name: "build-box")
    private let answerRoute = "POST /v1/workspaces/ws_1/me/held/apr_1"
    private let done = #"{"id":1,"ok":true,"chunk":{"kind":"done"}}"#

    override func setUp() {
        cloud = ScriptedTransport()
        local = ScriptedLink()
        vps = ScriptedLink()
        other = ScriptedLink()
        target = TargetLink(local: local)
        target.register(vpsMachine, link: vps)
        target.register(otherMachine, link: other)
        key = PersonKey()
        answering = WorkspaceAnswering(inbox: HttpWorkspaceInbox(transport: cloud), store: MemoryPersonCredential(signedInCredential()),
                                       key: key, now: { morning })
        carried = []
        conversation = Conversation(link: target, speaker: RecordingSpeaker(), key: key, face: RecordingFace(), owner: MemoryOwner(nil),
                                    signsEveryYes: { [target] subject in target!.reachesAnotherMachine(subject: subject) },
                                    workspace: answering)
        conversation.teamAnswered = { [weak self] subject, outcome in self?.carried.append((subject, outcome)) }
    }

    private func showing(_ calls: String...) async {
        cloud.answer("GET /v1/workspaces/ws_1/me/held", 200, "[\(calls.joined(separator: ","))]")
        for call in await answering.refresh().arrived { target.rememberWorkspace(subject: call.id) }
    }

    /// The proposal the daemon writes once the brain heard the answer, raised on the machine named.
    private func proposal(_ answer: HoldAnswer, from machine: MachineTarget = .thisMac) throws -> DaemonEvent {
        let proposal = try event(#"""
        {"kind":"proposal","subject":"prp_1","agent":"agt_memnox-operator","summary":"answer your team's call","at":"t",\#
        "teamAnswer":{"callId":"apr_1","answer":"\#(answer.rawValue)","label":"codex on build-box, from your team"}}
        """#)
        target.remember(subject: proposal.subject, from: machine)
        return proposal
    }

    private func verifies(_ signature: String?, _ message: String) throws -> Bool {
        let der = try XCTUnwrap(Data(base64Encoded: XCTUnwrap(signature)))
        let point = try P256.Signing.PublicKey(x963Representation: XCTUnwrap(Data(base64Encoded: key.publicPoint)))
        return point.isValidSignature(try P256.Signing.ECDSASignature(derRepresentation: der), for: Data(message.utf8))
    }

    private func confirms(_ link: ScriptedLink) -> [DaemonRequest] { link.sent.filter { $0.method == "confirm" } }

    func testEveryAskNamesTheTeamsQuestionsWhileSignedIn() async throws {
        await showing(heldJSON("apr_1"), heldJSON("apr_2", machineLabel: nil, agent: "claude-code"))
        local.answers["ask"] = [try line(done)]

        await conversation.heard("allow the push")

        let ask = try XCTUnwrap(local.sent.first { $0.method == "ask" })
        XCTAssertEqual(ask.teamCalls, [
            TeamCallBrief(id: "apr_1", label: "codex on build-box, from your team", what: "Codex wants to push to main."),
            TeamCallBrief(id: "apr_2", label: "claude-code on mch_91c2, from your team", what: "Codex wants to push to main."),
        ])
        let wire = String(decoding: try JSONEncoder().encode(ask), as: UTF8.self)
        XCTAssertTrue(wire.contains(#""teamCalls":[{"#), wire)
    }

    func testAnAskWithNoQuestionsWaitingSaysSoWithAnEmptyList() async throws {
        local.answers["ask"] = [try line(done)]

        await conversation.heard("what is going on")
        await conversation.guess("what is")

        XCTAssertEqual(local.sent.filter { $0.method == "ask" }.map(\.teamCalls), [[], []])
    }

    func testAnAskFromAMacNotSignedInToATeamNamesNoQuestions() async throws {
        let alone = Conversation(link: local, speaker: RecordingSpeaker(), key: key, face: RecordingFace(), owner: MemoryOwner(nil))
        local.answers["ask"] = [try line(done)]

        await alone.heard("what is going on")

        XCTAssertNil(try XCTUnwrap(local.sent.first).teamCalls)
    }

    func testAYesGoesSignedToTheWorkspaceThenIsConfirmedSignedToTheDaemon() async throws {
        await showing(heldJSON("apr_1"))
        local.answers["ask"] = [try line(done)]
        local.answers["confirm"] = [try line(#"{"id":2,"ok":true,"outcome":"confirmed"}"#)]
        cloud.answer(answerRoute, 200, #"{"id":"apr_1","status":"answered","answer":"once","approvalsNeeded":0}"#)
        await conversation.heard("allow it once")

        await conversation.handle(try proposal(.once))

        // One touch signs both, the call's answer for the workspace and the proposal's for the daemon.
        XCTAssertEqual(key.signed, ["memnox-confirm:v1:apr_1:once", "memnox-confirm:v1:prp_1:confirmed"])
        let sent = try XCTUnwrap(cloud.sent(answerRoute).first)
        XCTAssertEqual(sent.body["answer"], "once")
        XCTAssertTrue(try verifies(sent.body["signature"], "memnox-confirm:v1:apr_1:once"))
        let confirm = try XCTUnwrap(confirms(local).first)
        XCTAssertEqual(confirm.subject, "prp_1")
        XCTAssertEqual(confirm.answer, "confirmed")
        XCTAssertTrue(try verifies(confirm.signature, "memnox-confirm:v1:prp_1:confirmed"))
        XCTAssertFalse(answering.owns("apr_1"))
        XCTAssertEqual(carried.map(\.0), ["apr_1"])
        XCTAssertEqual(carried.map(\.1), [.answered])
    }

    func testAYesWhileAPhoneIsPairedIsLeftToItsFaceIDAndTouchesNothingHere() async throws {
        await showing(heldJSON("apr_1"))
        local.answers["ask"] = [try line(done)]
        await conversation.heard("allow it once")
        let paired = try event(#"""
        {"kind":"proposal","subject":"prp_1","agent":"agt_memnox-operator","summary":"answer your team's call","at":"t",\#
        "teamAnswer":{"callId":"apr_1","answer":"once","label":"codex on build-box, from your team"},\#
        "answerOn":{"deviceId":"dev_1","name":"iPhone"}}
        """#)
        target.remember(subject: paired.subject, from: .thisMac)

        await conversation.handle(paired)

        XCTAssertEqual(key.signed, [])
        XCTAssertTrue(cloud.sent(answerRoute).isEmpty)
        XCTAssertTrue(confirms(local).isEmpty)
        XCTAssertTrue(answering.owns("apr_1"))
    }

    func testADenyGoesUnsignedToTheWorkspaceAndIsConfirmedUnsigned() async throws {
        await showing(heldJSON("apr_1"))
        local.answers["ask"] = [try line(done)]
        local.answers["confirm"] = [try line(#"{"id":2,"ok":true,"outcome":"confirmed"}"#)]
        cloud.answer(answerRoute, 200, #"{"id":"apr_1","status":"answered","answer":"deny","approvalsNeeded":0}"#)
        await conversation.heard("deny it")

        await conversation.handle(try proposal(.deny))

        XCTAssertEqual(key.signed, [])
        XCTAssertEqual(cloud.sent(answerRoute).first?.body, ["answer": "deny", "deviceId": "pdv_mac"])
        let confirm = try XCTUnwrap(confirms(local).first)
        XCTAssertEqual(confirm.answer, "confirmed")
        XCTAssertNil(confirm.signature)
    }

    func testACancelledTouchIDDeclinesTheProposalAndNeverTouchesTheWorkspace() async throws {
        await showing(heldJSON("apr_1"))
        local.answers["ask"] = [try line(done)]
        local.answers["confirm"] = [try line(#"{"id":2,"ok":true,"outcome":"declined"}"#)]
        key.touches = false
        await conversation.heard("allow it")

        await conversation.handle(try proposal(.once))

        XCTAssertTrue(cloud.sent(answerRoute).isEmpty)
        let confirm = try XCTUnwrap(confirms(local).first)
        XCTAssertEqual(confirm.answer, "declined")
        XCTAssertNil(confirm.signature)
        XCTAssertTrue(answering.owns("apr_1"))
        XCTAssertTrue(carried.isEmpty)
    }

    func testAnAnswerTheWorkspaceWouldNotTakeDeclinesTheProposal() async throws {
        await showing(heldJSON("apr_1"))
        local.answers["ask"] = [try line(done)]
        cloud.answer(answerRoute, 403, #"{"message":"signature did not verify"}"#)
        await conversation.heard("allow it")

        await conversation.handle(try proposal(.once))

        XCTAssertEqual(confirms(local).map(\.answer), ["declined"])
        XCTAssertNil(confirms(local).first?.signature)
        XCTAssertTrue(carried.isEmpty)
    }

    func testAProposalForACallNoLongerWaitingIsDeclinedAndNothingIsSigned() async throws {
        local.answers["ask"] = [try line(done)]
        await conversation.heard("allow it")

        await conversation.handle(try proposal(.once))

        XCTAssertEqual(key.signed, [])
        XCTAssertTrue(cloud.sent(answerRoute).isEmpty)
        XCTAssertEqual(confirms(local).map(\.answer), ["declined"])
    }

    func testATeamAnswerIsConfirmedOnlyToTheDaemonThatRaisedIt() async throws {
        await showing(heldJSON("apr_1"))
        target.choose(vpsMachine)
        vps.answers["ask"] = [try line(done)]
        other.answers["confirm"] = [try line(#"{"id":2,"ok":true,"outcome":"confirmed"}"#)]
        cloud.answer(answerRoute, 200, #"{"id":"apr_1","status":"answered","answer":"once","approvalsNeeded":0}"#)
        await conversation.heard("allow it once")

        await conversation.handle(try proposal(.once, from: otherMachine))

        XCTAssertEqual(confirms(other).map(\.subject), ["prp_1"])
        XCTAssertTrue(try verifies(confirms(other).first?.signature, "memnox-confirm:v1:prp_1:confirmed"))
        XCTAssertEqual(confirms(vps), [])
        XCTAssertEqual(local.sent, [])
        // The workspace's own call id never reaches any daemon, only the proposal does.
        let everySubject = (local.sent + vps.sent + other.sent).compactMap(\.subject)
        XCTAssertFalse(everySubject.contains("apr_1"), "\(everySubject)")
        XCTAssertEqual(cloud.sent(answerRoute).count, 1)
    }

    func testATeamAnswerNobodyAskedForIsDeclinedWithoutTouchingTheWorkspace() async throws {
        await showing(heldJSON("apr_1"))
        local.answers["confirm"] = [try line(#"{"id":2,"ok":true,"outcome":"declined"}"#)]

        await conversation.handle(try proposal(.once))

        XCTAssertEqual(key.signed, [])
        XCTAssertTrue(cloud.sent(answerRoute).isEmpty)
        XCTAssertEqual(confirms(local).map(\.answer), ["declined"])
    }
}
