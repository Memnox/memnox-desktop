import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// The Your apps screen: what the person has, the catalogue marked against it, and a count that is only ever counted.
final class YourAppsTests: XCTestCase {
    private let notion = ToolConnection(toolkit: "notion", connected: true)
    private let slack = ToolConnection(toolkit: "slack", connected: false)
    private let github = ToolConnection(toolkit: "github", connected: true, local: true)

    func testReadsALocalToolOffTheWireAndLeavesTheRestUnmarked() throws {
        let json = #"[{"toolkit":"github","connected":true,"local":true},{"toolkit":"notion","connected":true}]"#
        let all = try JSONDecoder().decode([ToolConnection].self, from: Data(json.utf8))
        XCTAssertEqual(all.map(\.isLocal), [true, false])
    }

    func testPutsWhatIsOnThisMacFirstAndTheRestByName() {
        let cards = YourApps.yours([slack, notion, github])
        XCTAssertEqual(cards.map(\.slug), ["github", "notion", "slack"])
        XCTAssertEqual(cards.map(\.standing), [.onThisMac, .connected, .signInAgain])
    }

    func testNamesAToolOnceWhenTheListCarriesItTwice() {
        XCTAssertEqual(YourApps.yours([notion, notion]).count, 1)
    }

    func testMarksTheCatalogueAgainstWhatThePersonHas() {
        let found = [
            ToolkitSummary(slug: "notion", name: "Notion", logo: "https://logos.example/notion"),
            ToolkitSummary(slug: "github", name: "GitHub"),
            ToolkitSummary(slug: "asana", name: "Asana"),
        ]
        let cards = YourApps.catalogue(found, connections: [notion, github])
        XCTAssertEqual(cards.map(\.standing), [.connected, .onThisMac, .available])
        XCTAssertEqual(cards.first?.logo, "https://logos.example/notion")
    }

    func testOffersTheFeaturedToolsOnlyWhenTheCatalogueCouldNotBeReadUnasked() {
        let offered = YourApps.offered(found: [], searchFailed: true, query: "", connections: [])
        XCTAssertEqual(offered.map(\.slug), FeaturedToolkits.slugs)
        XCTAssertTrue(YourApps.offered(found: [], searchFailed: true, query: "asana", connections: []).isEmpty)
    }

    func testCountsTheResultsAndNeverEstimatesThem() {
        XCTAssertEqual(YourApps.countLine(30, query: ""), "30 apps")
        XCTAssertEqual(YourApps.countLine(1, query: "notion"), "1 app matches \u{201C}notion\u{201D}")
        XCTAssertEqual(YourApps.countLine(0, query: " zz "), "No app matches \u{201C}zz\u{201D}")
    }

    func testNeverAsksForAnAccountToConnect() {
        let lines = [YourAppStanding.onThisMac, .connected, .signInAgain, .available].map(\.line)
        XCTAssertFalse(lines.contains { $0.localizedCaseInsensitiveContains("account") && !$0.contains("your own account") })
        XCTAssertFalse(lines.contains { $0.contains("memnox.com") })
    }
}
