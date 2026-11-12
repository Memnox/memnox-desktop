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

    func testNamesThePublisherAndOffersOnlyASafeVersion() {
        XCTAssertEqual(IndexLines.publisher(skill.publisher), "By Acme")
        XCTAssertEqual(IndexLines.latest(skill), "v1.2.0")
        XCTAssertTrue(IndexLines.canInstall(skill))
        XCTAssertEqual(IndexLines.latest(pack), "No safe version to install")
        XCTAssertFalse(IndexLines.canInstall(pack))
    }

    func testSaysWhereAnInstallWaits() {
        XCTAssertEqual(IndexLines.installWaits(kind: "rule_pack", keyTitle: "Touch ID"),
                       "Installing a rule pack proposes each of its rules, and each waits for your signature with Touch ID on the island.")
    }

    func testSaysAnInstallInALine() {
        XCTAssertEqual(IndexLines.installedNote(IndexInstalled(id: "1", name: "release-notes", kind: .skill, version: "1.2.0", digest: "d", held: true), keyTitle: "Touch ID"),
                       "release-notes v1.2.0 is in My Skills, waiting for you to accept it.")
        XCTAssertEqual(IndexLines.installedNote(IndexInstalled(id: "2", name: "careful", kind: .rulePack, version: "2.0.0", digest: "d", proposed: ["p1", "p2", "p3"]), keyTitle: "Touch ID"),
                       "3 rules wait from careful v2.0.0 for your signature with Touch ID on the island.")
    }
}
