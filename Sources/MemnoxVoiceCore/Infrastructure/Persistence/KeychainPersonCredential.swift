import Foundation
import Security

/// The signed in person's workspace credential, in the Keychain under its own service, so reading or
/// forgetting the paired servers never touches it and signing out never touches them.
public final class KeychainPersonCredential: PersonCredentialStore, @unchecked Sendable {
    public static let defaultService = "com.memnox.voice.person"
    private static let account = "workspace"
    private let service: String

    public init(service: String = KeychainPersonCredential.defaultService) {
        self.service = service
    }

    public func load() -> WorkspaceCredential? {
        var found: CFTypeRef?
        guard SecItemCopyMatching(item(reading: true) as CFDictionary, &found) == errSecSuccess, let data = found as? Data else { return nil }
        return try? JSONDecoder().decode(WorkspaceCredential.self, from: data)
    }

    public func save(_ credential: WorkspaceCredential) throws {
        let data = try JSONEncoder().encode(credential)
        delete()
        var adding = item(reading: false)
        adding[kSecValueData as String] = data
        // Readable after the first unlock, so a teammate's call can be answered from the island before a fresh unlock.
        adding[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(adding as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    public func delete() {
        SecItemDelete(item(reading: false) as CFDictionary)
    }

    /// The Keychain takes its queries as an untyped dictionary, so this is the one place one is built.
    private func item(reading: Bool) -> [String: Any] {
        var item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
        ]
        if reading {
            item[kSecReturnData as String] = true
            item[kSecMatchLimit as String] = kSecMatchLimitOne
        }
        return item
    }
}

/// The credential in memory, for tests and for a Mac that cannot reach its keychain.
public final class MemoryPersonCredential: PersonCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var kept: WorkspaceCredential?

    public init(_ credential: WorkspaceCredential? = nil) {
        kept = credential
    }

    public func load() -> WorkspaceCredential? {
        lock.lock()
        defer { lock.unlock() }
        return kept
    }

    public func save(_ credential: WorkspaceCredential) throws {
        lock.lock()
        kept = credential
        lock.unlock()
    }

    public func delete() {
        lock.lock()
        kept = nil
        lock.unlock()
    }
}
