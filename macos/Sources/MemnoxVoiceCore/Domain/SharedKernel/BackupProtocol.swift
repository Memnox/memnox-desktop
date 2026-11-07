import Foundation

// Backing up on the wire, mirrored from the runtime's daemon/backup.ts: rules, hubs, skills, projects and memory,
// sealed under a passphrase and never a secret, and put back only once the person signs it.

/// What an archive holds, so a screen says it before anything is restored.
public struct BackupSummary: Decodable, Equatable, Sendable {
    public let createdAt: String
    /// Under the Memnox home, by path.
    public let files: [String]
    /// The ledger rides along; it is only ever restored where there is none.
    public let ledger: Bool

    public init(createdAt: String, files: [String], ledger: Bool) {
        self.createdAt = createdAt
        self.files = files
        self.ledger = ledger
    }
}
