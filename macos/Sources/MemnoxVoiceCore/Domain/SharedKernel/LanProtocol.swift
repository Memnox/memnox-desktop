import Foundation

// The local network on the wire, mirrored from the runtime's daemon/lan.ts: off until the person turns it on, the same
// Noise sessions either way, and only ever a private address.

/// A paired phone with a live session over the local network now.
public struct LanPhone: Decodable, Equatable, Sendable {
    public let deviceId: String
    public let name: String

    public init(deviceId: String, name: String) {
        self.deviceId = deviceId
        self.name = name
    }
}

public struct LanStatus: Decodable, Equatable, Sendable {
    /// The person's setting: off until they turn it on.
    public let on: Bool
    /// A listener is up, which also needs a private address on this Mac.
    public let listening: Bool
    /// The private addresses it listens on; empty while off or with no private network.
    public let addresses: [String]
    /// The port each address listens on, while listening.
    public let port: Int?
    /// Announced over Bonjour under a random name that says nothing of the machine.
    public let advertised: Bool
    /// That random name, which the QR carries so a phone knows which announcement is this Mac.
    public let instance: String?
    public let reachable: [LanPhone]

    public init(on: Bool, listening: Bool, addresses: [String] = [], port: Int? = nil, advertised: Bool = false,
                instance: String? = nil, reachable: [LanPhone] = []) {
        self.on = on
        self.listening = listening
        self.addresses = addresses
        self.port = port
        self.advertised = advertised
        self.instance = instance
        self.reachable = reachable
    }
}
