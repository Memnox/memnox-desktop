import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Pairing this Mac with a server from the link memnox pair printed: the digits come out for the person to
/// type there, the server is kept once it says yes, and every no is said in words the person can act on.
final class ServerPairingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_288_000) // 2026-10-06T12:00:00Z, before the link runs out.

    func testKeepsTheServerOnceItSaysYesAndHandsOverTheDigitsFirst() async {
        let store = MemoryPairedServers()
        let pairer = FakePairer(.success(pairedServer()))
        let pairing = ServerPairing(pairer: pairer, store: store, now: { [now] in now })
        let digits = Digits()
        let result = await pairing.connect(link: pairingLink(), name: "Studio Mac") { digits.code = $0 }

        XCTAssertEqual(result, .connected(pairedServer()))
        XCTAssertEqual(digits.code, "482913")
        XCTAssertEqual(store.all().map(\.machineId), ["mch_vps"])
        XCTAssertEqual(pairer.named, ["Studio Mac"])
    }

    func testRefusesALinkThatIsNotAPairingBeforeTouchingTheRelay() async {
        let pairer = FakePairer(.success(pairedServer()))
        let pairing = ServerPairing(pairer: pairer, store: MemoryPairedServers(), now: { [now] in now })
        let result = await pairing.connect(link: "https://example.com", name: "Mac") { _ in }
        XCTAssertEqual(result, .refused(ServerPairingLines.refused(.notAPairingLink)))
        XCTAssertEqual(pairer.named, [])
    }

    func testRefusesALinkThatRanOut() async {
        let pairing = ServerPairing(pairer: FakePairer(.success(pairedServer())), store: MemoryPairedServers(), now: { [now] in now })
        let result = await pairing.connect(link: pairingLink(expiresAt: "2026-10-06T11:00:00Z"), name: "Mac") { _ in }
        XCTAssertEqual(result, .refused(ServerPairingLines.refused(.expired)))
    }

    func testSaysWhyAndKeepsNothingWhenTheServerSaysNo() async {
        let store = MemoryPairedServers()
        for (failure, words) in [(PairingFailure.declined, ServerPairingLines.failed(.declined)),
                                 (.wrongMac, ServerPairingLines.failed(.wrongMac)),
                                 (.cancelled, ServerPairingLines.failed(.cancelled)),
                                 (.broken("no relay"), ServerPairingLines.unreachable)] {
            let pairing = ServerPairing(pairer: FakePairer(.failure(failure)), store: store, now: { [now] in now })
            let result = await pairing.connect(link: pairingLink(), name: "Mac") { _ in }
            XCTAssertEqual(result, .refused(words))
        }
        XCTAssertEqual(store.all(), [])
    }

    func testForgetsAServer() async {
        let store = MemoryPairedServers([pairedServer(), pairedServer("mch_other", name: "other")])
        let pairing = ServerPairing(pairer: FakePairer(.success(pairedServer())), store: store)
        pairing.forget("mch_vps")
        XCTAssertEqual(pairing.servers().map(\.machineId), ["mch_other"])
    }

    func testTheDigitsAreToBeTypedIntoMemnoxPairOnTheServer() {
        XCTAssertEqual(ServerPairingLines.typeCode, "Type these six digits into memnox pair on the server.")
    }

    func testTheTouchIDSheetNamesThisMacWhateverThePairerAsks() async throws {
        let person = PersonKey()
        let reasons = ReasonRecorder(person)
        let key = ReasonedKey(reasons, reason: ServerPairingLines.proofReason)
        _ = try await key.sign("memnox-device:v1:abc", reason: "Pair this iPhone with your Mac")
        XCTAssertEqual(reasons.reasons, [ServerPairingLines.proofReason])
        XCTAssertEqual(person.signed, ["memnox-device:v1:abc"])
        XCTAssertEqual(key.publicPoint, person.publicPoint)
    }

    func testAMacIntroducesItselfAsADesktopAndAPhoneAsNothingAtAll() throws {
        let mac = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            PhoneIntroduction(name: "Studio Mac", signingPoint: "BASE64", kind: IntroducedKind.desktop))) as? [String: String]
        XCTAssertEqual(mac, ["name": "Studio Mac", "signingPoint": "BASE64", "kind": "desktop"])
        let phone = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            PhoneIntroduction(name: "iPhone", signingPoint: "BASE64"))) as? [String: String]
        XCTAssertEqual(phone, ["name": "iPhone", "signingPoint": "BASE64"])
    }
}

/// A pairer that answers from a script and says the digits first, the way the real ceremony does.
private final class FakePairer: Pairer, @unchecked Sendable {
    private let answer: Result<PairedMachine, PairingFailure>
    private(set) var named: [String] = []

    init(_ answer: Result<PairedMachine, PairingFailure>) {
        self.answer = answer
    }

    func pair(_ invitation: PairingInvitation, name: String, code: @escaping @Sendable (String) -> Void) async throws -> PairedMachine {
        named.append(name)
        code("482913")
        return try answer.get()
    }
}

/// Where the digits land, from the pairer's own task.
private final class Digits: @unchecked Sendable {
    var code: String?
}

/// A key that writes down the words each sheet would show.
private final class ReasonRecorder: ConfirmKey {
    let inner: ConfirmKey
    var reasons: [String] = []
    init(_ inner: ConfirmKey) { self.inner = inner }
    var publicPoint: String { inner.publicPoint }
    func sign(_ message: String, reason: String) async throws -> String? {
        reasons.append(reason)
        return try await inner.sign(message, reason: reason)
    }
}
