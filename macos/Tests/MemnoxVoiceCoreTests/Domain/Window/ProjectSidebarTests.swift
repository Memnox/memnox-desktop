import XCTest

@testable import MemnoxVoiceCore

final class ProjectSidebarTests: XCTestCase {
    private let everything: Supports = { _ in true }

    func testHoldsTheProjectsOwnPagesWithoutLeadingWithCode() {
        XCTAssertEqual(ProjectSidebar.pages.map(\.title), ["Overview", "Rules here", "What agents here should know"])
        XCTAssertEqual(ProjectSidebar.backTitle, "Back to Projects")
        XCTAssertFalse(ProjectSidebar.pages.contains { $0.title.contains("Code") })
    }

    func testSaysWhatEachPageIsForInTheWordsTheWindowsAndLinuxAppUses() {
        XCTAssertEqual(ProjectPage.overview.summary, "Who is working here, what waits for you here, and how careful agents are here.")
    }

    func testOpensTheSharedMySkillsFromTheOverviewsSkillsPart() {
        // The Overview's Skills part is ProjectCanUseTarget.shared(.skills), which lands on Skills under Memory.
        XCTAssertEqual(SharedPage.skills.target(supports: everything), WindowRoute(.memory, tab: "skills"))
        XCTAssertEqual(ProjectCanUseTarget.shared(.skills).title, "Skills")
    }

    func testOpensOnTheOverviewAndKnowsWhereTheWindowIs() {
        let route = ProjectSidebar.route("prj_1")
        XCTAssertEqual(ProjectSidebar.place(of: route), ProjectPlace(id: "prj_1", page: .overview))
        XCTAssertNil(ProjectSidebar.place(of: ProjectSidebar.list))
        XCTAssertNil(ProjectSidebar.place(of: WindowRoute(.memory, tab: "map")))
    }

    func testKeepsAProjectsPageOpenWhenTheRouteSettles() {
        let route = ProjectSidebar.route("prj_1", .memory)
        XCTAssertEqual(Destinations.settled(route, supports: everything), route)
        XCTAssertEqual(Destinations.settled(route, supports: { _ in false }), route)
    }

    func testLeavesTheUsualStripOffAProjectsPages() {
        XCTAssertEqual(Sidebar.strip(for: ProjectSidebar.route("prj_1", .agents), supports: everything), [])
    }

    func testSendsAnOldRouteToTheToolsOrAgentsPageToTheOverview() {
        XCTAssertEqual(ProjectSidebar.place(of: ProjectSidebar.route("prj_1", .tools)), ProjectPlace(id: "prj_1", page: .overview))
        XCTAssertEqual(ProjectSidebar.place(of: ProjectSidebar.route("prj_1", .agents)), ProjectPlace(id: "prj_1", page: .overview))
        XCTAssertFalse(ProjectSidebar.pages.contains(.tools))
    }

    func testSaysWhereTheWindowIsAsTheTopBarDoes() {
        let place = ProjectPlace(id: "prj_1", page: .rules)
        XCTAssertEqual(ProjectSidebar.breadcrumb(place, name: "Spring launch"), ["Projects", "Spring launch", "Rules here"])
        XCTAssertEqual(ProjectSidebar.breadcrumb(place, name: nil), ["Projects", "Project", "Rules here"])
    }
}
