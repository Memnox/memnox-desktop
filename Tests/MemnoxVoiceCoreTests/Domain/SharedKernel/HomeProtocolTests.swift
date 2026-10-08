import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// The home and hand-over as the runtime's daemon/home.ts writes them.
final class HomeProtocolTests: XCTestCase {
    private let withReady = #"{"id":7,"ok":true,"home":{"machine":"studio","mode":"enforce","waiting":2,"working":[{"sessionId":"ses_1","agent":"claude-code","agentName":"Claude Code","task":"fix the invoice total","repository":"shop"},{"sessionId":"ses_2","agent":"codex","agentName":"Codex"}],"today":{"actions":41,"asked":6,"allowed":5,"refused":1},"ready":{"action":"git.push","approvals":14,"agentName":"Claude Code","targets":["feature/*","fix/*"],"because":"Said yes 14 times in 30 days and never refused."},"notCovered":{"unprotected":2,"dormant":1}}}"#

    private let withoutReady = #"{"id":8,"ok":true,"home":{"machine":"studio","mode":"observe","waiting":0,"working":[],"today":{"actions":0,"asked":0,"allowed":0,"refused":0},"notCovered":{"unprotected":0,"dormant":0}}}"#

    func testReadsEveryBlockOfAHomeWithSomethingReady() throws {
        let home = try XCTUnwrap(try line(withReady).home)
        XCTAssertEqual(home.machine, "studio")
        XCTAssertEqual(home.mode, "enforce")
        XCTAssertEqual(home.waiting, 2)
        XCTAssertEqual(home.working.map(\.id), ["ses_1", "ses_2"])
        XCTAssertEqual(home.working.first?.task, "fix the invoice total")
        XCTAssertEqual(home.working.first?.repository, "shop")
        XCTAssertNil(home.working.last?.task)
        XCTAssertNil(home.working.last?.repository)
        XCTAssertEqual(home.today, HomeToday(actions: 41, asked: 6, allowed: 5, refused: 1))
        XCTAssertEqual(home.ready, HomeReady(
            action: "git.push", approvals: 14, agentName: "Claude Code", targets: ["feature/*", "fix/*"],
            because: "Said yes 14 times in 30 days and never refused."
        ))
        XCTAssertEqual(home.notCovered, HomeNotCovered(unprotected: 2, dormant: 1))
    }

    func testReadsAHomeWithNothingReady() throws {
        let home = try XCTUnwrap(try line(withoutReady).home)
        XCTAssertNil(home.ready)
        XCTAssertTrue(home.working.isEmpty)
        XCTAssertEqual(home.notCovered, HomeNotCovered(unprotected: 0, dormant: 0))
    }

    func testReadsAReadyActionAskedOfMoreThanOneAgent() throws {
        let response = try line(#"{"id":9,"ok":true,"home":{"machine":"m","mode":"observe","waiting":0,"working":[],"today":{"actions":1,"asked":1,"allowed":1,"refused":0},"ready":{"action":"npm.install","approvals":5,"targets":[],"because":"b"},"notCovered":{"unprotected":0,"dormant":0}}}"#)
        let ready = try XCTUnwrap(response.home?.ready)
        XCTAssertNil(ready.agentName)
        XCTAssertEqual(ready.targets, [])
    }

    func testReadsTheProposalAHandOverMade() throws {
        let response = try line(#"{"id":10,"ok":true,"proposed":"prp_9"}"#)
        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.proposed, "prp_9")
        XCTAssertNil(response.home)
    }

    func testReadsAHandOverRefusedWithItsReason() throws {
        let response = try line(#"{"id":11,"ok":false,"error":"git.push is not ready to hand over.","reason":"git.push is not ready to hand over."}"#)
        XCTAssertFalse(response.ok)
        XCTAssertNil(response.proposed)
        XCTAssertEqual(response.reason, "git.push is not ready to hand over.")
    }

    func testSendsTheReadyActionOnHandOverAndNothingElse() throws {
        var request = DaemonRequest(id: 12, method: .handOver)
        request.action = "git.push"
        let sent = try XCTUnwrap(String(data: try encodeLine(request), encoding: .utf8))
        XCTAssertEqual(sent, #"{"action":"git.push","id":12,"method":"hand-over"}"# + "\n")
        let home = try XCTUnwrap(String(data: try encodeLine(DaemonRequest(id: 13, method: .home)), encoding: .utf8))
        XCTAssertEqual(home, #"{"id":13,"method":"home"}"# + "\n")
    }

    func testAServerMayBeAskedForItsHomeAndAHandOver() {
        XCTAssertTrue(RemoteReach.allows(DaemonRequest(id: 1, method: .home)))
        XCTAssertTrue(RemoteReach.allows(DaemonRequest(id: 2, method: .handOver)))
    }
}
