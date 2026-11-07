import XCTest

@testable import MemnoxVoiceCore

/// Mirrors shared/tauri-core/test/destinations.test.ts, so the window lays out the same on every desktop.
final class DestinationsTests: XCTestCase {
    private let nothingNew: Supports = { _ in false }
    private let everything: Supports = { _ in true }

    func testHidesATabUntilTheDaemonAnswersTheMethodItReads() {
        XCTAssertEqual(Destinations.visibleTabs(.workspaces, supports: nothingNew).map(\.id), ["projects"])
        // Not asked yet is not a yes, so nothing shows before the daemon answers.
        XCTAssertEqual(Destinations.visibleTabs(.governance, supports: { _ in nil }).map(\.id), ["approvals"])
    }

    func testListsEveryAgentFirstOnceTheDaemonAnswersAgents() {
        XCTAssertEqual(Destinations.visibleTabs(.agents, supports: everything).map(\.id), ["list", "profiles", "computer"])
        XCTAssertEqual(Destinations.settled(WindowRoute(.agents), supports: everything), WindowRoute(.agents, tab: "list"))
        // Sessions is left off for now, so a runtime older than the agents view opens Agents on this computer.
        XCTAssertEqual(Destinations.settled(WindowRoute(.agents), supports: nothingNew), WindowRoute(.agents, tab: "computer"))
        XCTAssertEqual(Destinations.settled(WindowRoute(.agents, tab: "sessions"), supports: everything), WindowRoute(.agents, tab: "list"))
        XCTAssertEqual(Destinations.visibleTabs(.governance, supports: { $0 == "rules" || $0 == "activity" }).map(\.id),
                       ["approvals", "policies", "activity"])
    }

    func testShowsTheSkillsHubOnlyWhereTheRuntimeKeepsOne() {
        XCTAssertEqual(Destinations.visibleTabs(.workspaces, supports: nothingNew).map(\.id), ["projects"])
        XCTAssertEqual(Destinations.visibleTabs(.workspaces, supports: everything).map(\.id), ["projects", "map", "memory", "layers", "sources", "skills"])
    }

