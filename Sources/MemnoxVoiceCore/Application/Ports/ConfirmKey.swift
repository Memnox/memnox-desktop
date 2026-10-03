import Foundation

/// The key a confirmation is signed with. Only a person's fingerprint can use the real one,
/// so an agent running as the same user can raise the sheet but never finish an approval.
public protocol ConfirmKey: AnyObject {
    /// The public half as the daemon registers it: a base64 X9.63 P-256 point.
    var publicPoint: String { get }
    /// A base64 DER signature, or nil when the person declined or cancelled.
    func sign(_ message: String, reason: String) async throws -> String?
}
