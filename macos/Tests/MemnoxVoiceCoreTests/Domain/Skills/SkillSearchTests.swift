import XCTest

@testable import MemnoxVoiceCore

final class SkillSearchTests: XCTestCase {
    private let home = "/Users/me"

    private func found(_ name: String, _ agent: String, imported: Bool = false, tools: [String] = []) -> FoundSkillView {
        FoundSkillView(id: name, name: name, agent: agent, kind: "skill", path: "\(home)/.agents/skills/\(name)", tools: tools,
                       grant: "", imported: imported)
    }

    private func label(_ agent: String) -> String {
        agent == "codex-cli" ? "Codex CLI" : "Claude Code"
    }

    func testNarrowsWhatAgentsHadByEveryWordTypedOnNameAgentAndPath() {
        let list = [found("gsap-core", "codex-cli"), found("higgsfield-video-explainer", "codex-cli"), found("higgsfield-websites", "claude-code"),
                    found("higgs-old", "codex-cli", imported: true)]
        XCTAssertEqual(SkillSearch.found(list, "HIGGS", label: label).map(\.name), ["higgsfield-video-explainer", "higgsfield-websites"])
        XCTAssertEqual(SkillSearch.found(list, "higgs video", label: label).map(\.name), ["higgsfield-video-explainer"])
        XCTAssertEqual(SkillSearch.found(list, "claude", label: label).map(\.name), ["higgsfield-websites"])
        XCTAssertEqual(SkillSearch.found(list, "  ", label: label).count, 3)
    }

    func testGroupsByAgentInTheOrderOfTheirLabels() {
        let groups = SkillSearch.grouped([found("b", "codex-cli"), found("a", "codex-cli"), found("c", "claude-code")], label: label)
        XCTAssertEqual(groups.map(\.label), ["Claude Code", "Codex CLI"])
        XCTAssertEqual(groups.last?.skills.map(\.name), ["a", "b"])
    }

    func testCountsWhatASearchLeavesAndSaysWhenNothingMatches() {
        XCTAssertEqual(SkillSearch.counted(shown: 3, of: 12, searching: true), "3 of 12")
        XCTAssertEqual(SkillSearch.counted(shown: 12, of: 12, searching: true), "12")
        XCTAssertEqual(SkillSearch.counted(shown: 3, of: 12, searching: false), "12")
        XCTAssertEqual(SkillSearch.noMatch(" higgs "), "No skills match \u{201C}higgs\u{201D}")
        XCTAssertEqual(SkillSearch.noMatchDetail(foundMatching: 2), "Nothing in the hub has that yet, but 2 skills agents already have match below, ready to import.")
    }

    func testSaysWhatImportAllTakesAndWhatItCameTo() {
        XCTAssertEqual(SkillSearch.importAllTitle(83, searching: false), "Import all 83")
        XCTAssertEqual(SkillSearch.importAllTitle(9, searching: true), "Import 9 shown")
        XCTAssertEqual(SkillSearch.importing(done: 4, of: 9), "Importing 4 of 9")
        XCTAssertEqual(SkillSearch.imported(ImportResults(done: 8, proposed: 1)), "8 skills are in the hub now. 1 waits for your signature on the island.")
        XCTAssertEqual(SkillSearch.imported(ImportResults(failed: ["Its folder would not read."])), "1 did not import: Its folder would not read.")
        XCTAssertEqual(SkillSearch.imported(ImportResults()), "Nothing was imported.")
    }

    func testWritesTheHomeFolderAsATildeAndFindsTheInstructionsFile() {
        XCTAssertEqual(SkillSearch.shortPath("/Users/me/.agents/skills/x", home: home), "~/.agents/skills/x")
        XCTAssertEqual(SkillSearch.shortPath("/Users/meg/x", home: home), "/Users/meg/x")
        XCTAssertEqual(SkillSearch.instructionsFile(found("x", "codex-cli")), "/Users/me/.agents/skills/x/SKILL.md")
        XCTAssertNil(SkillSearch.reach(found("x", "codex-cli")))
        XCTAssertEqual(SkillSearch.reach(found("x", "codex-cli", tools: ["Read", "Bash"])), "Uses Read and Bash")
    }
}
