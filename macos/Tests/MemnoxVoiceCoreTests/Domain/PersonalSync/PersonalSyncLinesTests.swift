import XCTest

@testable import MemnoxVoiceCore

/// Mirrors the wording half of shared/tauri-core/test/personal-sync.test.ts, with Touch ID named.
final class PersonalSyncLinesTests: XCTestCase {
    func testSaysEachStateInAWordAndCountsWhatThisMacCarries() {
        XCTAssertEqual(PersonalSyncLines.stateWord(.ready).word, "On")
        XCTAssertEqual(PersonalSyncLines.stateWord(.ready).tone, .good)
        XCTAssertEqual(PersonalSyncLines.stateWord(.keyArrived).word, "Key arrived")
        XCTAssertEqual(PersonalSyncLines.stateWord(.notOnPlan).word, "Not on your plan")
        XCTAssertEqual(PersonalSyncLines.kindCount(PersonalSyncKindCount(kind: "servers", items: 3)), "3 MCP servers")
        XCTAssertEqual(PersonalSyncLines.kindCount(PersonalSyncKindCount(kind: "memory", items: 1)), "1 memory fact")
        XCTAssertEqual(PersonalSyncLines.kindCount(PersonalSyncKindCount(kind: "other", items: 2)), "2 other")
        XCTAssertEqual(PersonalSyncLines.kindTile(PersonalSyncKindCount(kind: "skills", items: 2)), ProjectTile(value: 2, label: "Skills"))
    }

    func testSplitsAFingerprintIntoItsSixGroupsWrittenOrNot() {
        XCTAssertEqual(PersonalSyncLines.fingerprintGroups("12345 67890 11121 31415 16171 81920"),
                       ["12345", "67890", "11121", "31415", "16171", "81920"])
        XCTAssertEqual(PersonalSyncLines.fingerprintGroups("123456789011121314151617181920").count, 6)
    }

    func testSaysWhenItLastRanTheConflictsWhatWasOpenedElsewhereAndWhatWaitsOnTouchID() {
        let conflict = PersonalSyncConflict(id: "c_1", kind: "skills", name: "release-notes", writtenBy: "laptop",
                                            keptAt: "2026-10-30T10:00:00Z", theirs: "v2", mine: "v3")
        XCTAssertEqual(PersonalSyncLines.lastSyncedLine(nil), "Not synced on this machine yet.")
        XCTAssertEqual(PersonalSyncLines.lastSyncedLine("5 min ago"), "Last synced 5 min ago.")
        XCTAssertEqual(PersonalSyncLines.conflictsLine(0), "No conflicts.")
        XCTAssertEqual(PersonalSyncLines.conflictsLine(2), "2 conflicts to choose between.")
        XCTAssertEqual(PersonalSyncLines.conflictCaption(conflict, kept: "1 h ago"), "Skill written on laptop, kept 1 h ago")
        XCTAssertEqual(PersonalSyncLines.openedElsewhereLine(1), "1 repository opened on your other machines and not on this one.")
        XCTAssertEqual(PersonalSyncLines.keyWaitsLine(offering: true),
                       "Nothing moves yet. Giving the key waits for your signature with Touch ID on the island.")
        XCTAssertTrue(PersonalSyncLines.keyWaitsLine(offering: false).contains("Taking the key"))
    }
}
