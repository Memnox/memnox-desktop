import XCTest

@testable import MemnoxVoiceCore

let sampleProject = ProjectView(
    id: "prj_1", name: "memnox-desktop", path: "/code/memnox-desktop", declared: true, opened: true,
    agents: ["claude-code", "codex-cli"], agentsSeen: ["claude-code"], sessions: ProjectSessionsView(total: 4, ended: 3),
    servers: [ProjectGrantView(name: "github", inHub: true, agents: ["claude-code"])],
    skills: [ProjectGrantView(name: "review-checklist", inHub: true, agents: ["claude-code", "codex-cli"]),
             ProjectGrantView(name: "gone", inHub: false, agents: [])],
    rules: ProjectRulesView(file: "memnox.policies.toml", count: 3, inForce: true),
    instructions: [ProjectInstructionView(path: "CLAUDE.md", source: true, present: true, agents: ["claude-code"], written: false)],
    memoryScope: "project", openMissions: [ProjectMissionView(id: "m1", statement: "Ship the projects view", startedAt: "2026-10-29T10:00:00Z")],
    openQuestions: 2)

/// Mirrors the wording half of shared/tauri-core/test/projects.test.ts.
final class ProjectLinesTests: XCTestCase {
    private func changed(declared: Bool = true, opened: Bool = true, problems: [String]? = nil, agents: [String]? = nil,
                         servers: [ProjectGrantView]? = nil, skills: [ProjectGrantView]? = nil, rules: ProjectRulesView? = nil,
                         instructions: [ProjectInstructionView]? = nil, memoryScope: String? = nil) -> ProjectView {
        let base = sampleProject
        return ProjectView(id: base.id, name: base.name, path: base.path, declared: declared, problems: problems, opened: opened,
                           agents: agents ?? base.agents, agentsSeen: base.agentsSeen, sessions: base.sessions,
                           servers: servers ?? base.servers, skills: skills ?? base.skills, rules: rules ?? base.rules,
                           instructions: instructions ?? base.instructions, memoryScope: memoryScope ?? base.memoryScope,
                           openMissions: base.openMissions, openQuestions: base.openQuestions)
    }

    private func rule(_ name: String, file: String? = nil, folders: [String]? = nil) -> PolicyRuleView {
        PolicyRuleView(name: name, effect: "ask", match: PolicyRuleMatch(actions: ["git.push"], workingDirectories: folders),
                       sentence: name, source: "file", file: file, editable: false)
    }

    func testCountsAgentsSkillsServersAndTheRulesInForceNeverAScore() {
        XCTAssertEqual(ProjectLines.tiles(sampleProject), [
            ProjectTile(value: 2, label: "Agents"), ProjectTile(value: 2, label: "Skills"),
            ProjectTile(value: 1, label: "MCP server"), ProjectTile(value: 3, label: "Active rules"),
        ])
        let idle = changed(rules: ProjectRulesView(file: "memnox.policies.toml", count: 3, inForce: false))
        XCTAssertEqual(ProjectLines.tiles(idle).last, ProjectTile(value: 0, label: "Active rules"))
    }

    func testSaysAManifestThatWillNotReadBeforeAnythingElse() {
        XCTAssertEqual(ProjectLines.standing(changed(problems: ["bad toml"])).word, "Manifest will not read")
        XCTAssertEqual(ProjectLines.standing(changed(problems: ["bad toml"])).tone, .bad)
        XCTAssertEqual(ProjectLines.standing(changed(declared: false)).word, "Found, not saved")
        XCTAssertEqual(ProjectLines.standing(changed(opened: false)).word, "Not opened here")
        XCTAssertEqual(ProjectLines.standing(sampleProject).word, "Opened")
    }

    func testNamesTheAgentsThatReadAnInstructionFile() {
        XCTAssertEqual(ProjectLines.readersLine(["claude-code", "codex-cli"]), "Claude Code and Codex read it")
        XCTAssertEqual(ProjectLines.readersLine(["cursor"]), "Cursor reads it")
        XCTAssertEqual(ProjectLines.readersLine([]), "No agent here reads it")
        XCTAssertEqual(ProjectLines.instructionWord(ProjectInstructionView(path: "a", source: true, present: true, agents: [], written: true)),
                       "Source, written by Memnox")
        XCTAssertEqual(ProjectLines.instructionWord(ProjectInstructionView(path: "a", source: false, present: false, agents: [], written: false)),
                       "Missing")
    }

