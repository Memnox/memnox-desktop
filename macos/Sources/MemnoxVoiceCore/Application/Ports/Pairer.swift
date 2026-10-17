import Foundation

/// Why pairing stopped short of a paired Mac.
public enum PairingFailure: Error, Equatable {
    /// The runtime's static key is not the one in the QR, so somebody else answered.
    case wrongMac
    /// The person said no on the Mac.
    case declined
    /// Face ID was cancelled, so no proof was sent.
    case cancelled
    /// The relay or the handshake failed, with what the library or the network said.
    case broken(String)
}

/// Runs the pairing ceremony with the Mac in a scanned QR: the XXpsk0 handshake, the proof, and the wait for the person's answer.
public protocol Pairer: Sendable {
    /// Calls `code` with the six digits as soon as the handshake ends, then waits for the Mac's verdict.
    func pair(_ invitation: PairingInvitation, name: String, code: @escaping @Sendable (String) -> Void) async throws -> PairedMachine
}
