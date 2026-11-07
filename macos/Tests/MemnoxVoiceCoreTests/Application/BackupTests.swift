import XCTest

@testable import MemnoxVoiceCore

/// Mirrors the use case half of shared/tauri-core/test/backup.test.ts.
final class BackupTests: XCTestCase {
    private static let summaryJSON = #"{"createdAt":"2026-10-30T12:00:00.000Z","files":["rules.toml","hub.json"],"ledger":true}"#
    private let summary = BackupSummary(createdAt: "2026-10-30T12:00:00.000Z", files: ["rules.toml", "hub.json"], ledger: true)

    func testHandsBackTheSealedArchiveAndWhatItHoldsSendingTheLedgerSwitch() async throws {
        let link = ScriptedLink()
        link.answers["backup-create"] = [try line(#"{"id":1,"ok":true,"backupArchive":"sealed","backupSummary":"# + Self.summaryJSON + "}")]
        let made = await Backup(link: link).create(passphrase: "a long passphrase", ledger: true)
        XCTAssertEqual(made, .done(archive: "sealed", summary: summary))
        XCTAssertEqual(link.sent.first?.backupPassphrase, "a long passphrase")
        XCTAssertEqual(link.sent.first?.backupLedger, true)
    }

    func testProposesARestoreRatherThanPuttingAnythingBackAndPassesARefusalOn() async throws {
        let link = ScriptedLink()
        link.answers["backup-restore"] = [try line(#"{"id":1,"ok":true,"proposed":"prp_2","backupSummary":"# + Self.summaryJSON + "}")]
        let read = await Backup(link: link).restore(archive: " sealed\n", passphrase: "a long passphrase")
        XCTAssertEqual(read, .proposed(id: "prp_2", summary: summary))
        XCTAssertEqual(link.sent.first?.backupArchive, "sealed")

        let wrong = ScriptedLink()
        wrong.answers["backup-restore"] = [try line(#"{"id":1,"ok":false,"error":"That passphrase does not open this backup."}"#)]
        let refused = await Backup(link: wrong).restore(archive: "sealed", passphrase: "a long passphrase")
        XCTAssertEqual(refused, .failed("That passphrase does not open this backup."))

        let down = ScriptedLink()
        down.unreachable = true
        let gone = await Backup(link: down).create(passphrase: "a long passphrase", ledger: false)
        XCTAssertEqual(gone, .failed("The runtime is not answering."))
    }
}