    func testSaysAGrantTheHubLacksReachesNobody() {
        XCTAssertEqual(ProjectLines.grantLine(ProjectGrantView(name: "g", inHub: true, agents: ["claude-code"]), of: 2), "Given to 1 of 2 agents")
        XCTAssertEqual(ProjectLines.grantLine(ProjectGrantView(name: "g", inHub: false, agents: []), of: 2),
                       "Not in the hub on this computer, so no agent is given it")
    }

    func testSaysWhyNoRuleOfTheProjectIsInForce() {
        XCTAssertEqual(ProjectLines.rulesLine(sampleProject.rules), "3 rules from memnox.policies.toml, in force.")
        XCTAssertEqual(ProjectLines.rulesLine(ProjectRulesView(count: 0, inForce: false)),
                       "This project names no rule file, so the rules of this computer hold.")
        XCTAssertEqual(ProjectLines.rulesLine(ProjectRulesView(file: "p.toml", count: 1, inForce: false)),
                       "1 rule in p.toml, not in force until applying is signed.")
        XCTAssertEqual(ProjectLines.rulesLine(ProjectRulesView(file: "p.toml", count: 0, inForce: false, problem: "no such file")),
                       "p.toml will not load: no such file")
        XCTAssertEqual(ProjectLines.questionsLine(0), "No open questions")
        XCTAssertEqual(ProjectLines.questionsLine(1), "1 open question")
    }

    func testSaysWhatApplyingDidAtOnceAndWhatTheHubLacks() {
        XCTAssertEqual(ProjectLines.appliedLine(ProjectApplySummary(written: ["AGENTS.md", "CLAUDE.md"], kept: [".cursorrules"], missing: ["linear"])),
                       "Wrote 2 instruction files, left 1 of yours alone. The hub here lacks linear, so no agent is given it.")
        XCTAssertEqual(ProjectLines.appliedLine(ProjectApplySummary()),
                       "Nothing needed applying: every agent here already has this project\u{2019}s instructions.")
    }

    func testCountsAnApplyThatChangedNothingAsUpToDate() {
        XCTAssertTrue(ProjectLines.upToDate(ProjectApplySummary()))
        XCTAssertTrue(ProjectLines.upToDate(ProjectApplySummary(kept: [".cursorrules"], missing: ["linear"])))
        XCTAssertFalse(ProjectLines.upToDate(ProjectApplySummary(written: ["AGENTS.md"])))
        XCTAssertFalse(ProjectLines.upToDate(ProjectApplySummary(removed: ["AGENTS.md"])))
        XCTAssertFalse(ProjectLines.upToDate(ProjectApplySummary(governed: ["linear"])))
        XCTAssertEqual(ProjectLines.mark(.upToDate("x")), .upToDate)
        XCTAssertEqual(ProjectLines.mark(.done("x")), .changed)
        XCTAssertEqual(ProjectLines.mark(.proposed(id: "p", note: "x")), .waiting)
        XCTAssertEqual(ProjectLines.mark(.failed("x")), .failed)
        XCTAssertEqual(ProjectLines.note(.upToDate("Nothing.")), "Nothing.")
    }

    func testKeepsToTheRulesThatReachIntoTheProjectCountingTheOnesThatHoldEverywhereApart() {
        let rules = [
            rule("from-file", file: "/code/memnox-desktop/memnox.policies.toml"),
            rule("in-folder", folders: ["/code/memnox-desktop/**"]),
            rule("elsewhere", folders: ["/code/other"]),
            rule("everywhere"),
        ]
        let found = ProjectLines.rules(rules, in: sampleProject)
        XCTAssertEqual(found.here.map(\.name), ["from-file", "in-folder"])
        XCTAssertEqual(found.everywhere, 1)
    }

    func testMakesAFoundProjectIntoTheManifestItShowsNow() {
        XCTAssertEqual(ProjectLines.draft(of: sampleProject), ProjectDraft(
            name: "memnox-desktop", instructions: ["CLAUDE.md"], servers: ["github"], skills: ["review-checklist", "gone"],
            agents: ["claude-code", "codex-cli"], policy: "memnox.policies.toml", memory: "project"))
        let bare = changed(agents: [], servers: [], skills: [], rules: ProjectRulesView(count: 0, inForce: false), instructions: [], memoryScope: "")
        XCTAssertEqual(ProjectLines.draft(of: bare), ProjectDraft(name: "memnox-desktop"))
    }

