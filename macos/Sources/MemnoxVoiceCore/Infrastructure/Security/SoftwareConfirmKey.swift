import CryptoKit
import Foundation

/// A key in memory, for tests and for checking the runtime verifies what CryptoKit signs.
public final class SoftwareConfirmKey: ConfirmKey {
    private let key = P256.Signing.PrivateKey()

    public init() {}

    public var publicPoint: String { key.publicKey.x963Representation.base64EncodedString() }

    public func sign(_ message: String, reason: String) async throws -> String? {
        try key.signature(for: Data(message.utf8)).derRepresentation.base64EncodedString()
    }
}
