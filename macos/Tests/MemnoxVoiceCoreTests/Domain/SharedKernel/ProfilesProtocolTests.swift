import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Profiles as the runtime's daemon/profiles.ts writes them.
final class ProfilesProtocolTests: XCTestCase {
    func testReadsAProfileApply() throws {
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
        XCTAssertEqual(DaemonMethod.skillRemove.rawValue, "skill-remove")
    }
}
