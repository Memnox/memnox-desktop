import Foundation

/// Backing up what a person set up on this Mac and putting it back. It holds no rule and no secret: the runtime seals
/// the archive under the passphrase, and a restore waits for a signature on the island.
public final class Backup: @unchecked Sendable {
    private let link: DaemonLink
    private let ids: RequestIds

    public init(link: DaemonLink, ids: RequestIds = RequestIds()) {
        self.link = link
        self.ids = ids
    }

    public func create(passphrase: String, ledger: Bool) async -> BackupMade {
        var request = DaemonRequest(id: ids.next(), method: .backupCreate)
        request.backupPassphrase = passphrase
        request.backupLedger = ledger
        guard let response = await ask(request) else { return .failed("The runtime is not answering.") }
        guard response.ok else { return .failed(response.error ?? "The runtime refused this.") }
        guard let archive = response.backupArchive, let summary = response.backupSummary else { return .failed("The runtime made no backup.") }
        return .done(archive: archive, summary: summary)
    }

    public func restore(archive: String, passphrase: String) async -> BackupRead {
        var request = DaemonRequest(id: ids.next(), method: .backupRestore)
        request.backupArchive = archive.trimmingCharacters(in: .whitespacesAndNewlines)
        request.backupPassphrase = passphrase
        guard let response = await ask(request) else { return .failed("The runtime is not answering.") }
        guard response.ok else { return .failed(response.error ?? "The runtime refused this.") }
        guard let proposed = response.proposed, let summary = response.backupSummary else {
            return .failed("The runtime proposed nothing to put back.")
        }
        return .proposed(id: proposed, summary: summary)
    }

    /// A runtime that went away is said by the outcome, never thrown at the page.
    private func ask(_ request: DaemonRequest) async -> DaemonResponse? {
        try? await link.request(request)
    }
}
