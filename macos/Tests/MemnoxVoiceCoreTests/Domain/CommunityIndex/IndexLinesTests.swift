import XCTest

@testable import MemnoxVoiceCore

/// Mirrors the wording half of shared/tauri-core/test/community-index.test.ts, with Touch ID for the key.
final class IndexLinesTests: XCTestCase {
    private let skill = IndexEntryView(id: "lst_1", name: "release-notes", kind: .skill, description: "Drafts notes", category: "Writing",
                                       publisher: IndexPublisher(kind: "organization", name: "Acme"), license: "MIT",
                                       agents: ["claude-code", "codex-cli"], latest: IndexVersion(version: "1.2.0", digest: "sha256:abc"),
                                       yanked: ["1.1.0"])
    private let pack = IndexEntryView(id: "lst_2", name: "careful-pushes", kind: .rulePack, description: "Asks first", category: "Git",
                                      publisher: IndexPublisher(kind: "member", name: "Sam"), yanked: ["1.0.0", "1.0.1"], unsafe: true)

    func testNamesTheKindThePublisherAndTheAgents() {
        XCTAssertEqual(IndexLines.kindWord("rule_pack"), "Rule pack")
        XCTAssertEqual(IndexLines.kindWord("skill"), "Skill")
        XCTAssertEqual(IndexLines.publisher(skill.publisher), "By Acme")
        XCTAssertEqual(IndexLines.supportedAgents(skill.agents), "For Claude Code and Codex")
        XCTAssertEqual(IndexLines.supportedAgents([]), "Works with every agent")
    }

    func testOffersTheLatestSafeVersionAndNeverOneMarkedUnsafe() {
        XCTAssertEqual(IndexLines.latest(skill), "v1.2.0")
        XCTAssertTrue(IndexLines.canInstall(skill))
        XCTAssertEqual(IndexLines.latest(pack), "No safe version to install")
        XCTAssertFalse(IndexLines.canInstall(pack))
        XCTAssertEqual(IndexLines.yanked(pack.yanked), "2 versions marked unsafe")
        XCTAssertEqual(IndexLines.yanked(skill.yanked), "1 version marked unsafe")
        XCTAssertNil(IndexLines.yanked([]))
    }

    func testSaysWhatIsInMySkillsAndWhereAnInstallWaits() {
        let held = IndexEntryView(id: "x", name: "n", kind: .skill, description: "d", publisher: skill.publisher, installed: "1.0.0")
        XCTAssertEqual(IndexLines.installed(held), "v1.0.0 in My Skills")
        XCTAssertNil(IndexLines.installed(skill))
        XCTAssertEqual(IndexLines.installWaits(kind: "skill", keyTitle: "Touch ID"),
                       "Installing a skill puts it in My Skills, where it waits for you to accept it before any agent is given it.")
        XCTAssertEqual(IndexLines.installWaits(kind: "rule_pack", keyTitle: "Touch ID"),
                       "Installing a rule pack proposes each of its rules, and each waits for your signature with Touch ID on the island.")
    }

    func testFiltersByCategoryOnTheWindow() {
        XCTAssertEqual(IndexLines.categories([skill, pack, skill]), ["Git", "Writing"])
        XCTAssertEqual(IndexLines.inCategory([skill, pack], "Git").map(\.name), ["careful-pushes"])
        XCTAssertEqual(IndexLines.inCategory([skill, pack], nil).count, 2)
    }

    func testSaysWhereTheIndexCameFromOrWhyItIsNotFresh() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-30T12:00:00Z"))
        let index = CommunityIndexView(source: "https://memnox.com/index.json", fetchedAt: "2026-10-30T11:55:00Z", entries: [skill, pack])
        XCTAssertEqual(IndexLines.state(index, now: now), "Read from https://memnox.com/index.json 5 minutes ago.")
        let offline = CommunityIndexView(source: "s", said: "Offline, so this is what was read yesterday.")
        XCTAssertEqual(IndexLines.state(offline, now: now), "Offline, so this is what was read yesterday.")
        XCTAssertEqual(IndexLines.state(CommunityIndexView(source: "git", complete: false), now: now),
                       "Not read from git yet. It held more than it carries, so some listings are not shown.")
    }

    func testSaysAnInstallInALine() {
        XCTAssertEqual(IndexLines.installedNote(IndexInstalled(id: "1", name: "release-notes", kind: .skill, version: "1.2.0", digest: "d", held: true), keyTitle: "Touch ID"),
                       "release-notes v1.2.0 is in My Skills, waiting for you to accept it.")
        XCTAssertEqual(IndexLines.installedNote(IndexInstalled(id: "2", name: "careful", kind: .rulePack, version: "2.0.0", digest: "d", proposed: ["p1", "p2", "p3"]), keyTitle: "Touch ID"),
                       "3 rules wait from careful v2.0.0 for your signature with Touch ID on the island.")
    }
}
