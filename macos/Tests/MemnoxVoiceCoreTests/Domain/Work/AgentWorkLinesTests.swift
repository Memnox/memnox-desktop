import XCTest
@testable import MemnoxVoiceCore

/// What a screen says about agent work and about a profile, with no number on a job nobody is behind.
final class AgentWorkLinesTests: XCTestCase {
    private func work(_ status: String, profile: String = "backend", url: String? = nil, title: String? = nil) -> AgentWork {
        AgentWork(id: "agw_\(status)", profileId: profile, responsiblePerson: "Bo",
                  target: ExternalTaskRef(source: "linear", externalId: "LIN-1", url: url, title: title), status: status,
                  createdAt: "", updatedAt: "")
    }

    func testNamesTheIssueAndOpensOnlyAWebLink() {
        XCTAssertEqual(AgentWorkLines.issue(work("active", title: "Fix login")), "LIN-1 \u{00B7} Fix login")
        XCTAssertEqual(AgentWorkLines.link(work("active", url: "https://linear.app/a/issue/LIN-1"))?.host, "linear.app")
        XCTAssertNil(AgentWorkLines.link(work("active", url: "file:///etc/passwd")))
        XCTAssertEqual(AgentWorkLines.latest(work("active")), "No word from the agent yet.")
    }

    func testKeepsFinishedWorkOutOfAnAgentsCurrentWork() {
        let all = [work("done"), work("done_claimed"), work("active", profile: "docs")]
        XCTAssertEqual(AgentWorkLines.current(for: "backend", in: all)?.status, "done_claimed")
        XCTAssertTrue(AgentWorkLines.needsYou(all[1]))
        XCTAssertNil(AgentWorkLines.current(for: "review", in: all))
        XCTAssertEqual(AgentWorkLines.targetProblem("  "), "Paste the issue key, such as LIN-123, or its link.")
    }

    func testOrdersJobsBeforeDefaultsBeforeJobsWithNobodyBehindThem() {
        let connection = AgentConnection(id: "con_c", profileId: "p", kind: "runtime_hook", agentKind: "claude-code", mediation: "interposed",
                                         firstSeen: "", lastSeen: "", status: "live")
        let job = ProfileView(id: "backend", name: "Backend", updatedAt: "", purpose: "Builds the API", connections: [connection])
        let fallback = ProfileView(id: "default:codex-cli", name: "Codex", updatedAt: "", isDefault: true, connections: [connection])
        let template = ProfileView(id: "review", name: "Review", updatedAt: "")
        XCTAssertEqual(AgentProfileLines.ordered([template, fallback, job]).map(\.id), ["backend", "default:codex-cli", "review"])
        XCTAssertEqual(AgentProfileLines.purpose(fallback), "No job yet.")
        XCTAssertEqual(AgentProfileLines.purpose(job), "Builds the API")
        XCTAssertFalse(template.hasAgent)
    }
}
