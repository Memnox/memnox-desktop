import XCTest

@testable import MemnoxVoiceCore

final class SidebarTests: XCTestCase {
    private let nothingNew: Supports = { _ in false }
    private let everything: Supports = { _ in true }

    func testReadsAsTheConsolesSidebarDoes() {
        let sections = Sidebar.sections.map { [$0.title ?? ""] + $0.rows.map(\.title) }
        XCTAssertEqual(sections, [
            ["", "Home", "Projects", "Needs your attention", "Activity"],
            ["Your AI", "AI agents", "Protection settings", "Memory", "Skills", "MCP servers"],
            ["Connected tools", "Connectors", "Files"],
        ])
    }

    func testReachesEveryPageButSettingsFromARowOrItsStrip() {
        let inSidebar = Sidebar.rows.flatMap { $0.pages.map(\.route) }
        // Today settles on Home, so only Settings and Today stand outside the rows.
        for each in Destinations.all where each.id != .settings && each.id != .today {
            let routes = each.tabs.isEmpty ? [WindowRoute(each.id)] : each.tabs.map { WindowRoute(each.id, tab: $0.id) }
            for route in routes {
                XCTAssertTrue(inSidebar.contains(route), "\(route) has no row")
            }
        }
        XCTAssertEqual(inSidebar.count, Set(inSidebar).count, "a page sits under one row only")
    }

    func testMakesHomeOnePageWithNoStripAndLandsThere() {
        XCTAssertEqual(Sidebar.row(of: WindowRoute(.home))?.id, .home)
        XCTAssertEqual(Sidebar.strip(for: WindowRoute(.home), supports: everything), [])
        let home = Sidebar.rows[0]
        XCTAssertEqual(Sidebar.target(home, supports: nothingNew), Destinations.landing)
    }

    func testGathersTheAgentsAndThisComputerAsTabsOfAIAgentsWithSessionsLeftOff() {
        let agents = WindowRoute(.agents, tab: "list")
        XCTAssertEqual(Sidebar.strip(for: agents, supports: everything).map(\.title), ["Agents", "On this computer"])
        // Sessions is left off for now, so a runtime older than the agents view lands on this computer.
        XCTAssertEqual(Sidebar.rows.first { $0.id == .agents }.flatMap { Sidebar.target($0, supports: nothingNew) },
                       WindowRoute(.agents, tab: "computer"))
    }

    func testMakesTheMapListAndLayersOneMemoryRowThatOpensOnTheMap() {
        let memory = Sidebar.rows.first { $0.id == .memory }
        XCTAssertEqual(memory.flatMap { Sidebar.target($0, supports: everything) }, WindowRoute(.workspaces, tab: "map"))
        XCTAssertEqual(Sidebar.strip(for: WindowRoute(.workspaces, tab: "memory"), supports: everything).map(\.title),
                       ["Map", "List", "Layers"])
        XCTAssertEqual(Sidebar.row(of: WindowRoute(.workspaces, tab: "layers"))?.id, .memory)
        // Without the layers the strip still offers the map and the list.
        let noLayers: Supports = { $0 != "memory-layers" }
        XCTAssertEqual(Sidebar.strip(for: WindowRoute(.workspaces, tab: "map"), supports: noLayers).map(\.title), ["Map", "List"])
    }

    func testShowsNoStripOverAPageThatStandsAlone() {
        XCTAssertEqual(Sidebar.strip(for: WindowRoute(.governance, tab: "policies"), supports: everything), [])
        XCTAssertEqual(Sidebar.strip(for: WindowRoute(.governance, tab: "approvals"), supports: nothingNew), [])
        XCTAssertEqual(Sidebar.strip(for: WindowRoute(.settings, tab: "voice"), supports: everything), [])
    }

    func testLeavesARowOutUntilTheDaemonAnswersOneOfItsPages() {
        let files = Sidebar.rows.first { $0.id == .files }
        XCTAssertNil(files.flatMap { Sidebar.target($0, supports: nothingNew) })
        XCTAssertEqual(files.flatMap { Sidebar.target($0, supports: everything) }, WindowRoute(.workspaces, tab: "sources"))
    }

    func testGivesSkillsItsOwnRowWithMySkillsAloneWhileAssignedIsLeftOff() {
        XCTAssertEqual(Sidebar.row(of: WindowRoute(.workspaces, tab: "skills"))?.id, .skills)
        XCTAssertEqual(Sidebar.strip(for: WindowRoute(.workspaces, tab: "skills"), supports: everything), [])
    }

    func testGivesMcpServersItsOwnRowWithServersAloneWhileClientsAndSecretsAreLeftOff() {
        let servers = Sidebar.rows.first { $0.id == .servers }
        XCTAssertEqual(servers.flatMap { Sidebar.target($0, supports: everything) }, WindowRoute(.mcp, tab: "servers"))
        XCTAssertEqual(Sidebar.strip(for: WindowRoute(.mcp, tab: "servers"), supports: everything), [])
        // A runtime without the hub has none of its pages, so the row stays out rather than leading nowhere.
        XCTAssertNil(servers.flatMap { Sidebar.target($0, supports: nothingNew) })
        XCTAssertEqual(Sidebar.row(of: WindowRoute(.mcp, tab: "apps"))?.id, .connectors)
    }

    func testLeavesDiscoverOffTheSidebarForNow() {
        XCTAssertNil(Sidebar.row(of: WindowRoute(.workspaces, tab: "discover")))
    }
}
