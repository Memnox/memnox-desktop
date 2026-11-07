import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Mirrors the words half of shared/tauri-core/test/skills.test.ts, so a skill reads the same on every desktop.
final class SkillsLinesTests: XCTestCase {
    private func skill() throws -> SkillView {
        try JSONDecoder().decode(SkillView.self, from: Data(SkillsProtocolTests.skill.utf8))
    }

    func testCountsTheAgentsAndTheDaysNeverAScore() throws {
        XCTAssertEqual(SkillsLines.assigned(0), "No agents assigned")
        XCTAssertEqual(SkillsLines.assigned(1), "1 agent assigned")
        XCTAssertEqual(SkillsLines.assigned(3), "3 agents assigned")
        let now = try XCTUnwrap(readInstant("2026-10-30T12:00:00Z"))
        XCTAssertEqual(SkillsLines.updated("2026-10-30T09:00:00Z", now: now), "Updated today")
        XCTAssertEqual(SkillsLines.updated("2026-10-29T09:00:00.000Z", now: now), "Updated yesterday")
        XCTAssertEqual(SkillsLines.updated("2026-10-26T10:00:00Z", now: now), "Updated 4 days ago")
        XCTAssertEqual(SkillsLines.categoryVersion(try skill()), "Writing · v1.2.0")
        XCTAssertEqual(SkillsLines.categoryVersion(category: nil, version: "2.0.0"), "v2.0.0")
    }

    func testSaysWhyASkillIsHeldAndWhetherAcceptingItIsSigned() {
        XCTAssertEqual(SkillsLines.held(SkillHold(standing: .widened, gained: ["Bash", "curl"], signed: true)),
                       "Its folder reaches further than the version you accepted, so nothing new of it is handed out. It now reaches Bash and curl. Accepting it waits for your signature on the island.")
        XCTAssertTrue(SkillsLines.held(SkillHold(standing: .changed, gained: [], signed: false)).hasSuffix("Accepting it happens at once."))
    }

    func testSaysWhatEachAgentKeepsAndListsTheLossesForTheAgentsChosen() throws {
        XCTAssertEqual(SkillsLines.compatibility(supported: true, loses: []), "Keeps everything")
        XCTAssertEqual(SkillsLines.compatibility(supported: true, loses: ["a", "b"]), "Loses 2 things in conversion")
        XCTAssertEqual(SkillsLines.compatibility(supported: false, loses: []), "Cannot take skills")
        let compatibility = try skill().compatibility
        XCTAssertEqual(SkillsLines.conversionLosses(compatibility, chosen: ["cursor"]),
                       [ConversionLoss(label: "Cursor", loses: ["Its tool grant, since Cursor rules carry none"])])
        XCTAssertEqual(SkillsLines.conversionLosses(compatibility, chosen: ["claude-code"]), [])
    }

    func testSaysASyncInALine() {
        XCTAssertEqual(SkillsLines.synced(SkillsSyncSummary(written: 3, removed: 1, skipped: [SkillSkip(skill: "a", agent: "b", path: "p", reason: "r")])),
                       "Wrote 3, removed 1, skipped 1.")
        XCTAssertEqual(SkillsLines.synced(SkillsSyncSummary(written: 0, removed: 0)), "Every agent already has the skills the hub gives it.")
    }

    func testListsOnlyTheKindsOfReachASkillAsksFor() throws {
        XCTAssertEqual(SkillsLines.permissions(try skill()).map(\.title), ["Agent tools", "MCP servers", "Commands", "Hosts"])
    }

    func testTheAssignSheetSendsOnlyWhatChanged() {
        XCTAssertEqual(SkillsLines.assignmentChanges(current: ["claude-code", "codex-cli"], chosen: ["codex-cli", "cursor"]),
                       AssignmentChanges(give: ["cursor"], take: ["claude-code"]))
    }

    func testSaysTheGivesWaitOnTheIslandAndTheTakesHappened() {
        XCTAssertEqual(SkillsLines.assignedNote(proposed: 2, done: 1, failed: [], keyTitle: "Touch ID"),
                       "2 agents wait for your signature with Touch ID on the island. 1 change made at once.")
        XCTAssertEqual(SkillsLines.assignedNote(proposed: 0, done: 0, failed: [], keyTitle: "Touch ID"), "Nothing changed.")
        XCTAssertEqual(SkillsLines.assignedNote(proposed: 1, done: 0, failed: ["no such agent"], keyTitle: "Touch ID"), "no such agent")
    }

    func testNamesANewSkillAsEveryAgentFolderTakesItAndFillsTheVersion() {
        let form = SkillForm(name: "Release Notes!", description: "Drafts notes", instructions: "Do it.", tools: "Read, Bash")
        XCTAssertEqual(SkillsLines.name(from: "  Release Notes! "), "release-notes")
        XCTAssertEqual(SkillsLines.draft(from: form),
                       .success(SkillDraft(name: "release-notes", version: "1.0.0", description: "Drafts notes", instructions: "Do it.", tools: ["Read", "Bash"])))
    }

    func testSaysWhatTheFormIsMissing() {
        let form = SkillForm(name: "Release Notes!", description: "Drafts notes", instructions: "Do it.")
        var nameless = form
        nameless.name = "!!"
        XCTAssertEqual(SkillsLines.draft(from: nameless), .failure(SkillFormProblem("Give the skill a name.")))
        var empty = form
        empty.instructions = " "
        XCTAssertEqual(SkillsLines.draft(from: empty), .failure(SkillFormProblem("Write the instructions the agent follows.")))
    }
}
