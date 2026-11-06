import XCTest

@testable import MemnoxVoiceCore

final class ProjectPageLinesTests: XCTestCase {
    private func project(servers: [ProjectGrantView] = [], rules: ProjectRulesView = ProjectRulesView(count: 0, inForce: false),
                         organization: ProjectOrganizationView? = nil) -> ProjectView {
        let base = sampleProject
        return ProjectView(id: base.id, name: base.name, path: base.path, declared: true, opened: true, agents: base.agents,
                           agentsSeen: base.agentsSeen, sessions: base.sessions, servers: servers, skills: base.skills, rules: rules,
                           instructions: base.instructions, memoryScope: base.memoryScope, openMissions: base.openMissions,
                           openQuestions: 0, scope: organization == nil ? nil : .organization, organization: organization)
    }

    private let shared = ProjectOrganizationView(id: "org prj", name: "Launch", repository: "github.com/acme/site",
                                                 description: "The spring campaign", servers: ["slack"], memory: "project",
                                                 editedIn: "Changed in Memnox Cloud")

    func testListsTheToolsBeforeTheRepositoryOrFolder() {
        let notes = MemorySourceView(id: "s1", kind: .obsidian, name: "Launch notes", location: "/notes", project: "prj_1")
        let elsewhere = MemorySourceView(id: "s2", kind: .markdown, name: "Other", location: "/other", project: "prj_2")
        let tools = ProjectPageLines.tools(project(servers: [ProjectGrantView(name: "slack", inHub: true, agents: [])]),
                                           sources: [notes, elsewhere])
        XCTAssertEqual(tools.map(\.kind), [.notes, .app, .folder])
        XCTAssertEqual(tools.map(\.name), ["Launch notes", "slack", "memnox-desktop"])
        XCTAssertEqual(tools[1].server, "slack")
        let org = ProjectPageLines.tools(project(organization: shared), sources: [])
        XCTAssertEqual(org.map(\.kind), [.app, .repository, .folder])
        XCTAssertNil(org[0].server)
    }

    func testLeavesTheToolCountOffTheCardWithTheToolsPage() {
        XCTAssertEqual(ProjectPageLines.chips(project(servers: [ProjectGrantView(name: "slack", inHub: true, agents: [])]), sources: []),
                       ["Memory"])
        XCTAssertEqual(ProjectPageLines.chips(project(organization: shared), sources: []), ["Memory"])
    }

    func testShowsGetItReadyWhileTheProjectHasNoRules() {
        let empty = ProjectPageLines.readySteps(project(), sources: [], rulesHere: 0)
        XCTAssertEqual(empty.map(\.title), ["Choose what its AI may do"])
        XCTAssertEqual(empty.map(\.page), [.rules])
        XCTAssertEqual(empty.map(\.done), [false])
        XCTAssertTrue(ProjectPageLines.showsChecklist(empty))
        let ruled = ProjectPageLines.readySteps(project(rules: ProjectRulesView(file: "r.toml", count: 2, inForce: true)), sources: [], rulesHere: 0)
        XCTAssertEqual(ruled.map(\.done), [true])
        XCTAssertFalse(ProjectPageLines.showsChecklist(ruled))
    }

    func testShowsATeamOnlyOnceJoinedOrSharedByTheOrganization() {
        XCTAssertFalse(ProjectPageLines.showsTeam(project(), joined: false))
        XCTAssertTrue(ProjectPageLines.showsTeam(project(), joined: true))
        XCTAssertTrue(ProjectPageLines.showsTeam(project(organization: shared), joined: false))
        XCTAssertTrue(ProjectPageLines.teamLine(project()).hasPrefix("Only you work in this project."))
        XCTAssertTrue(ProjectPageLines.teamLine(project(organization: shared)).contains("shares this project as Launch"))
    }

    func testSaysWhatItsAIUsesWithNoPeopleWhileAlone() {
        let alone = ProjectPageLines.canUse(project(servers: [ProjectGrantView(name: "github", inHub: true, agents: [])]), joined: false)
        XCTAssertEqual(alone.map(\.title), ["AI agents", "Skills", "Apps"])
        XCTAssertEqual(alone.map(\.target), [.page(.agents), .shared(.skills), .shared(.connectors)])
        XCTAssertEqual(alone[1].names, ["review-checklist", "gone"])
        XCTAssertEqual(alone[2].names, ["github"])
        XCTAssertFalse(alone.contains { $0.empty.contains("people") || $0.what.contains("team") })
        let joined = ProjectPageLines.canUse(project(organization: shared), joined: false)
        XCTAssertEqual(joined[2].names, ["slack"])
        XCTAssertTrue(joined[1].what.contains("your team"))
        XCTAssertNil(ProjectPageLines.moreLine(alone[1]))
    }

