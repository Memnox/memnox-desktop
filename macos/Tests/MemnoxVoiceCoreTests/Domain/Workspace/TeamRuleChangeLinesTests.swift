import XCTest
@testable import MemnoxVoiceCore

/// Team rule changes on Needs you: plain words for what each changes and who asked, opened in Memnox Cloud to approve.
final class TeamRuleChangeLinesTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-23T12:00:00Z")! // A literal that always parses.

    func testSaysWhatEachChangesAndWhoAskedInPlainWords() {
        let lines = TeamRuleChangeLines.lines([
            CloudRuleChange(id: "prp_1", proposedBy: "Sam", proposedAt: "2026-11-23T10:00:00Z"),
            CloudRuleChange(id: "prp_2", proposedBy: "", proposedAt: "2026-11-23T11:55:00Z", kind: "shared_projects"),
        ], now: now)
        XCTAssertEqual(lines.map(\.title), ["A change to the team's rules", "A change to the team's projects"])
        XCTAssertEqual(lines.map(\.caption), ["Asked by Sam, 2 h ago", "Asked by a teammate, 5 min ago"])
    }

    func testOpensTheConsolesRuleChangesList() {
        XCTAssertEqual(TeamRuleChangeLines.consoleAddress.absoluteString, "https://app.memnox.com/inbox?queue=rule-changes")
    }

    func testReadsOnlyThePendingChangesWhileSignedIn() async throws {
        let cloud = ScriptedTransport()
        cloud.answer("GET /v1/workspaces/ws_1/agent-profiles", 200, #"{"profiles":[]}"#)
        cloud.answer("GET /v1/workspaces/ws_1/me/agent-work", 200, #"{"work":[],"handoffs":[]}"#)
        cloud.answer("GET /v1/workspaces/ws_1/policies/proposals", 200,
                     #"[{"id":"prp_1","workspaceId":"ws_1","policies":[],"summary":{"added":["no-push"],"removed":[],"modified":[],"unchanged":3},"proposedBy":"Sam","proposedAt":"2026-11-23T10:00:00Z","status":"pending","kind":"rules"}]"#)
        let agents = WorkspaceAgents(reader: HttpWorkspaceInbox(transport: cloud), store: MemoryPersonCredential(signedInCredential()))
        await agents.refresh()
        XCTAssertEqual(agents.remote.first?.ruleChanges.map(\.id), ["prp_1"])
        let asked = try XCTUnwrap(cloud.sent("GET /v1/workspaces/ws_1/policies/proposals").first)
        XCTAssertEqual(asked.query, "status=pending")
    }

    func testAWorkspaceThatWillNotListItsChangesStillShowsItsAgents() async {
        let cloud = ScriptedTransport()
        cloud.answer("GET /v1/workspaces/ws_1/agent-profiles", 200, #"{"profiles":[]}"#)
        cloud.answer("GET /v1/workspaces/ws_1/me/agent-work", 200, #"{"work":[],"handoffs":[]}"#)
        cloud.answer("GET /v1/workspaces/ws_1/policies/proposals", 403, #"{"message":"Forbidden"}"#)
        let agents = WorkspaceAgents(reader: HttpWorkspaceInbox(transport: cloud), store: MemoryPersonCredential(signedInCredential()))
        await agents.refresh()
        XCTAssertEqual(agents.remote.count, 1)
        XCTAssertEqual(agents.remote.first?.ruleChanges, [])
    }
}
