import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Profiles and the community index as the runtime's daemon/profiles.ts and daemon/community-index.ts write them.
final class ProfilesIndexProtocolTests: XCTestCase {
    func testReadsTheCommunityIndexWithAnUnsafeListing() throws {
        let skill = #"{"id":"lst_1","name":"release-notes","kind":"skill","description":"Drafts notes","category":"Writing","publisher":{"kind":"organization","name":"Acme"},"license":"MIT","agents":["claude-code"],"latest":{"version":"1.2.0","digest":"sha256:abc"},"yanked":["1.1.0"],"unsafe":false,"installed":"1.0.0"}"#
        let pack = #"{"id":"lst_2","name":"careful","kind":"rule_pack","description":"Asks first","publisher":{"kind":"member","name":"Sam"},"agents":[],"yanked":["1.0.0"],"unsafe":true}"#
        let response = try line(#"{"id":1,"ok":true,"communityIndex":{"source":"https://memnox.com/index.json","fetchedAt":"2026-10-30T11:55:00Z","complete":true,"entries":["# + skill + "," + pack + "]}}")
        let index = try XCTUnwrap(response.communityIndex)
        XCTAssertEqual(index.entries.first, IndexEntryView(id: "lst_1", name: "release-notes", kind: .skill, description: "Drafts notes",
                                                           category: "Writing", publisher: IndexPublisher(kind: "organization", name: "Acme"),
                                                           license: "MIT", agents: ["claude-code"], latest: IndexVersion(version: "1.2.0", digest: "sha256:abc"),
                                                           yanked: ["1.1.0"], installed: "1.0.0"))
        XCTAssertEqual(index.entries.last?.indexKind, .rulePack)
        XCTAssertNil(index.entries.last?.latest)
        XCTAssertEqual(index.entries.last?.unsafe, true)
        XCTAssertNil(index.said)
    }

    func testReadsAnInstallAndAProfileApply() throws {
        let installed = try line(#"{"id":2,"ok":true,"indexInstalled":{"id":"lst_2","name":"careful","kind":"rule_pack","version":"2.0.0","digest":"sha256:d","proposed":["p1","p2"],"held":false,"said":"Two rules wait."}}"#)
        XCTAssertEqual(installed.indexInstalled?.proposed, ["p1", "p2"])
        let applied = try line(#"{"id":3,"ok":true,"proposed":"p1","profiles":[{"id":"backend","name":"Backend","skills":["notes"],"mcpServers":["github"],"rulePack":{"name":"Careful","rules":6},"updatedAt":"2026-10-30T10:00:00Z","missing":["figma is no longer in the MCP Hub."]}],"profileApplied":{"profile":"Backend","agent":"claude-code","project":"/code/api","proposed":["p1"],"already":["github"],"skipped":[]}}"#)
        XCTAssertEqual(applied.profiles?.first?.rulePack, ProfilePackSummary(name: "Careful", rules: 6))
        XCTAssertEqual(applied.profiles?.first?.missing.count, 1)
        XCTAssertEqual(applied.profileApplied, ProfileApplied(profile: "Backend", agent: "claude-code", project: "/code/api", proposed: ["p1"], already: ["github"]))
    }

    func testWritesTheNewFieldsOnlyWhenSet() throws {
        var apply = DaemonRequest(id: 4, method: .profileApply)
        apply.profileName = "backend"
        apply.profileAgent = "claude-code"
        let applied = try XCTUnwrap(String(data: JSONEncoder().encode(apply), encoding: .utf8))
        XCTAssertTrue(applied.contains(#""method":"profile-apply""#))
        XCTAssertTrue(applied.contains(#""profileAgent":"claude-code""#))
        XCTAssertFalse(applied.contains("profileProject"))
        var put = DaemonRequest(id: 5, method: .profilePut)
        put.profileDraft = ProfileDraft(name: "Backend", skills: ["notes"], rulePack: ProfileRulePack(name: "Careful", toml: "[[policies]]"))
        let written = try XCTUnwrap(String(data: JSONEncoder().encode(put), encoding: .utf8))
        XCTAssertTrue(written.contains(#""skills":["notes"]"#))
        XCTAssertFalse(written.contains("mcpServers"))
        XCTAssertEqual(DaemonMethod.indexInstall.rawValue, "index-install")
        XCTAssertEqual(DaemonMethod.skillRemove.rawValue, "skill-remove")
    }
}
