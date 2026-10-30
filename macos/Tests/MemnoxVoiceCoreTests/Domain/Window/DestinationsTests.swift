import XCTest

@testable import MemnoxVoiceCore

/// Mirrors shared/tauri-core/test/destinations.test.ts, so the window lays out the same on every desktop.
final class DestinationsTests: XCTestCase {
    private let nothingNew: Supports = { _ in false }
    private let everything: Supports = { _ in true }

    func testHidesATabUntilTheDaemonAnswersTheMethodItReads() {
        XCTAssertEqual(Destinations.visibleTabs(.mcp, supports: nothingNew).map(\.id), ["apps"])
        XCTAssertEqual(Destinations.visibleTabs(.mcp, supports: everything).map(\.id), ["servers", "clients", "secrets", "apps"])
        // Not asked yet is not a yes, so nothing shows before the daemon answers.
        XCTAssertEqual(Destinations.visibleTabs(.governance, supports: { _ in nil }).map(\.id), ["approvals"])
    }

    func testLandsOnTheFirstTabShownWhenTheOneAskedForIsHidden() {
        XCTAssertEqual(Destinations.settled(WindowRoute(.mcp, tab: "servers"), supports: nothingNew), WindowRoute(.mcp, tab: "apps"))
        XCTAssertEqual(Destinations.settled(WindowRoute(.home), supports: everything), WindowRoute(.home))
        XCTAssertEqual(Destinations.settled(WindowRoute(.settings), supports: nothingNew), WindowRoute(.settings, tab: "account"))
    }

    func testKeepsEveryOldSettingsLinkWorking() {
        XCTAssertEqual(Destinations.route(forPage: "overview"), WindowRoute(.home))
        XCTAssertEqual(Destinations.route(forPage: "phones"), WindowRoute(.settings, tab: "phones"))
        XCTAssertEqual(Destinations.route(forPage: "tools"), WindowRoute(.agents, tab: "computer"))
        XCTAssertEqual(Destinations.route(forPage: "apps"), WindowRoute(.mcp, tab: "apps"))
        XCTAssertEqual(Destinations.route(forPage: "voice"), WindowRoute(.settings, tab: "voice"))
        XCTAssertEqual(Destinations.route(forPage: "governance"), WindowRoute(.governance))
        XCTAssertNil(Destinations.route(forPage: "nowhere"))
    }

    func testChangesLayoutAtTheSameWidthsAsWindowsAndLinux() {
        XCTAssertEqual([1280, 1000, 760, 480].map { WidthClass(width: $0) }, [.wide, .medium, .narrow, .compact])
        XCTAssertEqual([1200, 900, 640].map { WidthClass(width: $0) }, [.wide, .medium, .narrow])
    }

    func testFindsAPlaceByAnyWordOfItTitlesThatStartWithItFirst() {
        let found = Destinations.matchCommands("app", supports: nothingNew).map(\.title)
        XCTAssertEqual(found.first, "Approvals")
        XCTAssertTrue(found.contains("Your apps"))
        XCTAssertEqual(Destinations.matchCommands("servers", supports: nothingNew), [])
        XCTAssertEqual(Destinations.matchCommands("  ", supports: nothingNew), Destinations.commands(supports: nothingNew))
    }

    func testGoesBackAndForwardThroughRoutesAsABrowserDoes() {
        var history = RouteHistory(WindowRoute(.home))
        history.visit(WindowRoute(.agents))
        history.visit(WindowRoute(.agents))
        history.visit(WindowRoute(.mcp, tab: "apps"))
        history.back()
        XCTAssertEqual(history.current, WindowRoute(.agents))
        XCTAssertTrue(history.canGoForward)
        history.visit(WindowRoute(.settings, tab: "voice"))
        XCTAssertFalse(history.canGoForward)
        history.back()
        history.back()
        history.back()
        XCTAssertEqual(history.current, WindowRoute(.home))
        XCTAssertFalse(history.canGoBack)
    }

    func testEveryDestinationButSettingsHasItsOwnDigit() {
        let keys = Destinations.all.compactMap(\.key)
        XCTAssertEqual(keys, ["1", "2", "3", "4", "5"])
        XCTAssertNil(Destinations.info(.settings).key)
    }
}
