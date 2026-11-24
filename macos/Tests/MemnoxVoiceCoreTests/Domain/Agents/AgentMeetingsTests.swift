import XCTest
@testable import MemnoxVoiceCore

final class AgentMeetingsTests: XCTestCase {
    private let names = ["claude-code": "Claude Code", "codex": "Codex", "cursor": "Cursor"]

    func testSaysSharedFilesThenHoldsThenWaitsForOneAgentOnly() {
        let view = AgentOverlapsView(
            holds: [AgentHold(agent: "claude-code", path: "src/billing/", until: "t"), AgentHold(agent: "codex", path: "a.ts", until: "t")],
            together: [AgentsTogether(target: "/work/site/prices.json", agents: ["claude-code", "codex", "cursor"], at: "t")],
            heldBack: [AgentHeldBack(agent: "claude-code", what: "/work/site/a.ts", said: "Codex has it", at: "t")])
        XCTAssertEqual(AgentMeetings.lines(view, agent: "claude-code") { self.names[$0] ?? $0 }, [
            "In prices.json with Codex and Cursor right now.",
            "Holds billing, so no other agent changes it.",
            "Waited for a.ts, which another agent had.",
        ])
        XCTAssertEqual(AgentMeetings.lines(AgentOverlapsView(), agent: "claude-code") { $0 }, [])
    }
}
