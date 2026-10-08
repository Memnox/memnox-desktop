import Foundation

/// One authenticated connection to the relay, carrying whole binary messages. A protocol, so the
/// tunnel and the pairing are tested against an in-memory relay with no network.
public protocol RelaySocket: AnyObject, Sendable {
    func send(_ message: Data) async throws
    /// The next binary message, throwing ProtocolError.disconnected once the connection is gone.
    func receive() async throws -> Data
    func close()
}

/// Opens relay connections with a bearer token: rlp_ while pairing, rly_ after.
public protocol RelayDialer: Sendable {
    func dial(_ url: URL, token: String) async throws -> RelaySocket
}
