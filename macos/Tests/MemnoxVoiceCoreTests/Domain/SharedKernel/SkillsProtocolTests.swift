import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// The Skills Hub as the runtime's daemon/skills-hub.ts writes it.
final class SkillsProtocolTests: XCTestCase {
    static let skill = #"{"name":"release-notes","scope":"personal","category":"Writing","version":"1.2.0","description":"Drafts release notes from merged pull requests","enabled":true,"digest":"sha256:abc","held":{"standing":"widened","gained":["Bash"],"signed":true},"agents":["claude-code"],"assignments":[{"agent":"claude-code"},{"agent":"cursor","project":"/code/app"}],"compatibility":[{"agent":"claude-code","label":"Claude Code","supported":true,"loses":[]},{"agent":"cursor","label":"Cursor","supported":true,"loses":["Its tool grant, since Cursor rules carry none"]}],"versions":[{"version":"1.1.0","current":false,"acceptedAt":"2026-10-01T10:00:00Z","digest":"sha256:old"},{"version":"1.2.0","current":true}],"updatedAt":"2026-10-26T10:00:00Z","files":["template.md"],"instructions":"Read the merged pull requests.","tools":["Read"],"mcpServers":["github"],"permissions":{"filesystem":[],"network":["api.github.com"],"commands":["gh"]},"dependencies":[]}"#

    static let hub = #"{"skills":["# + skill + #"],"found":[{"id":"f1","name":"frontend-design","agent":"claude-code","kind":"skill","path":"/Users/me/.claude/skills/frontend-design","tools":["Read"],"grant":"reads files","imported":false}],"agents":[{"agent":"claude-code","label":"Claude Code","installed":true},{"agent":"cursor","label":"Cursor","installed":false}]}"#

    func testReadsEveryPartOfTheHub() throws {
        let view = try XCTUnwrap(try line(#"{"id":1,"ok":true,"skillsHub":"# + Self.hub + "}").skillsHub)
        let skill = try XCTUnwrap(view.skills.first)
        XCTAssertEqual(skill.skillScope, .personal)
        XCTAssertEqual(skill.held?.skillStanding, .widened)
        XCTAssertEqual(skill.held?.gained, ["Bash"])
        XCTAssertEqual(skill.assignments.map(\.project), [nil, "/code/app"])
        XCTAssertEqual(skill.compatibility.last?.loses.count, 1)
        XCTAssertEqual(skill.versions.map(\.current), [false, true])
        XCTAssertNil(skill.versions.last?.acceptedAt)
        XCTAssertEqual(skill.permissions.commands, ["gh"])
        XCTAssertNil(skill.problems)
        XCTAssertEqual(view.found.first?.imported, false)
        XCTAssertEqual(view.agents.map(\.installed), [true, false])
    }

    func testReadsASyncAndAnOlderRuntimeLeavesTheHubOut() throws {
        let synced = try line(#"{"id":2,"ok":true,"skillsSynced":{"written":2,"removed":1,"files":["/a"],"skipped":[{"skill":"a","agent":"b","path":"p","reason":"r"}]}}"#)
        XCTAssertEqual(synced.skillsSynced, SkillsSyncSummary(written: 2, removed: 1, files: ["/a"], skipped: [SkillSkip(skill: "a", agent: "b", path: "p", reason: "r")]))
        let older = try line(#"{"id":3,"ok":true}"#)
        XCTAssertNil(older.skillsHub)
        XCTAssertNil(older.skillsSynced)
    }

    func testAnUnknownStandingIsKeptButNotNamed() throws {
        let held = try JSONDecoder().decode(SkillHold.self, from: Data(#"{"standing":"moved","gained":[],"signed":false}"#.utf8))
        XCTAssertNil(held.skillStanding)
        XCTAssertEqual(held.standing, "moved")
    }

    func testWritesADraftAndAnAssignWithOnlyTheFieldsFilledIn() throws {
        var put = DaemonRequest(id: 4, method: .skillPut)
        put.skillDraft = SkillDraft(name: "release-notes", version: "1.0.0", description: "Drafts notes", instructions: "Do it.",
                                    tools: ["Read"], permissions: SkillDraftPermissions(commands: ["gh"]))
        put.skillScope = SkillScope.personal.rawValue
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encodeLine(put)) as? [String: Any])
        XCTAssertEqual(object["method"] as? String, "skill-put")
        XCTAssertEqual(object["skillScope"] as? String, "personal")
        let draft = try XCTUnwrap(object["skillDraft"] as? [String: Any])
        XCTAssertNil(draft["category"])
        XCTAssertEqual(draft["permissions"] as? [String: [String]], ["commands": ["gh"]])

        var assign = DaemonRequest(id: 5, method: .skillAssign)
        assign.skillName = "release-notes"
        assign.skillAgent = "cursor"
        assign.skillOn = false
        let assigned = try XCTUnwrap(JSONSerialization.jsonObject(with: encodeLine(assign)) as? [String: Any])
        XCTAssertEqual(assigned["skillAgent"] as? String, "cursor")
        XCTAssertEqual(assigned["skillOn"] as? Bool, false)
        XCTAssertNil(assigned["skillDraft"])
    }

    func testNamesEveryMethodAsTheRuntimeDoes() {
        let methods: [DaemonMethod] = [.skillsHub, .skillImport, .skillPut, .skillAssign, .skillDisable, .skillEnable, .skillSync,
                                       .skillRollback, .skillAccept]
        XCTAssertEqual(methods.map(\.rawValue), ["skills-hub", "skill-import", "skill-put", "skill-assign", "skill-disable",
                                                 "skill-enable", "skill-sync", "skill-rollback", "skill-accept"])
    }
}
