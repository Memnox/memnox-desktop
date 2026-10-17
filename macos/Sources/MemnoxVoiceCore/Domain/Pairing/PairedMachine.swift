import Foundation

/// Everything the phone keeps about one machine it paired with: a Mac, or a server it reaches over the relay.
/// The Noise private key and the rly_ token are secrets, so the whole record lives in the Keychain.
public struct PairedMachine: Codable, Equatable, Sendable {
    public let machineId: String
    public let machine: String
    public let relayURL: URL
    public let mailbox: Data
    /// This phone's id in the runtime's device registry, which the drive grant names.
    public let deviceId: String
    public let relayToken: String
    /// The runtime's X25519 static key, the one every IK handshake must reach.
    public let runtimeStatic: Data
    /// This phone's X25519 private key, made for this pairing.
    public let phonePrivateKey: Data
    /// The machine's Kokoro voice when it paired, nil when it named none.
    public var voice: String?
    /// Whether the machine has a Kokoro voice to lend; nil for a runtime too old to say, which is asked anyway.
    public var speaks: Bool?
    public let pairedAt: Date

    public init(machineId: String, machine: String, relayURL: URL, mailbox: Data, deviceId: String, relayToken: String,
                runtimeStatic: Data, phonePrivateKey: Data, voice: String?, speaks: Bool? = nil, pairedAt: Date) {
        self.machineId = machineId
        self.machine = machine
        self.relayURL = relayURL
        self.mailbox = mailbox
        self.deviceId = deviceId
        self.relayToken = relayToken
        self.runtimeStatic = runtimeStatic
        self.phonePrivateKey = phonePrivateKey
        self.voice = voice
        self.speaks = speaks
        self.pairedAt = pairedAt
    }
}

extension PairedMachine {
    /// Whether to ask the machine to speak a sentence: yes unless it said it has no voice to lend.
    public var lendsVoice: Bool { speaks != false }
}
