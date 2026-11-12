import XCTest
@testable import MemnoxVoiceCore

/// Agent work as the window reads and steers it: every press is an unsigned word to the daemon, which decides.
final class AgentWorkDeskTests: XCTestCase {
    static func work(_ id: String, status: String = "active", profile: String = "backend") -> String {
        #"{"id":""# + id + #"","profileId":""# + profile + #"","responsiblePerson":"Bo","target":{"source":"linear","externalId":"LIN-1"},"sessions":[],"attempts":1,"status":""# + status + #"","progress":[],"handoffs":[],"createdAt":"2026-11-07T09:00:00Z","updatedAt":"2026-11-07T09:00:00Z"}"#
    }

    func testReadsStartsAndStopsWorkWithNoSignature() async throws {
        let link = ScriptedLink()
        link.answers["agent-work"] = [try line(#"{"id":1,"ok":true,"agentWork":["# + Self.work("agw_1") + "]}")]
        link.answers["work-start"] = [try line(#"{"id":2,"ok":true,"agentWork":["# + Self.work("agw_2") + "," + Self.work("agw_1") + "]}")]
        link.answers["work-stop"] = [try line(#"{"id":3,"ok":true,"agentWork":["# + Self.work("agw_2", status: "stopped") + "]}")]
        let desk = AgentWorkDesk(link: link)
        await desk.refresh()
        XCTAssertEqual(desk.work?.map(\.id), ["agw_1"])
        let started = await desk.start(profile: "backend", target: " LIN-2 ", title: " ", project: "/code/api")
        XCTAssertEqual(started, .done("Started on LIN-2. The agent sees it at its next pause."))
        let start = try XCTUnwrap(link.sent.first { $0.method == "work-start" })
        XCTAssertEqual(start.workTarget, "LIN-2")
        XCTAssertNil(start.workTitle)
        XCTAssertEqual(start.workProject, "/code/api")
        XCTAssertNil(start.signature)
        XCTAssertEqual(desk.work?.count, 2)
        _ = await desk.stop("agw_2")
        XCTAssertEqual(link.sent.last?.workId, "agw_2")
        XCTAssertNil(link.sent.last?.signature)
    }

    func testAnswersAHandoffAndSaysARefusal() async throws {
        let link = ScriptedLink()
        link.answers["handoff-answer"] = [try line(#"{"id":1,"ok":false,"error":"No handoff waits under that id."}"#)]
        let refused = await AgentWorkDesk(link: link).answer("hnd_1", .accept)
        XCTAssertEqual(refused, .failed("No handoff waits under that id."))
        XCTAssertEqual(link.sent.first?.handoffAnswer, "accept")
    }

    func testPutsAChangedPieceOfWorkOnTopWithNoRead() async throws {
        let link = ScriptedLink()
        link.answers["agent-work"] = [try line(#"{"id":1,"ok":true,"agentWork":["# + Self.work("agw_1") + "," + Self.work("agw_2") + "]}")]
        let desk = AgentWorkDesk(link: link)
        await desk.refresh()
        let changed = try XCTUnwrap(try line(#"{"id":2,"ok":true,"agentWork":["# + Self.work("agw_2", status: "done_claimed") + "]}").agentWork?.first)
        desk.heard(changed)
        XCTAssertEqual(desk.work?.map(\.id), ["agw_2", "agw_1"])
        XCTAssertEqual(desk.work?.first?.workStatus, .doneClaimed)
    }
}