    func testOffersOnlyTheSessionFoldersThatAreNotProjectsYet() {
        let seen = [FolderPick(path: "/code/memnox-desktop/", name: "memnox-desktop"), FolderPick(path: "/code/other", name: "other")]
        XCTAssertEqual(ProjectLines.foldersToOpen(seen, projects: [sampleProject]), [FolderPick(path: "/code/other", name: "other")])
    }

    func testSaysWhatWaitsOnTheIslandWithTheKeyThatSignsIt() {
        XCTAssertEqual(ProjectLines.note(.proposed(id: "prp_1", note: "Applied.")),
                       "Applied. Its servers, skills and rules wait for you on the island: confirm them with Touch ID.")
        XCTAssertEqual(ProjectLines.note(.failed("No project prj_9.")), "No project prj_9.")
        // The same words as the Windows and Linux app's everywhereLine, pinned in test/projects.test.ts.
        XCTAssertEqual(ProjectLines.everywhereLine(1), "1 rule of this computer holds here too, as in every project.")
        XCTAssertEqual(ProjectLines.everywhereLine(3), "3 rules of this computer hold here too, as in every project.")
    }

    func testSaysWhatAnOrganizationHandsASharedProject() {
        let organization = ProjectOrganizationView(id: "op_1", name: "API", repository: "github.com/acme/api", rulePack: "Release rules",
                                                   rules: 4, memory: "project", editedIn: "API is changed in Memnox Cloud.")
        XCTAssertEqual(ProjectLines.organizationRulesLine(organization), "Release rules, 4 rules")
        let bare = ProjectOrganizationView(id: "op_2", name: "Web", repository: "github.com/acme/web", memory: "none", editedIn: "")
        XCTAssertEqual(ProjectLines.organizationRulesLine(bare), "No rule pack from the organization.")
        XCTAssertEqual(ProjectLines.organizationMemoryLine("none"), "Its agents keep no memory from this project.")
        XCTAssertEqual(ProjectLines.organizationMemoryLine("project"),
                       "What its agents learn is kept under the organization’s project rather than this folder.")
        XCTAssertEqual(ProjectLines.fromOrganization, "From your organization")
    }
}

final class ProjectCardLinesTests: XCTestCase {
    private func shared(description: String?) -> ProjectView {
        let base = sampleProject
        return ProjectView(id: base.id, name: base.name, path: base.path, declared: true, opened: true, agents: base.agents,
                           agentsSeen: base.agentsSeen, sessions: ProjectSessionsView(total: 0, ended: 0), servers: [], skills: [],
                           rules: base.rules, instructions: [], memoryScope: "none", openMissions: [], openQuestions: 0,
                           scope: .organization,
                           organization: ProjectOrganizationView(id: "o1", name: "Shop", repository: "github.com/acme/shop",
                                                                 description: description, servers: ["github", "linear"],
                                                                 skills: ["review"], memory: "project", editedIn: "Edited in Memnox Cloud"))
    }

    func testNamesTheSharedRepositoryElseTheFolderHere() {
        XCTAssertEqual(ProjectLines.repositoryLine(shared(description: nil)), "github.com/acme/shop")
        XCTAssertEqual(ProjectLines.repositoryLine(sampleProject), "/code/memnox-desktop")
        XCTAssertEqual(ProjectLines.noRepository, "No repository yet")
    }

    func testSaysWhatItIsForThenItsMissionThenItsSessions() {
        XCTAssertEqual(ProjectLines.cardLine(shared(description: "The storefront")), "The storefront")
        XCTAssertEqual(ProjectLines.cardLine(sampleProject), "Ship the projects view")
        XCTAssertEqual(ProjectLines.cardLine(shared(description: nil)), "No agent has worked here yet.")
    }

    func testChipsCountServersAndSkillsAndSayWhetherItKeepsMemory() {
        XCTAssertEqual(ProjectLines.chips(sampleProject), ["1 server", "2 skills", "Memory"])
        XCTAssertEqual(ProjectLines.chips(shared(description: nil)), ["2 servers", "1 skill", "Memory"])
    }
}
