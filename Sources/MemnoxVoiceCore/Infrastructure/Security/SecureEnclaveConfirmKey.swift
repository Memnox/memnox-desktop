import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// The real one: made in the Secure Enclave, usable only after Touch ID or the password, and
/// kept as the enclave's own opaque blob in the login keychain. It never leaves the chip.
public final class SecureEnclaveConfirmKey: ConfirmKey {
    /// The keychain service the app files its items under, its bundle identifier.
    private static let service = "com.memnox.voice"
    /// The one item under that service: the enclave's blob for the confirmation key.
    private static let account = "confirm-key"
    private let blob: Data
    public let publicPoint: String

    public init() throws {
        if let kept = Self.readBlob() {
            let key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: kept)
            blob = kept
            publicPoint = key.publicKey.x963Representation.base64EncodedString()
            return
        }
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage, .userPresence],
            &error
        ) else {
            // The function sets the error whenever it returns nil.
            throw error!.takeRetainedValue() as Error
        }
        let key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: access)
        try Self.writeBlob(key.dataRepresentation)
        blob = key.dataRepresentation
        publicPoint = key.publicKey.x963Representation.base64EncodedString()
    }

    public func sign(_ message: String, reason: String) async throws -> String? {
        let context = LAContext()
        context.localizedReason = reason
        do {
            let key = try SecureEnclave.P256.Signing.PrivateKey(
                dataRepresentation: blob,
                authenticationContext: context
            )
            return try key.signature(for: Data(message.utf8)).derRepresentation.base64EncodedString()
        } catch let error as LAError where error.code == .userCancel || error.code == .appCancel {
            // Cancelling the sheet is a no, said as one rather than as a failure.
            return nil
        }
    }

    private static func readBlob() -> Data? {
        var found: CFTypeRef?
        guard SecItemCopyMatching(keychainItem(.readBack), &found) == errSecSuccess else { return nil }
        return found as? Data
    }

    private static func writeBlob(_ data: Data) throws {
        let status = SecItemAdd(keychainItem(.storing(data)), nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    /// What a keychain call does with the key's item: read its blob back, or store a new one.
    private enum KeychainUse {
        case readBack
        case storing(Data)
    }

    /// The Keychain takes its queries as an untyped dictionary, so this is the one place one is built.
    private static func keychainItem(_ use: KeychainUse) -> CFDictionary {
        var item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        switch use {
        case .readBack: item[kSecReturnData as String] = true
        case .storing(let data): item[kSecValueData as String] = data
        }
        return item as CFDictionary
    }
}
