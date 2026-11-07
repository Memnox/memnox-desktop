import Foundation

/// How making a backup ended: the sealed archive and what it holds, or refused with why.
public enum BackupMade: Equatable, Sendable {
    case done(archive: String, summary: BackupSummary)
    case failed(String)
}

/// How reading one back ended: proposed and waiting on a signature, with what it holds, or refused.
public enum BackupRead: Equatable, Sendable {
    case proposed(id: String, summary: BackupSummary)
    case failed(String)
}

/// The words of the Backup page, mirrored from shared/tauri-core's backup-lines.ts.
public enum BackupLines {
    /// The shortest passphrase the runtime seals a backup under, so the form says so before it asks.
    public static let shortestPassphrase = 10

    /// What the passphrase fields say before Create or Restore is sent, or nil when they will do.
    public static func passphraseProblem(_ passphrase: String, again: String?) -> String? {
        if passphrase.count < shortestPassphrase { return "Use at least \(shortestPassphrase) characters." }
        if let again, again != passphrase { return "The two passphrases differ, so type it the same both times." }
        return nil
    }

    /// "memnox-backup-2026-10-30.txt", named by the day it was made so a folder of them sorts.
    public static func archiveFileName(_ createdAt: String) -> String {
        let day = createdAt.prefix(dayLength)
        let dated = day.count == dayLength && day.allSatisfy { $0.isNumber || $0 == "-" } && day.filter { $0 == "-" }.count == dashes
        return "memnox-backup-\(dated ? String(day) : "undated").txt"
    }

    /// What an archive holds, in a line, before anything is put back.
    public static func summaryLine(_ summary: BackupSummary) -> String {
        let files = summary.files.count == 1 ? "1 file" : "\(summary.files.count) files"
        return summary.ledger ? "\(files) and the ledger." : "\(files), without the ledger."
    }

    /// Said once a restore was read: nothing is put back until the person signs it on the island.
    public static let restoreWaitsLine =
        "Nothing is put back yet. It waits for your signature with Touch ID on the island, and then the setup in this backup replaces what is here."

    /// The ledger rides along only to a computer that has none, which the switch says before it is turned on.
    public static let ledgerLine = "It is only ever put back on a computer that has no ledger of its own."

    /// Said once a backup is made, so the passphrase is kept apart from the file.
    public static let keepApartLine = "Keep the passphrase somewhere apart from the file. Without it nobody, Memnox included, can open this backup."

    /// "2026-10-30" is ten characters with two dashes.
    private static let dayLength = 10
    private static let dashes = 2
}