    func testKeepsWhatWasLearnedHereNewestFirst() {
        let items = [
            MemoryItemView(id: "a", statement: "Old", project: "prj_1", createdAt: "2026-10-01T00:00:00Z"),
            MemoryItemView(id: "b", statement: "Elsewhere", project: "prj_2", createdAt: "2026-10-03T00:00:00Z"),
            MemoryItemView(id: "c", statement: "New", project: "/code/memnox-desktop", createdAt: "2026-10-02T00:00:00Z"),
            MemoryItemView(id: "d", statement: "Nowhere", createdAt: "2026-10-04T00:00:00Z"),
        ]
        XCTAssertEqual(ProjectPageLines.learned(items, in: project()).map(\.id), ["c", "a"])
    }

    func testPutsAServerInOrTakesItOutKeepingTheRest() {
        let one = project(servers: [ProjectGrantView(name: "github", inHub: true, agents: [])])
        XCTAssertEqual(ProjectPageLines.draft(of: one, adding: "slack").servers, ["github", "slack"])
        XCTAssertEqual(ProjectPageLines.draft(of: one, adding: "github").servers, ["github"])
        XCTAssertNil(ProjectPageLines.draft(of: one, removing: "github").servers)
        XCTAssertEqual(ProjectPageLines.draft(of: one, adding: "slack").skills, ["review-checklist", "gone"])
    }

    func testRenamesKeepingEverythingElse() {
        let one = project(servers: [ProjectGrantView(name: "github", inHub: true, agents: [])])
        XCTAssertEqual(ProjectPageLines.draft(of: one, renamed: "  Spring launch ")?.name, "Spring launch")
        XCTAssertEqual(ProjectPageLines.draft(of: one, renamed: "Spring launch")?.servers, ["github"])
        XCTAssertNil(ProjectPageLines.draft(of: one, renamed: " "))
        XCTAssertNil(ProjectPageLines.draft(of: one, renamed: one.name))
    }

    func testLinksToTheSharedProjectInMemnoxCloud() {
        XCTAssertEqual(ProjectPageLines.cloudLink(project(organization: shared))?.absoluteString, "https://app.memnox.com/projects/org%20prj")
        XCTAssertEqual(ProjectPageLines.cloudLink(project())?.absoluteString, "https://app.memnox.com/projects")
        XCTAssertEqual(ProjectPageLines.description(project(organization: shared)), "The spring campaign")
        XCTAssertEqual(ProjectPageLines.description(project()), "Ship the projects view")
    }

    func testSaysAProjectsPagesInTheWordsTheWindowsAndLinuxAppUses() {
        XCTAssertEqual(ProjectPageLines.readySteps(project(), sources: [], rulesHere: 0)[0].detail,
                       "What goes ahead, what asks you first, and what never happens.")
        XCTAssertEqual(ProjectPageLines.learnedEmpty, "Nothing learned here yet. As its AI works in the tools it lives in, what it learns shows here.")
        XCTAssertEqual(ProjectPageLines.agentsSharedLine, "AI agents are set up once for every project on this computer. This page shows the ones that work here and what this project gives each.")
        XCTAssertEqual(ProjectPageLines.rulesHereEmpty, "No rule names this project, so the rules of this computer decide here.")
        XCTAssertEqual(ProjectPageLines.rulesLink, "Choose what agents may do in Protection settings")
        XCTAssertEqual(ProjectPageLines.noSkillsGiven, "This project gives its agents no skills.")
        XCTAssertEqual(ProjectPageLines.moreSkillsLine(2), "2 more in Skills")
        XCTAssertEqual(ProjectPageLines.allMemoryLink, "All memory, shared with every project")
        XCTAssertEqual(ProjectPageLines.renameHeading(project()), "Rename \(project().name)")
        XCTAssertEqual([ProjectPageLines.renameInCloud, ProjectPageLines.removeInCloud], ["Rename in Memnox Cloud", "Remove in Memnox Cloud"])
        XCTAssertEqual(ProjectSidebar.goneTitle, "This project is gone")
        XCTAssertEqual(ProjectPage.rules.summary, "The agents given this project, what they carry, and the rules that hold in it.")
    }

    func testSaysACardsLineAsTheWindowsAndLinuxAppDoes() {
        XCTAssertEqual(ProjectLines.cardLine(project()), "Ship the projects view")
        XCTAssertEqual(ProjectLines.appliedLine(ProjectApplySummary()),
                       "Nothing needed applying: every agent here already has this project\u{2019}s instructions.")
    }
}
