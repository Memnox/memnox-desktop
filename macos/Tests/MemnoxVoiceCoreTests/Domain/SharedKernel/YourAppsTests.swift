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

    func testSaysAConnectedAppIsReachedThroughMemnoxAndNamesTheAgentsThatUsedItLately() throws {
        let json = #"[{"toolkit":"linear","connected":true,"usedBy":[{"agent":"claude-code","sessionId":"s1","at":"x"},{"agent":"codex","at":"y"}]},{"toolkit":"notion","connected":true},{"toolkit":"slack","connected":false}]"#
        let cards = YourApps.yours(try JSONDecoder().decode([ToolConnection].self, from: Data(json.utf8)))
        let name: (String) -> String = { $0 == "claude-code" ? "Claude Code" : "Codex" }
        XCTAssertEqual(cards.map { $0.agentsLine(name: name) }, [
            "Your agents can use it through Memnox. Used lately by Claude Code and Codex",
            "Your agents can use it through Memnox",
            nil,
        ])
        XCTAssertEqual(cards.first?.uses.first?.sessionId, "s1")
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

    func testReadsWhenEachToolWasConnectedOffTheWire() throws {
        let json = #"[{"toolkit":"slack","connected":true,"connectedAt":"2026-10-02T12:00:00.000Z"},{"toolkit":"notion","connected":true}]"#
        let all = try JSONDecoder().decode([ToolConnection].self, from: Data(json.utf8))
        XCTAssertEqual(all.map(\.connectedAt), ["2026-10-02T12:00:00.000Z", nil])
    }

    func testSaysConnectedSinceTheDateOrNotConnectedAsTheConsoleDoes() {
        let since = ToolConnection(toolkit: "slack", connected: true, connectedAt: "2026-10-02T12:00:00Z")
        let cards = YourApps.catalogue([ToolkitSummary(slug: "slack", name: "Slack"), ToolkitSummary(slug: "asana", name: "Asana")],
                                       connections: [since])
        XCTAssertEqual(cards.map(\.statusLine), ["Connected since Oct 2, 2026", "Not connected"])
        XCTAssertEqual(YourApps.yours([notion]).first?.statusLine, "Connected")
    }

    func testDrawsTheCloudsKindDescriptionAndSupportInTheConsolesWords() {
        let found = [
            ToolkitSummary(slug: "github", name: "GitHub", description: "  Code hosting.  ", categories: ["Developer Tools"],
                           kind: "record", support: "full"),
            ToolkitSummary(slug: "gmail", name: "Gmail", kind: "conversation", support: "partial"),
            ToolkitSummary(slug: "asana", name: "Asana"),
        ]
        let cards = YourApps.catalogue(found, connections: [])
        XCTAssertEqual(cards.map(\.kindLine), ["System of record", "System of conversation", nil])
        XCTAssertEqual(cards.map(\.supportPill), ["Fully supported", "Limited support", nil])
        XCTAssertEqual(cards.first?.description, "Code hosting.")
        // A connected tool's card borrows what the catalogue said of it.
        XCTAssertEqual(YourApps.yours([github], found: found).first?.categories, ["Developer Tools"])
    }

    func testCountsCategoriesOncePerCardCommonestFirstInTheConsolesSpelling() {
        let cards = [
            YourAppCard(slug: "a", name: "A", standing: .available, categories: ["Team Chat", "team-chat", "crm"]),
            YourAppCard(slug: "b", name: "B", standing: .available, categories: ["team-chat"]),
            YourAppCard(slug: "c", name: "C", standing: .available, categories: ["CRM", "collaboration-&-communication"]),
        ]
        let rail = YourApps.categories(cards)
        XCTAssertEqual(rail.map(\.label), ["CRM", "Team Chat", "Collaboration-&-communication"])
        XCTAssertEqual(rail.map(\.count), [2, 2, 1])
        XCTAssertEqual(rail.last?.id, "collaboration-and-communication")
        XCTAssertEqual(cards.filter { YourApps.inCategory($0, "team-chat") }.map(\.slug), ["a", "b"])
        XCTAssertEqual(cards.filter { YourApps.inCategory($0, nil) }.count, 3)
        XCTAssertEqual(YourApps.showingLine(2, of: 3), "2 of 3")
    }

    func testPromisesNothingBeforeASignInAndAsksForMemnoxCloudToConnect() {
        XCTAssertFalse(YourApps.allowanceLine.contains("100"))
        XCTAssertTrue(YourApps.allowanceLine.contains("once you sign in to Memnox Cloud"))
        XCTAssertEqual(YourApps.signInTitle, "Sign in to Memnox Cloud to connect")
        let copy = [YourApps.allowanceLine, YourApps.signInTitle, YourApps.signInDetail, YourApps.signInButton, YourApps.signInStopped]
        XCTAssertFalse(copy.contains { $0.contains("\u{2014}") || $0.contains("\u{2013}") || $0.contains(" - ") })
    }
}
