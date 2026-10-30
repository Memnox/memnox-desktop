import XCTest

@testable import MemnoxVoiceCore

/// Mirrors shared/tauri-core/test/workspaces.test.ts.
final class SeenWorkspacesTests: XCTestCase {
    private func card(_ id: String, repository: String? = nil, agent: String = "claude-code", name: String = "Claude Code",
                      lastActive: String? = nil) -> SessionCard {
        SessionCard(sessionId: id, agent: agent, agentName: name, state: "ended", repository: repository, lastActive: lastActive)
    }

    func testGroupsByRepositoryNamesEachAgentOnceAndPutsTheLatestFirst() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-30T12:00:00Z"))
        let seen = SeenWorkspaces.from([
            card("a", repository: "/code/memnox", lastActive: "2026-10-30T10:00:00Z"),
            card("b", repository: "/code/memnox", agent: "codex-cli", name: "Codex", lastActive: "2026-10-30T11:00:00Z"),
            card("c", repository: "/code/site", lastActive: "2026-10-29T11:00:00Z"),
            card("d", repository: "/code/memnox", lastActive: "2026-10-30T09:00:00Z"),
            card("e"),
        ], now: now)
        XCTAssertEqual(seen.map(\.path), ["/code/memnox", "/code/site"])
        XCTAssertEqual(seen.first?.agents.map(\.name), ["Claude Code", "Codex"])
        XCTAssertEqual(seen.first?.sessions, 3)
        XCTAssertEqual(seen.first?.lastActiveAt, "2026-10-30T11:00:00Z")
        XCTAssertEqual(seen.first?.lastActive, "1 h ago")
    }

    func testLeavesOutASessionWithNoRepository() {
        XCTAssertEqual(SeenWorkspaces.from([card("a"), card("b", repository: "")], now: Date()), [])
    }
}
