import XCTest

@testable import MemnoxVoiceCore

/// Mirrors shared/tauri-core/test/destinations.test.ts, so the window lays out the same on every desktop.
final class DestinationsTests: XCTestCase {
    private let nothingNew: Supports = { _ in false }
    private let everything: Supports = { _ in true }

    func testHidesATabUntilTheDaemonAnswersTheMethodItReads() {
        XCTAssertEqual(Destinations.visibleTabs(.connectors, supports: nothingNew).map(\.id), ["systems"])
        // Not asked yet is not a yes, so nothing shows before the daemon answers.
        XCTAssertEqual(Destinations.visibleTabs(.needsYou, supports: { _ in nil }).map(\.id), ["decide-now"])
    }

    func testListsTheAgentsFirstOnceTheDaemonAnswersAgents() {
        XCTAssertEqual(Destinations.visibleTabs(.agents, supports: everything).map(\.id), ["agents", "jobs", "this-computer"])
        XCTAssertEqual(Destinations.settled(WindowRoute(.agents), supports: everything), WindowRoute(.agents, tab: "agents"))
        XCTAssertEqual(Destinations.settled(WindowRoute(.agents), supports: nothingNew), WindowRoute(.agents, tab: "this-computer"))
    }

    func testLandsOnTheFirstTabShownWhenTheOneAskedForIsHidden() {
        XCTAssertEqual(Destinations.settled(WindowRoute(.connectors, tab: "mcp"), supports: nothingNew), WindowRoute(.connectors, tab: "systems"))
        XCTAssertEqual(Destinations.settled(WindowRoute(.connectors, tab: "mcp"), supports: everything), WindowRoute(.connectors, tab: "mcp"))
        XCTAssertEqual(Destinations.settled(WindowRoute(.home), supports: everything), WindowRoute(.home))
        XCTAssertEqual(Destinations.settled(WindowRoute(.settings), supports: nothingNew), WindowRoute(.settings, tab: "account"))
    }

    func testKeepsEveryOldLinkWorking() {
        XCTAssertEqual(Destinations.route(forPage: "overview"), WindowRoute(.home))
        XCTAssertEqual(Destinations.route(forPage: "today"), WindowRoute(.home))
        XCTAssertEqual(Destinations.route(forPage: "phones"), WindowRoute(.settings, tab: "phones"))
        XCTAssertEqual(Destinations.route(forPage: "tools"), WindowRoute(.agents, tab: "this-computer"))
        XCTAssertEqual(Destinations.route(forPage: "apps"), WindowRoute(.connectors, tab: "systems"))
        XCTAssertEqual(Destinations.route(forPage: "connection"), WindowRoute(.settings, tab: "connection"))
        XCTAssertEqual(Destinations.route(forPage: "machines"), WindowRoute(.settings, tab: "connection"))
        XCTAssertEqual(Destinations.route(forPage: "learn"), WindowRoute(.needsYou, tab: "decide-now"))
        XCTAssertEqual(Destinations.route(forPage: "governance"), WindowRoute(.needsYou, tab: "decide-now"))
        XCTAssertEqual(Destinations.route(forPage: "needs-you"), WindowRoute(.needsYou))
        XCTAssertNil(Destinations.route(forPage: "nowhere"))
    }

    func testGroupsSettingsUnderWhoAChangeIsAboutAsTheConsolesSettingsTreeDoes() {
        let groups = Destinations.tabGroups(.settings, supports: everything).map { [$0.title] + $0.tabs.map(\.id) }
        XCTAssertEqual(groups, [
            ["Account", "account", "permissions"],
            ["Devices", "connection", "phones"],
            ["Voice", "voice", "listening", "dictation"],
            ["App", "appearance", "help"],
        ])
        XCTAssertEqual(Destinations.tabGroups(.memory, supports: everything), [])
    }

    func testNamesThePaneARouteOpensWithWhatItIsFor() {
        XCTAssertEqual(Destinations.tab(of: WindowRoute(.memory, tab: "list"))?.title, "List")
        XCTAssertEqual(Destinations.tab(of: WindowRoute(.settings, tab: "voice"))?.summary,
                       "Who thinks for the voice, and the voice it answers in.")
        XCTAssertNil(Destinations.tab(of: WindowRoute(.home)))
    }

    func testChangesLayoutAtTheSameWidthsAsWindowsAndLinux() {
        XCTAssertEqual([1280, 1000, 760, 480].map { WidthClass(width: $0) }, [.wide, .medium, .narrow, .compact])
        XCTAssertEqual([1200, 900, 640].map { WidthClass(width: $0) }, [.wide, .medium, .narrow])
    }

    func testFindsAPlaceByAnyWordOfItTitlesThatStartWithItFirst() {
        XCTAssertEqual(Destinations.matchCommands("dec", supports: nothingNew).map(\.title).first, "Decide now")
        XCTAssertTrue(Destinations.matchCommands("conn", supports: nothingNew).map(\.title).contains("Connectors"))
        XCTAssertEqual(Destinations.matchCommands("mcp", supports: nothingNew), [])
        XCTAssertEqual(Destinations.matchCommands("  ", supports: nothingNew), Destinations.commands(supports: nothingNew))
    }

    func testGoesBackAndForwardThroughRoutesAsABrowserDoes() {
        var history = RouteHistory(WindowRoute(.home))
        history.visit(WindowRoute(.agents))
        history.visit(WindowRoute(.agents))
        history.visit(WindowRoute(.connectors, tab: "systems"))
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

    func testOpensTheFirstNineRowsWithADigitAndThePaletteSaysWhichOne() {
        XCTAssertEqual(Destinations.all.prefix(9).compactMap { Destinations.key($0.id) }, ["1", "2", "3", "4", "5", "6", "7", "8", "9"])
        XCTAssertEqual(Destinations.key(.needsYou), "2")
        XCTAssertNil(Destinations.key(.settings))
        XCTAssertEqual(Destinations.commands(supports: nothingNew).first { $0.title == "Sessions" }?.key, "3")
    }
}
