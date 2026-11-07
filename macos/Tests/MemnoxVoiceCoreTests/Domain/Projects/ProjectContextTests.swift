import XCTest

@testable import MemnoxVoiceCore

/// Mirrors shared/tauri-core/test/project-context.test.ts.
final class ProjectContextTests: XCTestCase {
    private let everything: Supports = { _ in true }
    private let now = ISO8601DateFormatter().date(from: "2026-11-06T12:00:00Z") ?? Date(timeIntervalSince1970: 0)

    private func project(_ id: String, _ name: String, _ path: String, lastActive: String? = nil) -> ProjectView {
        ProjectView(id: id, name: name, path: path, declared: true, opened: true, agents: [], agentsSeen: [],
                    sessions: ProjectSessionsView(total: 0, ended: 0), servers: [], skills: [],
                    rules: ProjectRulesView(count: 0, inForce: false), instructions: [], memoryScope: "project", openMissions: [],
                    openQuestions: 0, lastActive: lastActive)
    }

    private func fact(_ id: String, project: String?, at: String = "2026-11-01T10:00:00Z") -> MemoryItemView {
        MemoryItemView(id: id, statement: id, scope: project == nil ? .personal : .project, project: project, createdAt: at)
    }

    func testLinksOnlyTheSharedPagesTheDaemonAnswersWithWhatAppliesHere() {
        let links = ProjectContext.shared(SharedCounts(rules: 3, skills: 1), supports: everything)
        XCTAssertEqual(links.map(\.title), ["Protection settings", "Skills", "MCP servers", "Connectors", "Memory", "AI agents"])
        XCTAssertEqual(links.first?.count, 3)
        XCTAssertEqual(links.first?.hint, "3 rules hold here and in every project")
        XCTAssertNil(links[2].count)
        let bare = ProjectContext.shared(SharedCounts(), supports: { _ in false })
        XCTAssertFalse(bare.contains { $0.row == .skills || $0.row == .memory || $0.row == .servers })
        XCTAssertTrue(bare.contains { $0.row == .connectors })
        XCTAssertFalse(ProjectContext.showsShared)
    }

    func testCountsWhatOfEachSharedPageAppliesHereOnceItIsRead() {
        let web = project("p1", "Website", "/code/web")
        let rules = [PolicyRuleView(name: "everywhere", effect: "ask", match: PolicyRuleMatch(actions: ["git.push"]), sentence: "",
                                    source: "person", editable: true),
                     PolicyRuleView(name: "here", effect: "deny", match: PolicyRuleMatch(actions: ["filesystem.delete"], workingDirectories: ["/code/web"]),
                                    sentence: "", source: "person", editable: true)]
        let counts = ProjectContext.counts(web, rules: rules, skills: nil, servers: nil, connections: nil,
                                           memory: [fact("a", project: nil), fact("b", project: "/code/web")], agents: 2)
        XCTAssertEqual(counts, SharedCounts(rules: 1, memory: 1, agents: 2))
    }

    func testTellsWhatBelongsToTheProjectFromWhatIsShared() {
        let web = project("p1", "Website", "/code/web")
        XCTAssertEqual(ProjectContext.reach(skillScope: "project", skillProject: "/code/web", in: web), .onlyHere)
        XCTAssertEqual(ProjectContext.reach(skillScope: "personal", skillProject: nil, in: web), .everyProject)
        XCTAssertNil(ProjectContext.reach(skillScope: "project", skillProject: "/code/other", in: web))
        XCTAssertEqual(ProjectContext.reach(serverGivenEverywhere: true), .everyProject)
        XCTAssertEqual(ProjectContext.reach(memory: fact("a", project: "/code/web/"), in: web), .onlyHere)
        XCTAssertEqual(ProjectContext.reach(memory: fact("b", project: nil), in: web), .everyProject)
        XCTAssertNil(ProjectContext.reach(memory: fact("c", project: "/code/other"), in: web))
        XCTAssertEqual(ItemReach.onlyHere.word, "Only here")
        XCTAssertEqual(ItemReach.everyProject.word, "Every project")
    }

    func testSplitsMemoryIntoWhatTheProjectLearnedAndWhatIsKnownEverywhere() {
        let web = project("p1", "Website", "/code/web")
        let items = [fact("old", project: "/code/web"), fact("new", project: "p1", at: "2026-11-05T10:00:00Z"),
                     fact("shared", project: nil), fact("elsewhere", project: "/code/other")]
        let split = ProjectContext.memory(items, in: web)
        XCTAssertEqual(split.here.map(\.id), ["new", "old"])
        XCTAssertEqual(split.everywhere.map(\.id), ["shared"])
    }

