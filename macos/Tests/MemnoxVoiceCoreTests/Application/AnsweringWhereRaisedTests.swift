import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Every machine's held calls reach the island whichever one is picked, and each answer goes back
/// through the link the call came from, while the voice keeps talking to the machine picked.
final class AnsweringWhereRaisedTests: XCTestCase {
    var local: ScriptedLink!
    var vps: ScriptedLink!
    var other: ScriptedLink!
    var target: TargetLink!
    var key: PersonKey!
    var face: RecordingFace!
    var conversation: Conversation!
    private let vpsMachine = MachineTarget.server(machineId: "mch_vps", deviceId: "dev_mac", name: "hostinger-vps")
    private let otherMachine = MachineTarget.server(machineId: "mch_other", deviceId: "dev_mac2", name: "build-box")

    override func setUp() {
        local = ScriptedLink()
        vps = ScriptedLink()
        other = ScriptedLink()
        target = TargetLink(local: local)
        target.register(otherMachine, link: other)
        target.choose(vpsMachine, link: vps)
        key = PersonKey()
        face = RecordingFace()
        conversation = Conversation(link: target, speaker: RecordingSpeaker(), key: key, face: face, owner: MemoryOwner(nil),
                                    signsEveryYes: { [target] subject in target!.reachesAnotherMachine(subject: subject) },
                                    raisedOn: { [target] subject in target!.machine(for: subject)?.serverName })
    }

