import XCTest

@testable import MemnoxVoiceCore

/// Mirrors the use case half of shared/tauri-core/test/projects.test.ts.
final class ProjectsTests: XCTestCase {
    private static let view = #""projects":{"projects":[{"id":"prj_1","name":"memnox-desktop","path":"/code/memnox-desktop","declared":true,"opened":true,"agents":["claude-code"],"agentsSeen":["claude-code"],"sessions":{"total":4,"ended":3},"servers":[],"skills":[],"rules":{"count":0,"inForce":false},"instructions":[],"memoryScope":"project","openMissions":[],"openQuestions":0,"lastActive":"2026-10-30T11:58:00Z"}]}"#

    func testReadsTheProjectsAndSaysWhenTheRuntimeDoesNotAnswer() async throws {
        let link = ScriptedLink()
        link.answers["projects"] = [try line(#"{"id":1,"ok":true,"# + Self.view + "}")]
        let projects = Projects(link: link)
        await projects.refresh()
        XCTAssertEqual(projects.projects?.first?.name, "memnox-desktop")
        XCTAssertEqual(projects.projects?.first?.lastActive, "2026-10-30T11:58:00Z")
        XCTAssertFalse(projects.unreadable)

        let down = ScriptedLink()
        down.unreachable = true
        let gone = Projects(link: down)
        await gone.refresh()
        XCTAssertTrue(gone.unreadable)
    }

    func testOpensAFolderSayingWhatWentAtOnceAndThatTheRestWaitsOnTheIsland() async throws {
        let link = ScriptedLink()
        link.answers["project-open"] = [try line(#"{"id":1,"ok":true,"proposed":"prp_1","projectApplied":{"written":["CLAUDE.md"],"removed":[],"kept":[],"governed":[],"missing":[]},"# + Self.view + "}")]
        let projects = Projects(link: link)
        let outcome = await projects.open(" /code/memnox-desktop ")
        XCTAssertEqual(outcome, .proposed(id: "prp_1", note: "Wrote 1 instruction file."))
        XCTAssertEqual(link.sent.first?.projectPath, "/code/memnox-desktop")
        XCTAssertEqual(projects.projects?.count, 1)
        XCTAssertNil(projects.busy)
    }

    func testSavesAFoundProjectAndAppliesOneByIdPassingARefusalOnInTheRuntimesWords() async throws {
        let link = ScriptedLink()
        link.answers["project-put"] = [try line(#"{"id":1,"ok":true,"# + Self.view + "}")]
        link.answers["project-apply"] = [try line(#"{"id":2,"ok":false,"error":"No project prj_9."}"#)]
        let projects = Projects(link: link)
        let saved = await projects.put("/code/memnox-desktop", draft: ProjectDraft(name: "memnox-desktop"))
        XCTAssertEqual(saved, .done("Saved memnox-desktop as a project in .memnox/project.toml. Commit it so every clone has it."))
        XCTAssertEqual(link.sent.first?.projectDraft, ProjectDraft(name: "memnox-desktop"))
        XCTAssertEqual(link.sent.first?.projectPath, "/code/memnox-desktop")
        let refused = await projects.apply("prj_9")
        XCTAssertEqual(refused, .failed("No project prj_9."))
        XCTAssertEqual(link.sent.last?.projectId, "prj_9")
    }

    func testSendsTheDraftWithOnlyTheListsItHas() throws {
        var request = DaemonRequest(id: 1, method: .projectPut)
        request.projectDraft = ProjectDraft(name: "app", skills: ["review"])
        let json = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        XCTAssertTrue(json.contains(#""projectDraft":{"#))
        XCTAssertTrue(json.contains(#""skills":["review"]"#))
        XCTAssertFalse(json.contains("servers"))
    }
}
