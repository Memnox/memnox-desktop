import XCTest

@testable import MemnoxVoiceCore

/// Mirrors "what the daemon answers" in shared/tauri-core/test/destinations.test.ts.
final class DaemonSupportTests: XCTestCase {
    func testAsksOncePerMethodAndRemembersARefusalAsNotSupported() async throws {
        let link = ScriptedLink()
        link.answers["mcp-hub"] = [try line(#"{"id":1,"ok":true}"#)]
        link.answers["rules"] = [try line(#"{"id":2,"ok":false,"error":"unknown method rules"}"#)]
        let support = DaemonSupport(link: link)

        XCTAssertNil(support.supports("mcp-hub"))
        // A second look while the first ask may still be under way joins it rather than asking again.
        _ = support.supports("mcp-hub")
        let hub = await support.check("mcp-hub")
        XCTAssertTrue(hub)
        let rules = await support.check("rules")
        XCTAssertFalse(rules)

        XCTAssertEqual(support.supports("mcp-hub"), true)
        XCTAssertEqual(support.supports("rules"), false)
        XCTAssertEqual(link.sent.filter { $0.method == "mcp-hub" }.count, 1)
    }

    func testNoDaemonReadsAsNotSupportedAndForgettingAsksAgain() async {
        let link = ScriptedLink()
        link.unreachable = true
        let support = DaemonSupport(link: link)
        let told = Told()
        support.changed = { told.count() }

        let first = await support.check("activity")
        XCTAssertFalse(first)
        support.forget()
        XCTAssertNil(support.supports("activity"))
        _ = await support.check("activity")
        XCTAssertEqual(link.sent.filter { $0.method == "activity" }.count, 2)
        XCTAssertEqual(told.times, 3)
    }
}

/// Counts the changes the support reports, from whichever thread reports them.
private final class Told: @unchecked Sendable {
    private let lock = NSLock()
    private var counted = 0
    var times: Int { lock.withLock { counted } }
    func count() { lock.withLock { counted += 1 } }
}
