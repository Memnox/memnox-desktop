import Foundation

/// Why a scanned code is not a pairing this phone can use.
public enum InvitationError: Error, Equatable {
    /// Not a memnox://pair link at all, such as a QR for something else.
    case notAPairingLink
    case unreadable
    /// A newer Mac than this app understands.
    case unsupportedVersion(Int)
    case expired
}

/// What the Mac's QR carries: where to meet it and how to know it is the right Mac. It holds no
/// lasting credential, since the secret works for one handshake and the token for 120 seconds.
public struct PairingInvitation: Equatable, Sendable {
    public let machineId: String
    public let machine: String
    public let relayURL: URL
    public let mailbox: Data
    /// The rlp_ token, single use, scoped to this mailbox.
    public let pairingToken: String
    /// The runtime's X25519 static key, which the handshake must end with or the phone walks away.
    public let runtimeStatic: Data
    /// The 32 byte PSK for XXpsk0.
    public let secret: Data
    public let expiresAt: Date

    /// The only QR version this app reads.
    public static let version = 1
    static let scheme = "memnox"
    static let host = "pair"
    static let payloadField = "d"
    /// Noise keys and the PSK are all 32 bytes.
    static let keyLength = 32

    /// Reads a scanned link, refusing one that is malformed, from a newer Mac, or past its expiry at `now`.
    public init(link: String, now: Date) throws {
        guard let parts = URLComponents(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme == Self.scheme, parts.host == Self.host,
              let payload = parts.queryItems?.first(where: { $0.name == Self.payloadField })?.value
        else { throw InvitationError.notAPairingLink }
        guard let json = Base64URL.decode(payload),
              let wire = try? JSONDecoder().decode(WireInvitation.self, from: json)
        else { throw InvitationError.unreadable }
        guard wire.v == Self.version else { throw InvitationError.unsupportedVersion(wire.v) }
        guard let relay = URL(string: wire.relayUrl),
              let mailbox = Base64URL.decode(wire.mailbox), mailbox.count == RelayFraming.mailboxLength,
              let runtimeStatic = Data(base64Encoded: wire.runtimeNoiseStatic), runtimeStatic.count == Self.keyLength,
              let secret = Data(base64Encoded: wire.secret), secret.count == Self.keyLength,
              let expiresAt = readInstant(wire.expiresAt),
              !wire.pairingToken.isEmpty
        else { throw InvitationError.unreadable }
        guard expiresAt > now else { throw InvitationError.expired }
        machineId = wire.machineId
        machine = wire.machine
        relayURL = relay
        self.mailbox = mailbox
        pairingToken = wire.pairingToken
        self.runtimeStatic = runtimeStatic
        self.secret = secret
        self.expiresAt = expiresAt
    }
}

/// The QR's JSON exactly as remote-contract.md spells it.
private struct WireInvitation: Decodable {
    let v: Int
    let machineId: String
    let machine: String
    let relayUrl: String
    let mailbox: String
    let pairingToken: String
    let runtimeNoiseStatic: String
    let secret: String
    let expiresAt: String
}

/// An ISO 8601 instant with or without fractional seconds, since JavaScript writes them with milliseconds.
public func readInstant(_ text: String) -> Date? {
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text)
}

/// An instant written the way the runtime writes one, with milliseconds, in UTC.
public func writeInstant(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}
