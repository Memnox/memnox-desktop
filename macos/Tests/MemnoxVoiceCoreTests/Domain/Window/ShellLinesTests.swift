import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Mirrors shared/tauri-core/test/shell-pickers.test.ts, so the top bar's pickers behave alike on every desktop.
final class ShellLinesTests: XCTestCase {
    private func project(_ id: String, _ path: String) -> ProjectView {
        ProjectView(id: id, name: id, path: path, declared: true, opened: true, agents: [], agentsSeen: [],
                    sessions: ProjectSessionsView(total: 0, ended: 0), servers: [], skills: [],
                    rules: ProjectRulesView(file: "memnox.policies.toml", count: 0, inForce: true), instructions: [],
                    memoryScope: "project", openMissions: [], openQuestions: 0)
    }

    private func skill(_ scope: String, project: String?) throws -> SkillView {
        var json = SkillsProtocolTests.skill.replacingOccurrences(of: #""scope":"personal""#, with: #""scope":"\#(scope)""#)
        if let project { json = json.replacingOccurrences(of: #""category""#, with: #""project":"\#(project)","category""#) }
        return try JSONDecoder().decode(SkillView.self, from: Data(json.utf8))
    }

    func testStartsOnAllProjectsAndForgetsAProjectThatIsGone() {
        let app = project("p1", "/code/app"), site = project("p2", "/code/site")
        XCTAssertEqual(ShellLines.allProjects, "All projects")
        XCTAssertNil(ShellLines.currentProject([app, site], saved: nil))
        XCTAssertEqual(ShellLines.currentProject([app, site], saved: "p2"), site)
        XCTAssertNil(ShellLines.currentProject([app], saved: "p2"))
        XCTAssertNil(ShellLines.currentProject(nil, saved: "p1"))
    }

    func testNarrowsWorkspacesToTheProjectPicked() {
        let app = project("p1", "/code/app"), site = project("p2", "/code/site")
        XCTAssertEqual(ShellLines.projectsShown([app, site], current: nil), [app, site])
        XCTAssertEqual(ShellLines.projectsShown([app, site], current: site), [site])
    }

    func testKeepsThePersonsOwnSkillsAndThoseWrittenIntoTheProject() throws {
        let app = project("p1", "/code/app")
        let skills = [try skill("personal", project: nil), try skill("project", project: "/code/app"), try skill("project", project: "/code/site")]
        XCTAssertEqual(ShellLines.skillsShown(skills, current: app), [skills[0], skills[1]])
        XCTAssertEqual(ShellLines.skillsShown(skills, current: nil), skills)
    }

    func testTellsAFolderInsideAProjectFromOneThatOnlyStartsAlike() {
        XCTAssertTrue(ShellLines.inside("/code/app", project: "/code/app"))
        XCTAssertTrue(ShellLines.inside("/code/app/web", project: "/code/app"))
        XCTAssertFalse(ShellLines.inside("/code/apparel", project: "/code/app"))
    }

    func testOffersTheCurrentProjectFirstInALaunchOrOpenForm() {
        let folders = [FolderPick(path: "/code/site", name: "site"), FolderPick(path: "/code/app", name: "app")]
        XCTAssertEqual(ShellLines.withCurrent(folders, current: project("app", "/code/app")).map(\.path), ["/code/app", "/code/site"])
        XCTAssertEqual(ShellLines.withCurrent(folders, current: nil), folders)
    }

    func testStartsALaunchOrOpenFormOnTheCurrentProjectWhenTheFormOffersIt() {
        let app = project("p1", "/code/app")
        XCTAssertEqual(ShellLines.preselectedFolder(["/code/site", "/code/app"], current: app, fallback: "/code/site"), "/code/app")
        XCTAssertEqual(ShellLines.preselectedFolder(["/code/site"], current: app, fallback: "/code/site"), "/code/site")
        XCTAssertEqual(ShellLines.preselectedFolder(["/code/site", "/code/app"], current: nil, fallback: "/code/site"), "/code/site")
    }

    func testTheScopeSelectorShowsOnlyOnceTheRuntimeHandsDownSomethingOfAnOrganization() throws {
        let rule = { (source: String) in PolicyRuleView(name: "r", effect: "ask", match: PolicyRuleMatch(actions: []), sentence: "s", source: source, editable: false) }
        XCTAssertFalse(ShellLines.hasOrganization(skills: [try skill("project", project: nil)], rules: [rule("person")]))
        XCTAssertTrue(ShellLines.hasOrganization(skills: [try skill("organization", project: nil)]))
        XCTAssertTrue(ShellLines.hasOrganization(rules: [rule("workspace")]))
    }

    func testTheScopeFallsBackToPersonalWhenNothingIsConnected() {
        XCTAssertEqual(ShellLines.shownScope(saved: "organization", connected: false), .personal)
        XCTAssertEqual(ShellLines.shownScope(saved: "organization", connected: true), .organization)
        XCTAssertEqual(ShellLines.shownScope(saved: nil, connected: true), .personal)
        XCTAssertEqual(ShownScope.allCases.map(\.title), ["Personal", "Organization"])
    }

    func testShowsThePersonsItemsOrTheOrganizationsNeverBothMixed() {
        let items = [("mine", false), ("theirs", true)]
        XCTAssertEqual(ShellLines.inScope(items, .personal) { $0.1 }.map(\.0), ["mine"])
        XCTAssertEqual(ShellLines.inScope(items, .organization) { $0.1 }.map(\.0), ["theirs"])
    }

    func testTheNumberKeysAreNamedAsEachPlatformPressesThem() {
        XCTAssertEqual(ShellLines.shortcutWords("3", mac: true), "\u{2318}3")
        XCTAssertEqual(ShellLines.shortcutWords("3", mac: false), "Ctrl 3")
    }
}
