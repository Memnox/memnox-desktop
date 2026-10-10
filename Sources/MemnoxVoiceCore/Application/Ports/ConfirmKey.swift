import Foundation

/// The key a confirmation is signed with. Only a person's fingerprint can use the real one,
/// so an agent running as the same user can raise the sheet but never finish an approval.
public protocol ConfirmKey: AnyObject {
    /// The public half as the daemon registers it: a base64 X9.63 P-256 point.
    var publicPoint: String { get }
    /// A base64 DER signature, or nil when the person declined or cancelled.
    func sign(_ message: String, reason: String) async throws -> String?
    /// One signature per message under one touch, in order, or nil when the person declined or cancelled.
    func sign(_ messages: [String], reason: String) async throws -> [String]?
}

extension ConfirmKey {
    /// Each in turn, for a key whose every signature costs nothing more than the first.
    public func sign(_ messages: [String], reason: String) async throws -> [String]? {
        var signatures: [String] = []
        for message in messages {
            guard let signature = try await sign(message, reason: reason) else { return nil }
            signatures.append(signature)
        }
        return signatures
    }
}
