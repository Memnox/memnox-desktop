import Foundation
import Security

/// The servers this Mac paired with, in the Keychain, one item per machine. Each record holds a Noise
/// private key and a relay token, so it is kept beside the confirmation key rather than in defaults.
public final class KeychainPairedServers: PairedStore, @unchecked Sendable {
    /// Apart from the confirmation key's service, so reading every server never reads that key.
    public static let defaultService = "com.memnox.voice.servers"
    private static let accountPrefix = "server-"
    private let service: String

    public init(service: String = KeychainPairedServers.defaultService) {
        self.service = service
    }

    public func all() -> [PairedMachine] {
        var found: CFTypeRef?
        guard SecItemCopyMatching(item(.listAccounts), &found) == errSecSuccess,
              let rows = found as? [[String: Any]] else { return [] }
        // The login keychain lists many items in one call but hands back their data only one at a time.
        let servers = rows.compactMap { row -> PairedMachine? in
            guard let account = row[kSecAttrAccount as String] as? String else { return nil }
            var data: CFTypeRef?
            guard SecItemCopyMatching(item(.read(account)), &data) == errSecSuccess,
                  let bytes = data as? Data else { return nil }
            return try? JSONDecoder().decode(PairedMachine.self, from: bytes)
        }
        return PairedMachines.distinct(servers)
    }

    public func save(_ server: PairedMachine) throws {
        let data = try JSONEncoder().encode(server)
        forget(machineId: server.machineId)
        let status = SecItemAdd(item(.storing(Self.account(server.machineId), data)), nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    public func forget(machineId: String) {
        SecItemDelete(item(.match(Self.account(machineId))))
    }

    private static func account(_ machineId: String) -> String { accountPrefix + machineId }

    private enum KeychainUse {
        case match(String)
        case listAccounts
        case read(String)
        case storing(String, Data)
    }

    /// The Keychain takes its queries as an untyped dictionary, so this is the one place one is built.
    private func item(_ use: KeychainUse) -> CFDictionary {
        var item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        switch use {
        case .match(let account):
            item[kSecAttrAccount as String] = account
        case .listAccounts:
            item[kSecReturnAttributes as String] = true
            item[kSecMatchLimit as String] = kSecMatchLimitAll
        case .read(let account):
            item[kSecAttrAccount as String] = account
            item[kSecReturnData as String] = true
            item[kSecMatchLimit as String] = kSecMatchLimitOne
        case .storing(let account, let data):
            item[kSecAttrAccount as String] = account
            item[kSecValueData as String] = data
            // Readable after the first unlock, so a server's held call can still be answered from a locked screen's island.
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
        return item as CFDictionary
    }
}

/// The servers in memory, for tests and for a Mac that cannot reach its keychain.
public final class MemoryPairedServers: PairedStore, @unchecked Sendable {
    private let lock = NSLock()
    private var kept: [PairedMachine]

    public init(_ servers: [PairedMachine] = []) {
        kept = servers
    }

    public func all() -> [PairedMachine] {
        lock.lock()
        defer { lock.unlock() }
        return PairedMachines.distinct(kept)
    }

    public func save(_ server: PairedMachine) throws {
        lock.lock()
        kept = kept.filter { $0.machineId != server.machineId } + [server]
        lock.unlock()
    }

    public func forget(machineId: String) {
        lock.lock()
        kept.removeAll { $0.machineId == machineId }
        lock.unlock()
    }
}