    func testLandsOnTheFirstTabShownWhenTheOneAskedForIsHidden() {
        XCTAssertEqual(Destinations.settled(WindowRoute(.mcp, tab: "servers"), supports: nothingNew), WindowRoute(.mcp, tab: "apps"))
        XCTAssertEqual(Destinations.settled(WindowRoute(.mcp, tab: "servers"), supports: everything), WindowRoute(.mcp, tab: "servers"))
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

    func testLeavesDiscoverOutForNowAndShowsTheHubOnceTheRuntimeAnswersIt() {
        XCTAssertFalse(Destinations.visibleTabs(.workspaces, supports: everything).map(\.id).contains("discover"))
        XCTAssertEqual(Destinations.visibleTabs(.mcp, supports: everything).map(\.id), ["servers", "apps"])
        XCTAssertEqual(Destinations.visibleTabs(.mcp, supports: nothingNew).map(\.id), ["apps"])
        XCTAssertEqual(Destinations.matchCommands("servers", supports: everything).map(\.title), ["Servers"])
    }

    func testLeavesBackupOutOfSettingsForNowAsWindowsAndLinuxDo() {
        XCTAssertFalse(Destinations.settingsTabs.map(\.id).contains("backup"))
    }

    func testLeavesTheLocalNetworkOutOfSettingsForNowAsWindowsAndLinuxDo() {
        XCTAssertFalse(Destinations.visibleTabs(.settings, supports: { _ in true }).map(\.id).contains("network"))
    }

    func testLeavesWhatCouldLoseAPersonOffForNowAndSettlesItsOldLinks() {
        XCTAssertFalse(Destinations.visibleTabs(.settings, supports: { _ in true }).map(\.id).contains("sync"))
        XCTAssertEqual(Destinations.settled(WindowRoute(.settings, tab: "sync"), supports: everything), WindowRoute(.settings, tab: "account"))
        XCTAssertEqual(Destinations.settled(WindowRoute(.governance, tab: "learn"), supports: everything), WindowRoute(.governance, tab: "approvals"))
        XCTAssertEqual(Destinations.settled(WindowRoute(.mcp, tab: "secrets"), supports: everything), WindowRoute(.mcp, tab: "servers"))
        XCTAssertEqual(Destinations.settled(WindowRoute(.workspaces, tab: "assigned"), supports: everything), WindowRoute(.workspaces, tab: "projects"))
    }

    func testGroupsSettingsUnderWhoAChangeIsAboutAsTheConsolesSettingsTreeDoes() {
        let groups = Destinations.tabGroups(.settings, supports: everything).map { [$0.title] + $0.tabs.map(\.id) }
        XCTAssertEqual(groups, [
            ["Account", "account", "permissions", "connection"],
            ["Devices", "phones"],
            ["Voice", "voice", "listening", "dictation"],
            ["App", "appearance", "help"],
        ])
    }

    func testGroupsEveryDestinationAsWindowsAndLinuxDo() {
        let titles = { (id: Destination) in Destinations.tabGroups(id, supports: self.everything).map { [$0.title] + $0.tabs.map(\.title) } }
        XCTAssertEqual(titles(.agents), [["Agents", "Agents", "Jobs"], ["This computer", "On this computer"]])
        XCTAssertEqual(titles(.workspaces), [["Projects", "Projects"], ["Knowledge", "Map", "Memory", "Layers", "Files"],
                                             ["Skills", "My Skills"]])
        XCTAssertEqual(titles(.mcp), [["Hub", "Servers"], ["Apps", "Connectors"]])
        XCTAssertEqual(titles(.governance), [["Needs your attention", "Approvals"], ["Rules", "Protection settings"], ["Record", "Activity"]])
    }

    func testDropsAHeadingWhoseEveryTabIsHiddenSoNoGroupStandsOverNothing() {
        XCTAssertEqual(Destinations.tabGroups(.mcp, supports: nothingNew).map(\.title), ["Apps"])
        XCTAssertEqual(Destinations.tabGroups(.mcp, supports: everything).map(\.title), ["Hub", "Apps"])
        XCTAssertEqual(Destinations.tabGroups(.home, supports: everything), [])
    }

    func testGivesTheMapItsOwnPageOnceTheRuntimeAnswersMemory() {
        XCTAssertFalse(Destinations.visibleTabs(.workspaces, supports: nothingNew).map(\.id).contains("map"))
        XCTAssertEqual(Destinations.tab(of: WindowRoute(.workspaces, tab: "map"))?.tab.title, "Map")
        XCTAssertEqual(Destinations.settled(WindowRoute(.workspaces, tab: "map"), supports: everything), WindowRoute(.workspaces, tab: "map"))
    }

    func testNamesThePaneARouteOpensWithItsHeadingAndWhatItIsFor() {
        let memory = Destinations.tab(of: WindowRoute(.workspaces, tab: "memory"))
        XCTAssertEqual(memory?.group, "Knowledge")
        XCTAssertEqual(memory?.tab.title, "Memory")
        XCTAssertEqual(Destinations.tab(of: WindowRoute(.settings, tab: "voice"))?.tab.summary,
                       "Who thinks for the voice, and the voice it answers in.")
        XCTAssertNil(Destinations.tab(of: WindowRoute(.home)))
    }

    func testChangesLayoutAtTheSameWidthsAsWindowsAndLinux() {
        XCTAssertEqual([1280, 1000, 760, 480].map { WidthClass(width: $0) }, [.wide, .medium, .narrow, .compact])
        XCTAssertEqual([1200, 900, 640].map { WidthClass(width: $0) }, [.wide, .medium, .narrow])
    }

    func testFindsAPlaceByAnyWordOfItTitlesThatStartWithItFirst() {
        let found = Destinations.matchCommands("app", supports: nothingNew).map(\.title)
        XCTAssertEqual(found.first, "Approvals")
        XCTAssertTrue(Destinations.matchCommands("conn", supports: nothingNew).map(\.title).contains("Connectors"))
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

    func testOpensOnHomeAndSendsAnOldTodayLinkThere() {
        XCTAssertEqual(Destinations.landing, WindowRoute(.home))
        XCTAssertEqual(Destinations.settled(WindowRoute(.today), supports: everything), WindowRoute(.home))
        // Today keeps no digit, so Command 1 to 5 still open what they opened on Windows and Linux.
        XCTAssertNil(Destinations.info(.today).key)
        XCTAssertEqual(Destinations.route(forPage: "home"), WindowRoute(.home))
        XCTAssertEqual(Destinations.route(forPage: "today"), WindowRoute(.home))
        XCTAssertFalse(Destinations.commands(supports: everything).contains { $0.route.destination == .today })
    }
}
