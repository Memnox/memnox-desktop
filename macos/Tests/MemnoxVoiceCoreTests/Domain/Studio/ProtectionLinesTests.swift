import XCTest

@testable import MemnoxVoiceCore

/// Mirrors shared/tauri-core/test/protection-lines.test.ts, so both desktops say the console's words.
final class ProtectionLinesTests: XCTestCase {
    func testListsTheTabsInTheConsolesOrder() {
        XCTAssertEqual(ProtectionTab.shown.map(\.title), ["Ready-made rules", "All rules"])
    }

    func testSaysTheConsolesWordsForTheReadyMadeRules() {
        XCTAssertEqual(ProtectionLines.search, "Search by tool, command or what it protects: kubectl, refund, secrets")
        XCTAssertEqual(ProtectionLines.starter, "Add the starter set")
        XCTAssertEqual(ProtectionLines.noneMatch, "No ready-made rule matches that. Propose your own under All rules.")
        XCTAssertEqual(ProtectionLines.inForceAs(.ask), "In force as ask")
        XCTAssertEqual(ProtectionLines.readyIntro(keyTitle: "Touch ID"),
                       "Rules written for you. Choose Allow, Ask or Deny on one; it holds once you confirm it with Touch ID.")
    }

    func testSavesTheWayTheConsolesChoicesSave() {
        XCTAssertEqual([ProtectionLines.notSaved, ProtectionLines.undo, ProtectionLines.review], ["Not saved yet", "Undo", "Review and save"])
        XCTAssertEqual(ProtectionLines.previewed, "Not saved yet. Nothing has changed.")
        XCTAssertEqual(ProtectionLines.reviewDescription(keyTitle: "Touch ID"),
                       "Saving proposes each change, and it takes effect once you confirm it with Touch ID on the island.")
    }

    func testPointsBetweenTheTabsAsTheConsoleDoes() {
        XCTAssertEqual(ProtectionLines.simplerTitle, "Want the simple version?")
        XCTAssertEqual(ProtectionLines.startTitle, "Start from a ready-made rule")
        XCTAssertEqual(ProtectionLines.handOver, "See what to hand over")
        XCTAssertEqual(ProtectionLines.readyToHandOver, "Ready to hand over")
        XCTAssertEqual(ProtectionLines.stopAsking, "Stop asking")
    }

    func testNoLineHoldsADash() {
        let lines = [ProtectionLines.readyIntro(keyTitle: "Touch ID"), ProtectionLines.search, ProtectionLines.noneMatch,
                     ProtectionLines.reviewDescription(keyTitle: "Touch ID"), ProtectionLines.allIntro, ProtectionLines.simplerNote,
                     ProtectionLines.startNote, ProtectionLines.noRulesBody, ProtectionLines.autonomyIntro,
                     ProtectionLines.nothingReadyBody, ProtectionLines.almostCaption]
        for line in lines {
            XCTAssertFalse(line.contains("\u{2014}") || line.contains("\u{2013}") || line.contains(" - "), line)
        }
    }
}