    func testAHeldCallFromThisMacStillArrivesAndIsAnsweredHereWhileAServerIsPicked() async throws {
        let held = try event(#"{"kind":"held","subject":"apr_local","agent":"claude-code","summary":"delete old.ts","at":"t","withinSession":true}"#)
        XCTAssertTrue(MachineEvents.delivers(held, chosen: false, thisMac: true))
        target.remember(subject: held.subject, from: .thisMac)
        local.answers["confirm"] = [try line(#"{"id":1,"ok":true,"outcome":"once"}"#)]

        let outcome = await conversation.answerHeld("apr_local", .once, reason: "delete old.ts", touchID: false)

        XCTAssertEqual(outcome, .answered)
        XCTAssertEqual(local.sent.map(\.method), ["confirm"])
        // Inside its own repository on this Mac, so a tap is the answer, as it always was here.
        XCTAssertNil(local.sent.first?.signature)
        XCTAssertEqual(vps.sent, [])
        XCTAssertEqual(other.sent, [])
    }

    func testAHeldCallFromAServerIsAnsweredThroughThatServersLinkAndSigned() async throws {
        let held = try event(#"{"kind":"held","subject":"apr_build","agent":"codex","summary":"push to main","at":"t","withinSession":true}"#)
        XCTAssertTrue(MachineEvents.delivers(held, chosen: false, thisMac: false))
        target.remember(subject: held.subject, from: otherMachine)
        other.answers["confirm"] = [try line(#"{"id":1,"ok":true,"outcome":"once"}"#)]

        let outcome = await conversation.answerHeld("apr_build", .once, reason: "push to main", touchID: false)

        XCTAssertEqual(outcome, .answered)
        XCTAssertEqual(other.sent.map(\.method), ["confirm"])
        XCTAssertNotNil(other.sent.first?.signature)
        XCTAssertEqual(key.signed, ["memnox-confirm:v1:apr_build:once"])
        XCTAssertEqual(vps.sent, [])
        XCTAssertFalse(local.sent.contains { $0.method == "confirm" })
    }

    func testADenyGoesBackWhereTheCallCameFromUnsigned() async throws {
        target.remember(subject: "apr_local", from: .thisMac)
        local.answers["confirm"] = [try line(#"{"id":1,"ok":true,"outcome":"deny"}"#)]
        _ = await conversation.answerHeld("apr_local", .deny, reason: "push")
        XCTAssertEqual(local.sent.last?.answer, "deny")
        XCTAssertNil(local.sent.last?.signature)
        XCTAssertEqual(vps.sent, [])
    }

    func testTheVoiceStillTalksToTheMachinePicked() async {
        target.remember(subject: "apr_local", from: .thisMac)
        _ = await conversation.sessionsList()
        XCTAssertEqual(vps.sent.map(\.method), ["sessions-list"])
        XCTAssertEqual(local.sent, [])
    }

    func testABriefOnAServersHeldCallIsAskedOfThatServerAndNamesIt() async throws {
        let held = try event(#"{"kind":"held","subject":"apr_build","agent":"codex","agentName":"Codex","summary":"push to main","at":"t"}"#)
        target.remember(subject: held.subject, from: otherMachine)
        await conversation.handle(held)
        XCTAssertEqual(other.sent.first?.method, "brief")
        XCTAssertEqual(vps.sent, [])
        XCTAssertTrue(face.shown.contains { $0.1 == "Codex on build-box needs you" })
    }

    func testPickingAnotherMachineLeavesAnAnswerToThisMacAlone() async throws {
        target.remember(subject: "apr_local", from: .thisMac)
        target.choose(.thisMac)
        XCTAssertEqual(target.machine(for: "apr_local"), .thisMac)
        target.forget(subject: "apr_local")
        XCTAssertNil(target.machine(for: "apr_local"))
    }

    func testAForgottenServerIsNoLongerAnsweredOrPicked() {
        target.remember(subject: "apr_vps", from: vpsMachine)
        target.unregister(machineId: "mch_vps")
        XCTAssertNil(target.machine(for: "apr_vps"))
        XCTAssertEqual(target.target, .thisMac)
    }

    func testOnlyWhatWaitsOnThePersonComesFromAMachineNotPicked() throws {
        let question = try event(#"{"kind":"notice","notice":"question","subject":"n1","agent":"a","summary":"Which?","at":"t"}"#)
        let finished = try event(#"{"kind":"notice","notice":"finished","subject":"n2","agent":"a","summary":"Done","at":"t"}"#)
        let shown = try event(#"{"kind":"show","subject":"d1","agent":"a","summary":"open","at":"t","display":"open"}"#)
        let proposal = try event(#"{"kind":"proposal","subject":"p1","agent":"a","summary":"allow","at":"t"}"#)
        let settled = try event(#"{"kind":"settled","subject":"apr_1","agent":"a","summary":"s","at":"t"}"#)
        // A server not picked: held calls, questions and their settling.
        XCTAssertTrue(MachineEvents.delivers(question, chosen: false, thisMac: false))
        XCTAssertTrue(MachineEvents.delivers(settled, chosen: false, thisMac: false))
        XCTAssertFalse(MachineEvents.delivers(finished, chosen: false, thisMac: false))
        XCTAssertFalse(MachineEvents.delivers(proposal, chosen: false, thisMac: false))
        XCTAssertFalse(MachineEvents.delivers(shown, chosen: false, thisMac: false))
        // This Mac not picked: its proposals and notices still come, and nothing to show on a screen.
        XCTAssertTrue(MachineEvents.delivers(finished, chosen: false, thisMac: true))
        XCTAssertTrue(MachineEvents.delivers(proposal, chosen: false, thisMac: true))
        XCTAssertFalse(MachineEvents.delivers(shown, chosen: false, thisMac: true))
        // The machine picked is heard in full.
        XCTAssertTrue(MachineEvents.delivers(shown, chosen: true, thisMac: false))
    }

    func testAServersCallIsLabelledWithItsNameAndThisMacsWithYourMac() {
        XCTAssertEqual(CallLabel.label("Claude Code", at: .raised(on: "hostinger-vps")), "Claude Code on hostinger-vps")
        XCTAssertEqual(CallLabel.label("Claude Code", at: .raised(on: nil)), "Claude Code on your Mac")
        XCTAssertEqual(CallLabel.label("Claude Code", at: .raised(on: " ")), "Claude Code on your Mac")
    }
}
