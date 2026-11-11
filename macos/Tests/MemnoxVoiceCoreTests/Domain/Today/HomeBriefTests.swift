import XCTest

@testable import MemnoxVoiceCore

/// Home lays Today's items into the contract's blocks, in the contract's order and words.
final class HomeBriefTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        // A fixed zone, so local midnight is the same wherever the tests run.
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()
    private let now = ISO8601DateFormatter().date(from: "2026-11-01T13:14:00Z") ?? Date()

    func testReadsTheBlocksInTheConsolesOrderAndWords() {
        let blocks = HomeBrief.blocks(TodaySources(), now: now, calendar: calendar)
        XCTAssertEqual(blocks.map(\.block.title), ["Needs you", "Working now", "Ready to hand over", "Today"])
        XCTAssertTrue(blocks.allSatisfy { $0.items.isEmpty })
        XCTAssertEqual(HomeBriefBlock.waiting.none, "Nothing needs you. Agents keep working inside their rules.")
    }

    func testPutsEachItemUnderTheBlockThatAnswersIt() throws {
        let activity = try JSONDecoder().decode([ActivityRow].self, from: Data(#"""
            [{"id":"r1","at":"2026-11-01T09:00:00Z","agent":"claude-code","agentName":"Claude Code","session":"s1","kind":"command","operation":"git.push","target":"origin","effect":"allow","rule":"ok","reason":"allowed by rule"}]
            """#.utf8))
        let working = SessionCard(sessionId: "w", agent: "claude-code", agentName: "Claude Code", task: "tests", state: "working",
                                  lastActive: "2026-11-01T08:00:00Z")
        let held = TodayHeld(subject: "h", agent: "codex", who: "Codex", what: "rm -rf build", at: "2026-11-01T12:00:00Z")
        let ready = HomeReady(action: "git push", approvals: 5, targets: [], because: "you said yes five times")
        let sources = TodaySources(held: [held], sessions: [working], activity: activity, owed: ["Sign in"], ready: ready)
        let blocks = HomeBrief.blocks(sources, now: now, calendar: calendar)
        let ids = Dictionary(uniqueKeysWithValues: blocks.map { ($0.block, $0.items.map(\.id)) })
        XCTAssertEqual(ids[.waiting], ["held:h", "owed:Sign in"])
        XCTAssertEqual(ids[.working], ["session:w"])
        XCTAssertEqual(ids[.today], ["row:r1"])
        XCTAssertEqual(ids[.ready]?.count, 1)
        XCTAssertEqual(HomeBrief.items(blocks).first?.id, "held:h")
    }
}
