import CryptoKit
import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Pairing a phone and looking after devices: every yes that widens what a phone can do is signed
/// over the exact string the runtime verifies, and a no or a cancel sends nothing signed.
final class PairingTests: XCTestCase {
    var link: ScriptedLink!
    var key: PersonKey!
    var pairing: Pairing!

    private let phone = PairingPhone(name: "Sam's iPhone", fingerprint: "fp_abc", code: "482913")
    private let device = Device(id: "dev_1", name: "Sam's iPhone", kind: "phone", fingerprint: "fp_abc",
                                capabilities: ["see", "ask", "answer", "steer"], pairedAt: "2026-10-05T00:00:00Z")

    override func setUp() {
        link = ScriptedLink()
        key = PersonKey()
        pairing = Pairing(link: link, key: key)
    }

    func testBeginsWithTheMacsNameAndHandsBackTheQR() async throws {
        link.answers["pair-begin"] = [try line(#"{"id":1,"ok":true,"outcome":"pairing","pairing":{"id":"pai_1","qr":"memnox://pair?d=abc","expiresAt":"2026-10-05T00:05:00Z"}}"#)]
        let start = await pairing.begin(name: "Studio Mac")
        XCTAssertEqual(start, .started(PairingInvite(id: "pai_1", qr: "memnox://pair?d=abc", expiresAt: "2026-10-05T00:05:00Z")))
        XCTAssertEqual(link.sent.first?.method, "pair-begin")
        XCTAssertEqual(link.sent.first?.name, "Studio Mac")
    }

    func testNamesWhatAGrantLetsADeviceDoInWordsRatherThanItsRawName() {
        XCTAssertEqual("let \(device.name) \(Capability.mac.allowing)", "let Sam's iPhone act on this Mac")
        for capability in Capability.allCases {
            XCTAssertNotEqual(capability.allowing, capability.rawValue)
        }
    }

    func testCarriesTheDaemonsReasonWhenThisMacIsNotOnMemnoxCloud() async throws {
        link.answers["pair-begin"] = [try line(#"{"id":1,"ok":false,"outcome":"refused","reason":"Connect this Mac to Memnox Cloud first."}"#)]
        let start = await pairing.begin()
        XCTAssertEqual(start, .refused("Connect this Mac to Memnox Cloud first."))
    }

    func testSaysTheDaemonIsUnreachableWhenNothingAnswers() async {
        link.unreachable = true
        let start = await pairing.begin()
        XCTAssertEqual(start, .unreachable)
    }

    func testBeginThenAcceptSignsThePairingAndThePhonesKey() async throws {
        link.answers["pair-begin"] = [try line(#"{"id":1,"ok":true,"outcome":"pairing","pairing":{"id":"pai_1","qr":"memnox://pair?d=abc","expiresAt":"2026-10-05T00:05:00Z"}}"#)]
        link.answers["pair-accept"] = [try line(#"{"id":2,"ok":true,"outcome":"paired","device":{"id":"dev_1","name":"Sam's iPhone","kind":"phone","fingerprint":"fp_abc","capabilities":["see","ask","answer","steer"],"pairedAt":"2026-10-05T00:00:00Z"}}"#)]
        guard case .started(let invite) = await pairing.begin() else { return XCTFail("the pairing did not open") }
        let answer = await pairing.accept(invite.id, phone: phone)
        XCTAssertEqual(answer, .paired(device))
        XCTAssertEqual(key.signed, ["memnox-pair:v1:pai_1:fp_abc"])
        let sent = try XCTUnwrap(link.sent.last)
        XCTAssertEqual(sent.method, "pair-accept")
        XCTAssertEqual(sent.pairingId, "pai_1")
        try assertSigned(sent.signature, over: "memnox-pair:v1:pai_1:fp_abc")
    }

    func testCancelledTouchIDSendsNoAccept() async {
        key.touches = false
        let answer = await pairing.accept("pai_1", phone: phone)
        XCTAssertEqual(answer, .cancelled)
        XCTAssertTrue(link.sent.isEmpty)
    }

    func testARefusedAcceptCarriesWhy() async throws {
        link.answers["pair-accept"] = [try line(#"{"id":1,"ok":false,"outcome":"refused","reason":"The pairing expired."}"#)]
        let answer = await pairing.accept("pai_1", phone: phone)
        XCTAssertEqual(answer, .refused("The pairing expired."))
    }

    func testDeclineGoesUnsigned() async throws {
        link.answers["pair-decline"] = [try line(#"{"id":1,"ok":true,"outcome":"declined"}"#)]
        let change = await pairing.decline("pai_1")
        XCTAssertEqual(change, .done)
        XCTAssertEqual(link.sent.first?.pairingId, "pai_1")
        XCTAssertNil(link.sent.first?.signature)
        XCTAssertTrue(key.signed.isEmpty)
    }

    func testRevokeGoesUnsigned() async throws {
        link.answers["device-revoke"] = [try line(#"{"id":1,"ok":true,"outcome":"revoked"}"#)]
        let change = await pairing.revoke(device)
        XCTAssertEqual(change, .done)
        XCTAssertEqual(link.sent.first?.deviceId, "dev_1")
        XCTAssertNil(link.sent.first?.signature)
        XCTAssertTrue(key.signed.isEmpty)
    }

    func testUngrantGoesUnsignedAndNamesTheCapability() async throws {
        link.answers["device-ungrant"] = [try line(#"{"id":1,"ok":true,"outcome":"ungranted","device":{"id":"dev_1","name":"Sam's iPhone","kind":"phone","fingerprint":"fp_abc","capabilities":["see","ask"],"pairedAt":"2026-10-05T00:00:00Z"}}"#)]
        let change = await pairing.ungrant(.answer, from: device)
        XCTAssertEqual(change, .done)
        let sent = try XCTUnwrap(link.sent.first)
        XCTAssertEqual(sent.method, "device-ungrant")
        XCTAssertEqual(sent.deviceId, "dev_1")
        XCTAssertEqual(sent.capability, "answer")
        XCTAssertNil(sent.signature)
        XCTAssertTrue(key.signed.isEmpty)
    }

    func testTurningDrivingOffTakesMacBackWithoutTouchID() async throws {
        let driving = Device(id: "dev_1", name: "Sam's iPhone", kind: "phone", fingerprint: "fp_abc",
                             capabilities: ["see", "ask", "mac"], pairedAt: "2026-10-05T00:00:00Z")
        link.answers["device-ungrant"] = [try line(#"{"id":1,"ok":true,"outcome":"ungranted","device":{"id":"dev_1","name":"Sam's iPhone","kind":"phone","fingerprint":"fp_abc","capabilities":["see","ask"],"pairedAt":"2026-10-05T00:00:00Z"}}"#)]
        // Even a person who would cancel the sheet can turn it off, since no sheet is raised.
        key.touches = false
        let change = await pairing.ungrant(.mac, from: driving)
        XCTAssertEqual(change, .done)
        XCTAssertEqual(link.sent.map(\.method), ["device-ungrant"])
        XCTAssertEqual(link.sent.first?.capability, "mac")
        XCTAssertNil(link.sent.first?.signature)
        XCTAssertTrue(key.signed.isEmpty)
    }

    func testARefusedUngrantCarriesWhy() async throws {
        link.answers["device-ungrant"] = [try line(#"{"id":1,"ok":false,"outcome":"refused","reason":"No such device."}"#)]
        let change = await pairing.ungrant(.mac, from: device)
        XCTAssertEqual(change, .refused("No such device."))
    }

    func testUngrantSaysTheDaemonIsUnreachableWhenNothingAnswers() async {
        link.unreachable = true
        let change = await pairing.ungrant(.mac, from: device)
        XCTAssertEqual(change, .unreachable)
    }

    func testGrantIsSignedOverTheDeviceAndTheCapability() async throws {
        link.answers["device-grant"] = [try line(#"{"id":1,"ok":true,"outcome":"granted"}"#)]
        let change = await pairing.grant(.rules, to: device)
        XCTAssertEqual(change, .done)
        let sent = try XCTUnwrap(link.sent.first)
        XCTAssertEqual(sent.deviceId, "dev_1")
        XCTAssertEqual(sent.capability, "rules")
        try assertSigned(sent.signature, over: "memnox-grant:v1:dev_1:rules")
    }

    func testLettingAPhoneDriveThisMacIsAGrantOfMacSignedWithTouchID() async throws {
        link.answers["device-grant"] = [try line(#"{"id":1,"ok":true,"outcome":"granted"}"#)]
        let change = await pairing.grant(.mac, to: device)
        XCTAssertEqual(change, .done)
        let sent = try XCTUnwrap(link.sent.first)
        XCTAssertEqual(sent.method, "device-grant")
        XCTAssertEqual(sent.capability, "mac")
        XCTAssertEqual(key.signed, ["memnox-grant:v1:dev_1:mac"])
        try assertSigned(sent.signature, over: "memnox-grant:v1:dev_1:mac")
    }

    func testCancelledTouchIDSendsNoGrant() async {
        key.touches = false
        let change = await pairing.grant(.rewind, to: device)
        XCTAssertEqual(change, .cancelled)
        XCTAssertTrue(link.sent.isEmpty)
    }

    func testPendingEndsOnceThePairingExpires() async throws {
        link.answers["pair-pending"] = [
            try line(#"{"id":1,"ok":true,"pairing":{"id":"pai_1","state":"waiting"}}"#),
            try line(#"{"id":1,"ok":true,"pairing":{"id":"pai_1","state":"expired"}}"#),
            try line(#"{"id":1,"ok":true,"pairing":{"id":"pai_1","state":"answered"}}"#),
        ]
        var states: [PairingState?] = []
        for try await invite in pairing.pending("pai_1") { states.append(invite.pairingState) }
        XCTAssertEqual(states, [.waiting, .expired])
        XCTAssertEqual(link.sent.first?.pairingId, "pai_1")
    }

    func testPendingHandsOverThePhoneToCheck() async throws {
        link.answers["pair-pending"] = [
            try line(#"{"id":1,"ok":true,"pairing":{"id":"pai_1","state":"answered","phone":{"name":"Sam's iPhone","fingerprint":"fp_abc","code":"482913"}}}"#),
        ]
        var phones: [PairingPhone] = []
        for try await invite in pairing.pending("pai_1") { if let phone = invite.phone { phones.append(phone) } }
        XCTAssertEqual(phones, [phone])
    }

    func testListsTheDevicesOrNoneWhenTheDaemonIsAway() async throws {
        link.answers["devices-list"] = [try line(#"{"id":1,"ok":true,"devices":[{"id":"dev_1","name":"Sam's iPhone","kind":"phone","fingerprint":"fp_abc","capabilities":["see","ask","answer","steer"],"pairedAt":"2026-10-05T00:00:00Z"}]}"#)]
        let found = await pairing.devices()
        XCTAssertEqual(found, [device])
        link.unreachable = true
        let none = await pairing.devices()
        XCTAssertEqual(none, [])
    }

    func testTellsTheDaemonTheVoicePicked() async throws {
        link.answers["voice-choice"] = [try line(#"{"id":1,"ok":true,"voice":"bf_emma"}"#)]
        let held = await pairing.tellVoice("bf_emma")
        XCTAssertEqual(held, "bf_emma")
        XCTAssertEqual(link.sent.first?.method, "voice-choice")
        XCTAssertEqual(link.sent.first?.voice, "bf_emma")
    }

    /// The signature verifies under the person's key over exactly this message.
    private func assertSigned(_ signature: String?, over message: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let der = try XCTUnwrap(signature.flatMap { Data(base64Encoded: $0) }, file: file, line: line)
        let point = try XCTUnwrap(Data(base64Encoded: key.publicPoint), file: file, line: line)
        let publicKey = try P256.Signing.PublicKey(x963Representation: point)
        let valid = publicKey.isValidSignature(try P256.Signing.ECDSASignature(derRepresentation: der), for: Data(message.utf8))
        XCTAssertTrue(valid, file: file, line: line)
    }
}