    func testFiltersTheSharedMemoryPageByProjectAndNamesWhoseEachFactIs() {
        let web = project("p1", "Website", "/code/web", lastActive: "2026-11-01T10:00:00Z")
        let report = project("p2", "Report", "/docs/report", lastActive: "2026-11-05T10:00:00Z")
        let items = [fact("w", project: "/code/web"), fact("s", project: nil), fact("x", project: "/code/gone")]
        XCTAssertEqual(ProjectContext.memoryChoices([web, report]).map(\.title), ["All projects", "Shared with every project", "Report", "Website"])
        XCTAssertEqual(ProjectContext.shown(items, .shared, projects: [web]).map(\.id), ["s"])
        XCTAssertEqual(ProjectContext.shown(items, .project("p1"), projects: [web]).map(\.id), ["w"])
        XCTAssertEqual(ProjectContext.shown(items, .project("gone"), projects: [web]).count, 3)
        XCTAssertEqual(items.map { ProjectContext.owner(of: $0, projects: [web]) }, ["Website", "Every project", "gone"])
        XCTAssertEqual(MemoryProjectChoice(key: MemoryProjectChoice.shared.key), .shared)
        XCTAssertEqual(MemoryProjectChoice(key: "p1"), .project("p1"))
    }

    func testSaysWhoWorksInAProjectWhatWaitsAndWhenItWasLastActive() {
        let web = project("p1", "Website", "/code/web", lastActive: "2026-11-06T10:00:00Z")
        let cards = [SessionCard(sessionId: "s1", agent: "claude-code", agentName: "Claude Code", state: "working", repository: "/code/web/app"),
                     SessionCard(sessionId: "s2", agent: "codex-cli", agentName: "Codex", state: "ended", repository: "/code/web"),
                     SessionCard(sessionId: "s3", agent: "cursor", agentName: "Cursor", state: "working", repository: "/code/other")]
        let pulse = ProjectContext.pulse(web, sessions: cards, waitingPlaces: ["web", "other", nil], now: now)
        XCTAssertEqual(pulse.working, ["claude-code"])
        XCTAssertEqual(pulse.workingLine, "Claude Code working now")
        XCTAssertEqual(pulse.waitingLine, "1 waits on you")
        XCTAssertEqual(pulse.lastActivity, "Active now")
        let quiet = ProjectContext.pulse(web, sessions: [], waitingPlaces: [], now: now)
        XCTAssertEqual(quiet.lastActivity, "Active 2 h ago")
        XCTAssertNil(quiet.workingLine)
        XCTAssertEqual(ProjectContext.pulse(project("p2", "New", "/new"), sessions: [], waitingPlaces: [], now: now).lastActivity, "No activity yet")
    }

    func testSortsByRecentAndFindsAProjectByNameOrFolder() {
        let a = project("a", "Website", "/code/web", lastActive: "2026-11-01T10:00:00Z")
        let b = project("b", "Report", "/docs/q3", lastActive: "2026-11-05T10:00:00Z")
        let c = project("c", "Fresh", "/code/fresh")
        XCTAssertEqual(ProjectContext.recent([a, c, b]).map(\.id), ["b", "a", "c"])
        XCTAssertEqual(ProjectContext.matching([a, b, c], query: "code").map(\.id), ["a", "c"])
        XCTAssertEqual(ProjectContext.matching([a, b, c], query: "q3 report").map(\.id), ["b"])
        XCTAssertEqual(ProjectContext.matching([a, b], query: " ").count, 2)
    }

    func testSwitchesProjectsOnThePageThePersonWasOn() {
        let a = project("a", "Website", "/code/web", lastActive: "2026-11-01T10:00:00Z")
        let b = project("b", "Report", "/docs/q3", lastActive: "2026-11-05T10:00:00Z")
        let live = SessionCard(sessionId: "s", agentName: "Codex", state: "working", repository: "/code/web")
        let rows = ProjectContext.switcher([a, b], sessions: [live], current: "a", query: "")
        XCTAssertEqual(rows.map(\.name), ["Report", "Website"])
        XCTAssertEqual(rows.map(\.live), [false, true])
        XCTAssertEqual(rows.map(\.current), [false, true])
        XCTAssertEqual(ProjectContext.switchRoute(to: "b", from: ProjectPlace(id: "a", page: .memory)), ProjectSidebar.route("b", .memory))
        XCTAssertEqual(ProjectContext.switchRoute(to: "b", from: ProjectPlace(id: "a", page: .tools)), ProjectSidebar.route("b"))
    }

    func testNamesTheProjectAHeldCallOrASessionHappensIn() {
        let web = project("a", "Website", "/code/web")
        XCTAssertEqual(ProjectContext.projectName(place: "web", projects: [web]), "Website")
        XCTAssertEqual(ProjectContext.projectName(place: "elsewhere", projects: [web]), "elsewhere")
        XCTAssertNil(ProjectContext.projectName(place: nil, projects: [web]))
        XCTAssertEqual(ProjectContext.projectName(repository: "/code/web/site", projects: [web]), "Website")
        XCTAssertEqual(ProjectContext.projectName(repository: "/code/other", projects: [web]), "other")
        XCTAssertEqual(ProjectContext.inLine("Website"), "In Website")
    }
}
