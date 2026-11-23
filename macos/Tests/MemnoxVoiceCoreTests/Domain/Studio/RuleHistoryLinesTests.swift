import XCTest
@testable import MemnoxVoiceCore

/// Rules' History: what changed, who signed or declined it and when, and whether it holds now.
final class RuleHistoryLinesTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-23T12:00:00Z")! // A literal that always parses.

    func testSaysWhatChangedWhoAnsweredAndWhetherItHolds() {
        let lines = RuleHistoryLines.lines([
            RuleHistoryRow(id: "prp_2", kind: "removed", rules: ["ask-before-push"], answer: "declined",
                           answeredAt: "2026-11-23T10:30:00Z", answeredBy: "Ana", proposedBy: "Ana"),
            RuleHistoryRow(id: "prp_1", kind: "added", rules: ["Never deploy to Railway."], answer: "confirmed",
                           answeredAt: "2026-11-23T07:30:00Z", proposedBy: "agt_memnox-operator"),
        ], now: now)
        XCTAssertEqual(lines.map(\.title), ["Take out ask-before-push", "Never deploy to Railway."])
        XCTAssertEqual(lines.map(\.caption), ["Declined by Ana, 1 h ago", "Signed, 4 h ago"])
        XCTAssertEqual(lines.map(\.outcome), ["Left as it was", "In force"])
        XCTAssertEqual(lines.map(\.inForce), [false, true])
    }

    func testReadsTheRuntimesRows() throws {
        let json = #"{"id":3,"ok":true,"ruleHistory":[{"id":"prp_1","kind":"added","rules":["Never deploy."],"answer":"confirmed","answeredAt":"2026-11-23T07:30:00Z","proposedBy":"Ana"}]}"#
        let response = try JSONDecoder().decode(DaemonResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.ruleHistory?.map(\.id), ["prp_1"])
    }

    func testTellsAHeldCallKeptForLaterFromOneAnAgentIsBlockedOn() throws {
        let kept = #"{"kind":"held","subject":"apr_1","agent":"claude-code","summary":"push","at":"2026-11-23T09:00:00Z","parkedAt":"2026-11-23T10:00:00Z"}"#
        let blocked = #"{"kind":"held","subject":"apr_2","agent":"claude-code","summary":"push","at":"2026-11-23T09:00:00Z"}"#
        XCTAssertEqual(try JSONDecoder().decode(DaemonEvent.self, from: Data(kept.utf8)).parkedAt, "2026-11-23T10:00:00Z")
        XCTAssertNil(try JSONDecoder().decode(DaemonEvent.self, from: Data(blocked.utf8)).parkedAt)
    }
}
