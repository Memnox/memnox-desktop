import XCTest

@testable import MemnoxVoiceCore

final class ProjectSidebarTests: XCTestCase {
    private let everything: Supports = { _ in true }

    func testHoldsTheProjectsOwnPagesWithoutLeadingWithCode() {
        XCTAssertEqual(ProjectSidebar.pages.map(\.title), ["Overview", "Agents", "Memory", "What its AI may do"])
        XCTAssertEqual(ProjectSidebar.backTitle, "Back to Projects")
        XCTAssertFalse(ProjectSidebar.pages.contains { $0.title.contains("Code") })
    }

    func testOpensOnTheOverviewAndKnowsWhereTheWindowIs() {
        let route = ProjectSidebar.route("prj_1")
        XCTAssertEqual(ProjectSidebar.place(of: route), ProjectPlace(id: "prj_1", page: .overview))
        XCTAssertNil(ProjectSidebar.place(of: ProjectSidebar.list))
        XCTAssertNil(ProjectSidebar.place(of: WindowRoute(.workspaces, tab: "map")))
    }

    func testKeepsAProjectsPageOpenWhenTheRouteSettles() {
        let route = ProjectSidebar.route("prj_1", .memory)
        XCTAssertEqual(Destinations.settled(route, supports: everything), route)
        XCTAssertEqual(Destinations.settled(route, supports: { _ in false }), route)
    }

    func testLeavesTheUsualStripOffAProjectsPages() {
        XCTAssertNil(Sidebar.row(of: ProjectSidebar.route("prj_1", .agents)))
        XCTAssertEqual(Sidebar.strip(for: ProjectSidebar.route("prj_1", .agents), supports: everything), [])
    }

    func testSendsAnOldRouteToTheToolsPageToTheOverview() {
        XCTAssertEqual(ProjectSidebar.place(of: ProjectSidebar.route("prj_1", .tools)), ProjectPlace(id: "prj_1", page: .overview))
        XCTAssertFalse(ProjectSidebar.pages.contains(.tools))
    }

    func testSaysWhereTheWindowIsAsTheTopBarDoes() {
        let place = ProjectPlace(id: "prj_1", page: .rules)
        XCTAssertEqual(ProjectSidebar.breadcrumb(place, name: "Spring launch"), ["Projects", "Spring launch", "What its AI may do"])
        XCTAssertEqual(ProjectSidebar.breadcrumb(place, name: nil), ["Projects", "Project", "What its AI may do"])
    }
}
