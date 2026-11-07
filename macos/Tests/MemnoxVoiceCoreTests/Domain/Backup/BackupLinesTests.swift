import XCTest

@testable import MemnoxVoiceCore

/// Mirrors the wording half of shared/tauri-core/test/backup.test.ts.
final class BackupLinesTests: XCTestCase {
    private let summary = BackupSummary(createdAt: "2026-10-30T12:00:00.000Z", files: ["rules.toml", "hub.json"], ledger: true)

    func testAsksForTenCharactersTypedTheSameTwice() {
        XCTAssertEqual(BackupLines.passphraseProblem("short", again: "short"), "Use at least 10 characters.")
        XCTAssertEqual(BackupLines.passphraseProblem("long enough!", again: "long enough?"),
                       "The two passphrases differ, so type it the same both times.")
        XCTAssertNil(BackupLines.passphraseProblem("long enough!", again: "long enough!"))
        XCTAssertNil(BackupLines.passphraseProblem("long enough!", again: nil))
    }

    func testNamesTheFileByItsDayAndSaysWhatItHolds() {
        XCTAssertEqual(BackupLines.archiveFileName(summary.createdAt), "memnox-backup-2026-10-30.txt")
        XCTAssertEqual(BackupLines.archiveFileName("whenever"), "memnox-backup-undated.txt")
        XCTAssertEqual(BackupLines.summaryLine(summary), "2 files and the ledger.")
        XCTAssertEqual(BackupLines.summaryLine(BackupSummary(createdAt: "", files: ["a"], ledger: false)), "1 file, without the ledger.")
        XCTAssertTrue(BackupLines.restoreWaitsLine.contains("signature with Touch ID on the island"))
    }
}
