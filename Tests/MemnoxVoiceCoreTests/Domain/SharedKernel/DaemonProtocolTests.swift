import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// The wire format shared with memnox-runtime, read and written exactly.
final class DaemonProtocolTests: XCTestCase {
    func testEncodesOnlyTheFieldsSet() throws {
        var request = DaemonRequest(id: 3, method: .ask)
        request.said = "what is claude doing"
        let text = String(data: try encodeLine(request), encoding: .utf8)
        XCTAssertEqual(text, "{\"id\":3,\"method\":\"ask\",\"said\":\"what is claude doing\"}\n")
    }

    func testDecodesWhatTheRuntimeWrites() throws {
        let event = try line(#"{"id":0,"ok":true,"event":{"kind":"held","subject":"apr_1","agent":"claude-code","summary":"claude-code wants to push","at":"2026-09-30T10:00:00.000Z","expiresAt":"2026-09-30T10:02:00.000Z"}}"#)
        XCTAssertEqual(event.event?.eventKind, .held)
        let chunk = try line(#"{"id":2,"ok":true,"chunk":{"kind":"done"}}"#)
        XCTAssertEqual(chunk.chunk?.endsTurn, true)
        XCTAssertThrowsError(try line("not json"))
    }

    func testReadsWhereASessionRuns() throws {
        let located = try line(#"{"id":7,"ok":true,"location":{"sessionId":"ses_1","agent":"claude-code","alive":true,"app":"iTerm","appPath":"/Applications/iTerm.app","tty":"ttys004","cwd":"/work/shop"}}"#)
        XCTAssertEqual(located.location?.appPath, "/Applications/iTerm.app")
        XCTAssertEqual(located.location?.alive, true)
    }

    func testSignsTheSameMessageTheRuntimeVerifies() {
        XCTAssertEqual(
            confirmationMessage(subject: "prp_1", answer: "confirmed"),
            "memnox-confirm:v1:prp_1:confirmed"
        )
    }

    func testReadsALiveSessionWithItsConversation() throws {
        let response = try line(#"{"id":7,"ok":true,"session":{"sessionId":"ses_1","agent":"claude-code","agentName":"Claude Code","task":"add a cancel button","state":"working","thinking":true,"waitingOnYou":0,"helpers":[],"steps":[{"at":"t","surface":"git","text":"Pushed main","refused":true}],"files":[{"path":"src/Cart.tsx","added":4,"removed":1}],"conversation":[{"at":"t1","who":"person","text":"add a cancel button"},{"at":"t2","who":"tool","text":"Edit: Cart.tsx"}]}}"#)
        let view = try XCTUnwrap(response.session)
        XCTAssertEqual(view.conversation?.map(\.who), ["person", "tool"])
        XCTAssertEqual(view.steps.first?.refused, true)
        XCTAssertTrue(view.thinking)
    }

    func testSignsThePairingAndGrantMessagesTheRuntimeVerifies() {
        XCTAssertEqual(pairingMessage(pairingId: "pai_1", fingerprint: "fp_abc"), "memnox-pair:v1:pai_1:fp_abc")
        XCTAssertEqual(grantMessage(deviceId: "dev_1", capability: .rules), "memnox-grant:v1:dev_1:rules")
    }

    func testNamesThePairingMethodsAsTheRuntimeDoes() {
        let methods: [DaemonMethod] = [.pairBegin, .pairPending, .pairAccept, .pairDecline, .devicesList, .deviceRevoke, .deviceGrant, .voiceChoice]
        XCTAssertEqual(methods.map(\.rawValue), [
            "pair-begin", "pair-pending", "pair-accept", "pair-decline", "devices-list", "device-revoke", "device-grant", "voice-choice",
        ])
    }

    func testEncodesThePairingRequestFields() throws {
        var request = DaemonRequest(id: 4, method: .deviceGrant)
        request.deviceId = "dev_1"
        request.capability = Capability.rules.rawValue
        request.signature = "sig"
        let text = String(data: try encodeLine(request), encoding: .utf8)
        XCTAssertEqual(text, "{\"capability\":\"rules\",\"deviceId\":\"dev_1\",\"id\":4,\"method\":\"device-grant\",\"signature\":\"sig\"}\n")
    }

    func testRoundTripsAPairingAndADevice() throws {
        let invite = PairingInvite(id: "pai_1", qr: "memnox://pair?d=abc", expiresAt: "2026-10-05T00:05:00Z", state: "answered",
                                   phone: PairingPhone(name: "iPhone", fingerprint: "fp_abc", code: "482913"))
        let device = Device(id: "dev_1", name: "iPhone", kind: "phone", fingerprint: "fp_abc", capabilities: ["see", "ask", "teleport"],
                            pairedAt: "2026-10-05T00:00:00Z", revokedAt: "2026-10-06T00:00:00Z")
        XCTAssertEqual(try JSONDecoder().decode(PairingInvite.self, from: JSONEncoder().encode(invite)), invite)
        XCTAssertEqual(try JSONDecoder().decode(Device.self, from: JSONEncoder().encode(device)), device)
        XCTAssertEqual(invite.pairingState, .answered)
        XCTAssertEqual(device.deviceKind, .phone)
        XCTAssertEqual(device.granted, [.see, .ask])
        XCTAssertTrue(device.isRevoked)
    }

    func testReadsWhatThePairingMethodsAnswer() throws {
        let begun = try line(#"{"id":1,"ok":true,"outcome":"pairing","pairing":{"id":"pai_1","qr":"memnox://pair?d=abc","expiresAt":"t"}}"#)
        XCTAssertEqual(begun.outcomeKind, .pairing)
        XCTAssertEqual(begun.pairing?.qr, "memnox://pair?d=abc")
        let refused = try line(#"{"id":1,"ok":false,"outcome":"refused","reason":"Connect this Mac to Memnox Cloud first."}"#)
        XCTAssertEqual(refused.outcomeKind, .refused)
        XCTAssertEqual(refused.reason, "Connect this Mac to Memnox Cloud first.")
        let listed = try line(#"{"id":1,"ok":true,"devices":[{"id":"dev_1","name":"Mac","kind":"mac","fingerprint":"f","capabilities":[],"pairedAt":"t"}]}"#)
        XCTAssertEqual(listed.devices?.first?.deviceKind, .mac)
        let voice = try line(#"{"id":1,"ok":true,"voice":"af_heart"}"#)
        XCTAssertEqual(voice.voice, "af_heart")
        let unknown = try line(#"{"id":1,"ok":true,"outcome":"something new","pairing":{"id":"pai_1","state":"teleported"}}"#)
        XCTAssertNil(unknown.outcomeKind)
        XCTAssertNil(unknown.pairing?.pairingState)
    }

    func testOnlyPairedDeclinedAndExpiredEndAPairing() {
        XCTAssertEqual(PairingState.allCases.filter(\.isOver), [.paired, .declined, .expired])
    }

    func testNamesDriveAndMacAsTheRuntimeDoes() {
        XCTAssertEqual(DaemonMethod.drive.rawValue, "drive")
        XCTAssertEqual(Capability.mac.rawValue, "mac")
        XCTAssertEqual(grantMessage(deviceId: "dev_1", capability: .mac), "memnox-grant:v1:dev_1:mac")
        XCTAssertEqual(driveMessage(deviceId: "dev_1", until: "2026-10-05T10:15:00.000Z"), "memnox-drive:v1:dev_1:2026-10-05T10:15:00.000Z")
    }

    func testNamesUngrantAsTheRuntimeDoes() {
        XCTAssertEqual(DaemonMethod.deviceUngrant.rawValue, "device-ungrant")
        XCTAssertEqual(Outcome.ungranted.rawValue, "ungranted")
    }

    func testEncodesAnUngrantWithNoSignature() throws {
        var request = DaemonRequest(id: 7, method: .deviceUngrant)
        request.deviceId = "dev_1"
        request.capability = Capability.mac.rawValue
        let text = String(data: try encodeLine(request), encoding: .utf8)
        XCTAssertEqual(text, "{\"capability\":\"mac\",\"deviceId\":\"dev_1\",\"id\":7,\"method\":\"device-ungrant\"}\n")
    }

    func testReadsWhatUngrantAnswers() throws {
        let answer = try line(#"{"id":1,"ok":true,"outcome":"ungranted","device":{"id":"dev_1","name":"iPhone","kind":"phone","fingerprint":"fp","capabilities":["see"],"pairedAt":"p"}}"#)
        XCTAssertEqual(answer.outcomeKind, .ungranted)
        XCTAssertEqual(answer.device?.granted, [.see])
    }

    func testReadsAPhoneTurnOnANotice() throws {
        let started = try event(#"{"kind":"notice","subject":"ask_1","agent":"memnox","summary":"s","at":"t","phoneTurn":{"deviceId":"dev_1","name":"iPhone","said":"what changed"}}"#)
        XCTAssertEqual(started.phoneTurn, PhoneTurn(deviceId: "dev_1", name: "iPhone", said: "what changed"))
        let chunk = try event(#"{"kind":"notice","subject":"ask_1","agent":"memnox","summary":"s","at":"t","phoneTurn":{"deviceId":"dev_1","name":"iPhone","answer":"Two files"}}"#)
        XCTAssertEqual(chunk.phoneTurn?.answer, "Two files")
        XCTAssertNil(chunk.phoneTurn?.said)
        let ended = try event(#"{"kind":"notice","subject":"ask_1","agent":"memnox","summary":"s","at":"t","phoneTurn":{"deviceId":"dev_1","name":"iPhone","ended":true}}"#)
        XCTAssertEqual(ended.phoneTurn?.ended, true)
        XCTAssertNil(try event(#"{"kind":"notice","subject":"n","agent":"memnox","summary":"s","at":"t"}"#).phoneTurn)
    }

    func testRoundTripsAPhoneTurn() throws {
        for turn in [
            PhoneTurn(deviceId: "dev_1", name: "iPhone", said: "what changed"),
            PhoneTurn(deviceId: "dev_1", name: "iPhone", answer: "Two files"),
            PhoneTurn(deviceId: "dev_1", name: "iPhone", ended: true),
        ] {
            XCTAssertEqual(try JSONDecoder().decode(PhoneTurn.self, from: JSONEncoder().encode(turn)), turn)
        }
    }

    func testEncodesADriveWithItsUntil() throws {
        var request = DaemonRequest(id: 5, method: .drive)
        request.until = "2026-10-05T10:15:00.000Z"
        request.signature = "sig"
        let text = String(data: try encodeLine(request), encoding: .utf8)
        XCTAssertEqual(text, "{\"id\":5,\"method\":\"drive\",\"signature\":\"sig\",\"until\":\"2026-10-05T10:15:00.000Z\"}\n")
    }

    func testReadsWhatDriveAndARemoteAskAnswer() throws {
        let driving = try line(#"{"id":1,"ok":true,"outcome":"driving","until":"2026-10-05T10:15:00.000Z"}"#)
        XCTAssertEqual(driving.outcomeKind, .driving)
        XCTAssertEqual(driving.until, "2026-10-05T10:15:00.000Z")
        XCTAssertEqual(try line(#"{"id":1,"ok":true,"outcome":"stopped"}"#).outcomeKind, .stopped)
        let done = try line(#"{"id":2,"ok":true,"done":{"text":"Typed it into Claude Code"}}"#)
        XCTAssertEqual(done.done, DoneLine(text: "Typed it into Claude Code"))
        let asked = try line(#"{"id":3,"ok":true,"origin":{"deviceId":"dev_1"},"chunk":{"kind":"text","text":"On it."}}"#)
        XCTAssertEqual(asked.origin, Origin(deviceId: "dev_1"))
    }

    func testReadsAShowOnlyTheMacCanDoAndANoticeOfADrive() throws {
        let show = try event(#"{"kind":"show","subject":"dsp_1","agent":"memnox","summary":"open shop","at":"t","display":"folder","needsMac":true,"origin":{"deviceId":"dev_1"}}"#)
        XCTAssertEqual(show.needsMac, true)
        XCTAssertEqual(show.origin?.deviceId, "dev_1")
        let notice = try event(#"{"kind":"notice","subject":"drv_1","agent":"memnox","summary":"driving","at":"t","drivenBy":{"deviceId":"dev_1","name":"iPhone","until":"u"}}"#)
        XCTAssertEqual(notice.drivenBy, DrivenBy(deviceId: "dev_1", name: "iPhone", until: "u"))
        let plain = try event(#"{"kind":"show","subject":"dsp_2","agent":"memnox","summary":"s","at":"t"}"#)
        XCTAssertNil(plain.needsMac)
        XCTAssertNil(plain.origin)
        XCTAssertNil(plain.drivenBy)
    }

    func testRoundTripsTheDriveValues() throws {
        let drivenBy = DrivenBy(deviceId: "dev_1", name: "iPhone", until: "2026-10-05T10:15:00.000Z")
        XCTAssertEqual(try JSONDecoder().decode(DrivenBy.self, from: JSONEncoder().encode(drivenBy)), drivenBy)
        let ended = DrivenBy(deviceId: "dev_1", name: "iPhone")
        XCTAssertEqual(try JSONDecoder().decode(DrivenBy.self, from: JSONEncoder().encode(ended)), ended)
        XCTAssertEqual(try JSONDecoder().decode(Origin.self, from: JSONEncoder().encode(Origin(deviceId: "dev_1"))), Origin(deviceId: "dev_1"))
        XCTAssertEqual(try JSONDecoder().decode(DoneLine.self, from: JSONEncoder().encode(DoneLine(text: "Done"))), DoneLine(text: "Done"))
    }
}
