import XCTest

@testable import MemnoxVoiceCore

/// Mirrors shared/tauri-core/test/destinations.test.ts, so the sidebar reads the same on every desktop.
final class SidebarTests: XCTestCase {
    private let nothingNew: Supports = { _ in false }
    private let everything: Supports = { _ in true }

    func testReadsAsTheConsolesSidebarDoes() {
        let sections = Sidebar.sections.map { [$0.title ?? ""] + $0.rows.map { Destinations.info($0).title } }
        XCTAssertEqual(sections, [
            ["", "Home", "Needs you", "Sessions", "Agents", "Projects"],
            ["Govern", "Rules", "Hand over", "Activity"],
            ["Knowledge", "Memory", "Connectors"],
        ])
        XCTAssertEqual(Sidebar.foot.map { Destinations.info($0).title }, ["Settings"])
    }

    func testLandsOnHomeWithNoStrip() {
        XCTAssertEqual(Sidebar.target(.home, supports: nothingNew), Destinations.landing)
        XCTAssertEqual(Sidebar.strip(for: WindowRoute(.home), supports: everything), [])
    }

    func testOpensNeedsYouOnDecideNowWhateverTheRuntimeAnswers() {
        XCTAssertEqual(Sidebar.target(.needsYou, supports: nothingNew), WindowRoute(.needsYou, tab: "decide-now"))
        XCTAssertEqual(Sidebar.strip(for: WindowRoute(.needsYou, tab: "decide-now"), supports: nothingNew), [])
    }

    func testLeavesARowOutUntilTheDaemonAnswersOneOfItsPages() {
        XCTAssertNil(Sidebar.target(.rules, supports: nothingNew))
        XCTAssertEqual(Sidebar.target(.rules, supports: everything), WindowRoute(.rules, tab: "rules"))
    }

    func testGathersMemoryAndItsSkillsAsOneRowThatOpensOnTheMap() {
        XCTAssertEqual(Sidebar.target(.memory, supports: everything), WindowRoute(.memory, tab: "map"))
        XCTAssertEqual(Sidebar.strip(for: WindowRoute(.memory, tab: "list"), supports: everything).map(\.title),
                       ["Map", "List", "Layers", "Skills"])
        let skillsOnly: Supports = { $0 == "skills-hub" }
        XCTAssertEqual(Sidebar.target(.memory, supports: skillsOnly), WindowRoute(.memory, tab: "skills"))
    }

    func testOpensConnectorsOnTheSystemsThisMacReaches() {
        XCTAssertEqual(Sidebar.target(.connectors, supports: nothingNew), WindowRoute(.connectors, tab: "systems"))
        XCTAssertEqual(Sidebar.strip(for: WindowRoute(.connectors, tab: "systems"), supports: everything).map(\.title),
                       ["Systems", "Files", "MCP servers"])
    }

    func testKeepsSettingsAsATreeRatherThanAStrip() {
        XCTAssertEqual(Sidebar.strip(for: WindowRoute(.settings, tab: "voice"), supports: everything), [])
    }
}
