import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// How sessions, steps and timings read on screen.
final class SessionTextTests: XCTestCase {
    private func step(_ surface: String, _ text: String) throws -> SessionViewStep {
        try JSONDecoder().decode(SessionViewStep.self, from: Data(#"{"at":"2026-10-01T00:00:00Z","surface":"\#(surface)","text":"\#(text)"}"#.utf8))
    }

    func testSaysHowLongAgoTheWayAPersonDoes() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-03T12:00:00Z"))
        XCTAssertEqual(SessionText.ago("2026-10-03T11:59:30Z", now: now), "just now")
        // Another machine's clock a little ahead is still just now, never a negative minute.
        XCTAssertEqual(SessionText.ago("2026-10-03T12:00:10Z", now: now), "just now")
        XCTAssertEqual(SessionText.ago("2026-10-03T11:59:00Z", now: now), "1 min ago")
        XCTAssertEqual(SessionText.ago("2026-10-03T11:15:00.250Z", now: now), "44 min ago")
        XCTAssertEqual(SessionText.ago("2026-10-03T09:00:00Z", now: now), "3 h ago")
        XCTAssertEqual(SessionText.ago("2026-10-01T12:00:00Z", now: now), "2 d ago")
        XCTAssertNil(SessionText.ago("yesterday", now: now))
        XCTAssertNil(SessionText.ago(nil, now: now))
    }

    func testNamesAHostItReachedBySiteAndAFileByItsLastPart() throws {
        XCTAssertEqual(SessionText.line(for: try step("network", "GET https://api.github.com/repos")), "Reached github.com")
        XCTAssertEqual(SessionText.line(for: try step("filesystem", "Edited /work/shop/src/cart.ts")), "Edited cart.ts")
    }

    func testLeavesOutTheHostsItCalledAndRepeatsUnlessThatIsAllItDid() throws {
        let edit = try step("filesystem", "Edited /work/cart.ts")
        let steps = [edit, try step("network", "GET https://a.example.com"), edit, try step("shell", "Ran npm test")]
        XCTAssertEqual(SessionText.meaningful(steps).map(SessionText.line(for:)), ["Edited cart.ts", "Ran npm test"])
        let onlyCalls = [try step("network", "GET https://example.com")]
        XCTAssertEqual(SessionText.meaningful(onlyCalls).count, 1)
    }

    func testNamesATraceStepAndItsDurationTheWayAWaterfallIsRead() {
        XCTAssertEqual(SessionText.traceStepName("voice.turn"), "Your question")
        XCTAssertEqual(SessionText.traceStepName("brain.sessions"), "Asked sessions")
        XCTAssertEqual(SessionText.traceStepName("operator.show"), "Ran show")
        XCTAssertEqual(SessionText.traceStepName("custom"), "custom")
        XCTAssertEqual(SessionText.duration(milliseconds: 420), "420 ms")
        XCTAssertEqual(SessionText.duration(milliseconds: 1_260), "1.3 s")
        XCTAssertEqual(SessionText.shortPath("/work/shop/src/cart.ts"), "src/cart.ts")
    }

    func testSubtitlesASessionWithWhatTheTitleDidNotSay() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-03T12:00:00Z"))
        let quiet = SessionCard(sessionId: "ses_1", agentName: "Codex", task: "fix the test", state: "idle",
                                repository: "api", lastActive: "2026-10-03T11:50:00Z")
        XCTAssertEqual(quiet.title, "fix the test")
        XCTAssertEqual(quiet.subtitle(now: now), "Codex \u{00B7} api \u{00B7} 10 min ago")
        let busy = SessionCard(sessionId: "ses_2", agentName: "Codex", state: "working", repository: "api")
        XCTAssertEqual(busy.subtitle(now: now), "Codex \u{00B7} working")
    }
}
