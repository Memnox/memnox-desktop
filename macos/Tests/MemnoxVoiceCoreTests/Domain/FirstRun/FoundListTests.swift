import XCTest

@testable import MemnoxVoiceCore

final class FoundListTests: XCTestCase {
    private func found(skills count: Int) -> FoundToImport {
        let skills = (0..<count).map { FoundToImport.Skill(id: "f\($0)", agent: "claude-code", name: "skill-\($0)") }
        let servers = [FoundToImport.Server(agent: "cursor", name: "notion"), FoundToImport.Server(agent: "claude-code", name: "github")]
        return FoundToImport(servers: servers, skills: skills + [.init(id: "c1", agent: "codex-cli", name: "release-notes")], agents: 3)
    }

    func testGroupsByAgentWithTheMostFirstAndServersBeforeSkills() {
        let groups = FoundList.groups(found(skills: 90))
        XCTAssertEqual(groups.map(\.agent), ["claude-code", "codex-cli", "cursor"])
        XCTAssertEqual(groups[0].items.first?.name, "github")
        XCTAssertEqual(FoundList.holds(groups[0]), "1 tool and 90 skills")
        XCTAssertEqual(FoundList.holds(groups[2]), "1 tool")
    }

    func testShowsAFewOfALongGroupUntilShowAll() {
        let group = FoundList.groups(found(skills: 90))[0]
        XCTAssertEqual(FoundList.shown(group, expanded: false).count, FoundList.collapsed)
        XCTAssertEqual(FoundList.showAll(group, expanded: false), "Show all 91")
        XCTAssertEqual(FoundList.shown(group, expanded: true).count, 91)
        XCTAssertNil(FoundList.showAll(group, expanded: true))
        XCTAssertNil(FoundList.showAll(FoundList.groups(found(skills: 90))[1], expanded: false))
    }

    func testSearchNarrowsTheRowsAndDropsAgentsWithNone() {
        let groups = FoundList.groups(found(skills: 90), matching: " NOTION ")
        XCTAssertEqual(groups.map(\.agent), ["cursor"])
        XCTAssertTrue(FoundList.groups(found(skills: 3), matching: "nothing like it").isEmpty)
        XCTAssertEqual(FoundList.noMatch(" xyz "), "Nothing matches xyz.")
    }

    func testImportsOnlyWhatWasNotLeftOut() {
        let all = found(skills: 2)
        let kept = FoundList.kept(all, leaving: ["server:cursor:notion", "skill:c1"])
        XCTAssertEqual(kept.servers.map(\.name), ["github"])
        XCTAssertEqual(kept.skills.map(\.id), ["f0", "f1"])
        XCTAssertEqual(kept.agents, 1)
        XCTAssertEqual(FoundList.importTitle(kept: 3, of: 5), "Import 3 of 5")
        XCTAssertEqual(FoundList.importTitle(kept: 5, of: 5), "Import all 5")
        XCTAssertEqual(FoundList.importTitle(kept: 0, of: 5), "Nothing chosen")
    }
}
