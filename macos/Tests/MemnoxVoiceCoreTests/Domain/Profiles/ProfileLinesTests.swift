import XCTest

@testable import MemnoxVoiceCore

/// Mirrors the wording half of shared/tauri-core/test/profiles.test.ts, with Touch ID for the key.
final class ProfileLinesTests: XCTestCase {
    func testCountsWhatItBundlesNeverAScore() {
        let backend = ProfileView(id: "backend-engineering", name: "Backend Engineering", skills: ["review-checklist", "release-notes"],
                                  mcpServers: ["postgres"], rulePack: ProfilePackSummary(name: "Careful", rules: 6), updatedAt: "2026-10-30T10:00:00Z")
        XCTAssertEqual(ProfileLines.contents(backend), "2 skills · 1 server · Careful, 6 rules")
        XCTAssertEqual(ProfileLines.contents(ProfileView(id: "a", name: "a", skills: ["a"], updatedAt: "")), "1 skill · 0 servers · No starter rules")
    }

    func testSaysWhatAnApplyRaisedWhatWasAlreadyGivenAndWhatWasSkipped() {
        XCTAssertEqual(ProfileLines.applied(ProfileApplied(profile: "p", agent: "a", proposed: ["p1", "p2"], already: ["postgres"]), keyTitle: "Touch ID"),
                       "2 changes wait for your OK with Touch ID on the island. 1 was already given.")
        XCTAssertEqual(ProfileLines.applied(ProfileApplied(profile: "p", agent: "a", skipped: ["figma is not in the MCP Hub."]), keyTitle: "Touch ID"),
                       "Skipped: figma is not in the MCP Hub.")
        XCTAssertEqual(ProfileLines.applied(ProfileApplied(profile: "p", agent: "a"), keyTitle: "Touch ID"), "The profile holds nothing to give.")
    }
}
