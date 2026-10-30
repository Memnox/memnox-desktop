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

    func testListsEveryAgentFirstOnceTheDaemonAnswersAgents() {
        XCTAssertEqual(Destinations.visibleTabs(.agents, supports: everything).map(\.id), ["list", "sessions", "computer"])
        XCTAssertEqual(Destinations.settled(WindowRoute(.agents), supports: everything), WindowRoute(.agents, tab: "list"))
        // A runtime older than the agents view opens Agents on its sessions, as before.
        XCTAssertEqual(Destinations.settled(WindowRoute(.agents), supports: nothingNew), WindowRoute(.agents, tab: "sessions"))
        XCTAssertEqual(Destinations.visibleTabs(.governance, supports: { $0 == "rules" || $0 == "activity" }).map(\.id),
                       ["approvals", "policies", "activity"])
    }

    func testShowsTheSkillsHubOnlyWhereTheRuntimeKeepsOne() {
        XCTAssertEqual(Destinations.visibleTabs(.workspaces, supports: nothingNew).map(\.id), ["projects"])
        XCTAssertEqual(Destinations.visibleTabs(.workspaces, supports: everything).map(\.id), ["projects", "memory", "skills", "assigned", "discover", "profiles"])
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

    func testKeepsBackupUnderSettingsAfterAppearanceAsWindowsAndLinuxDo() {
        let tabs = Destinations.settingsTabs.map(\.id)
        XCTAssertEqual(tabs.firstIndex(of: "backup"), tabs.firstIndex(of: "appearance").map { $0 + 1 })
        XCTAssertEqual(Destinations.route(forPage: "backup"), WindowRoute(.settings, tab: "backup"))
        XCTAssertEqual(Destinations.settled(WindowRoute(.settings, tab: "backup"), supports: { _ in false }), WindowRoute(.settings, tab: "backup"))
    }

    func testShowsTheLocalNetworkAfterPhonesOnlyWhereTheRuntimeAnswersIt() {
        XCTAssertFalse(Destinations.visibleTabs(.settings, supports: { _ in false }).map(\.id).contains("network"))
        let tabs = Destinations.visibleTabs(.settings, supports: { _ in true }).map(\.id)
        XCTAssertEqual(tabs.firstIndex(of: "network"), tabs.firstIndex(of: "phones").map { $0 + 1 })
        XCTAssertEqual(Destinations.route(forPage: "network"), WindowRoute(.settings, tab: "network"))
    }

    func testShowsPersonalSyncAfterTheLocalNetworkOnlyWhereTheRuntimeAnswersIt() {
        XCTAssertFalse(Destinations.visibleTabs(.settings, supports: { _ in false }).map(\.id).contains("sync"))
        let tabs = Destinations.visibleTabs(.settings, supports: { _ in true }).map(\.id)
        XCTAssertEqual(Array(tabs[3...5]), ["phones", "network", "sync"])
        XCTAssertEqual(Destinations.route(forPage: "sync"), WindowRoute(.settings, tab: "sync"))
    }

    func testGroupsSettingsUnderWhoAChangeIsAboutAsTheConsolesSettingsTreeDoes() {
        let groups = Destinations.tabGroups(.settings, supports: everything).map { [$0.title] + $0.tabs.map(\.id) }
        XCTAssertEqual(groups, [
            ["Account", "account", "permissions", "connection"],
            ["Devices", "phones", "network", "sync"],
            ["Voice", "voice", "listening", "dictation"],
            ["App", "appearance", "backup", "help"],
        ])
    }

    func testGroupsEveryDestinationAsWindowsAndLinuxDo() {
        let titles = { (id: Destination) in Destinations.tabGroups(id, supports: self.everything).map { [$0.title] + $0.tabs.map(\.title) } }
        XCTAssertEqual(titles(.agents), [["Agents", "Agents", "Sessions"], ["This computer", "On this computer"]])
        XCTAssertEqual(titles(.workspaces), [["Projects", "Workspaces", "Profiles"], ["Knowledge", "Memory"],
                                             ["Skills", "My Skills", "Assigned", "Discover"]])
        XCTAssertEqual(titles(.mcp), [["Hub", "Servers", "Clients", "Secrets"], ["Apps", "Your apps"]])
        XCTAssertEqual(titles(.governance), [["Waiting on you", "Approvals", "Learn"], ["Rules", "Policies"], ["Record", "Activity"]])
    }

    func testDropsAHeadingWhoseEveryTabIsHiddenSoNoGroupStandsOverNothing() {
        XCTAssertEqual(Destinations.tabGroups(.mcp, supports: nothingNew).map(\.title), ["Apps"])
        XCTAssertEqual(Destinations.tabGroups(.mcp, supports: everything).map(\.title), ["Hub", "Apps"])
        XCTAssertEqual(Destinations.tabGroups(.home, supports: everything), [])
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
