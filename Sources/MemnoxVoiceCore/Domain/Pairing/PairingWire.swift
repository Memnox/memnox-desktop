import Foundation

// The payloads inside the pairing handshake and its first two transport lines, as remote-contract.md names them.

/// Message 2: the runtime names its Mac.
public struct RuntimeHello: Codable, Equatable, Sendable {
    public let machine: String

    public init(machine: String) { self.machine = machine }
}

/// Message 3: the phone names itself and the P256 point its yes will be signed with.
public struct PhoneIntroduction: Codable, Equatable, Sendable {
    public let name: String
    /// Base64 X9.63 P256.
    public let signingPoint: String
    /// "desktop" from a Mac; left out, or anything else, the runtime takes for a phone.
    public let kind: String?

    public init(name: String, signingPoint: String, kind: String? = nil) {
        self.name = name
        self.signingPoint = signingPoint
        self.kind = kind
    }
}

/// The kind a Mac names itself with in message 3, as remote-contract.md spells it.
public enum IntroducedKind {
    public static let desktop = "desktop"
}

/// The first transport line: a signature over deviceProofMessage, which proves the phone holds that key.
public struct DeviceProof: Codable, Equatable, Sendable {
    /// Base64 DER.
    public let proof: String

    public init(proof: String) { self.proof = proof }
}

/// The runtime's one line once the person decided on the Mac.
public struct PairingVerdict: Codable, Equatable, Sendable {
    public let paired: Bool
    public let deviceId: String?
    /// The rly_ token for this mailbox, until revoked.
    public let relayToken: String?
    /// The Kokoro voice the machine speaks with, so the phone can sound the same.
    public let voice: String?
    /// Whether the machine has a Kokoro voice to lend; a server usually has none, and then the phone never asks.
    public let speaks: Bool?

    public init(paired: Bool, deviceId: String? = nil, relayToken: String? = nil, voice: String? = nil, speaks: Bool? = nil) {
        self.paired = paired
        self.deviceId = deviceId
        self.relayToken = relayToken
        self.voice = voice
        self.speaks = speaks
    }
}
