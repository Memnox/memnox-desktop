import XCTest

@testable import MemnoxVoiceCore

/// The Skills page's words for use and fixes, and the connector order chips.
final class SkillCareLinesTests: XCTestCase {
    func testSaysUsesFailuresAndRefusalsOrThatItWasNotUsed() {
        XCTAssertEqual(SkillCareLines.counts(nil), "Not used in the last 30 days")
        XCTAssertEqual(SkillCareLines.counts(SkillStatsView(name: "r", uses: 1, failures: 2, refusals: 1)),
                       "Used once, 2 failures, 1 refusal in the last 30 days")
    }

    func testSaysWhatCalibrateBuildsFromBeforeItIsPressed() {
        XCTAssertEqual(SkillCareLines.calibrateHint(SkillStatsView(name: "r", uses: 0, failures: 0, refusals: 0)),
                       "Nothing noted and nothing failed, so there is no fix to suggest.")
        XCTAssertEqual(SkillCareLines.calibrateHint(SkillStatsView(name: "r", uses: 2, failures: 1, refusals: 0, notes: ["a"],
                                                                   recentFailures: ["exit 1", "exit 2"])),
                       "Builds a Known issues section from 1 note and 2 failures.")
        XCTAssertEqual(SkillCareLines.note("  use the staged diff\n please "), "use the staged diff  please")
        XCTAssertNil(SkillCareLines.note(" \n "))
    }

    func testChipsEachConnectorByWhereItComesFrom() {
        XCTAssertEqual(ConnectorSource.allCases.map(ConnectorOrderLines.chip), ["Official", "CLI", "API", "Community MCP"])
        XCTAssertEqual(ConnectorOrderLines.chip(for: ToolkitSummary(slug: "gmail", name: "Gmail", source: "official", weight: 4)),
                       "Official 4")
        XCTAssertNil(ConnectorOrderLines.chip(for: ToolkitSummary(slug: "gmail", name: "Gmail")))
    }

    func testCarriesTheOrderChipFromTheCatalogueOntoItsCard() {
        let cards = YourApps.catalogue([ToolkitSummary(slug: "gmail", name: "Gmail", source: "cli", weight: 3)], connections: [])
        XCTAssertEqual(cards.first?.orderChip, "CLI 3")
        XCTAssertNil(YourApps.catalogue([ToolkitSummary(slug: "gmail", name: "Gmail")], connections: []).first?.orderChip)
    }
}
