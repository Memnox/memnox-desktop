import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// The wire format shared with memnox-runtime, read and written exactly.
final class DaemonProtocolTests: XCTestCase {
    func testEncodesOnlyTheFieldsSet() throws {
        var request = DaemonRequest(id: 3, method: .ask)
        request.said = "what is claude doing"
        let text = String(data: try encodeLine(request), encoding: .utf8)
        XCTAssertEqual(text, "{\"id\":3,\"method\":\"ask\",\"said\":\"what is claude doing\"}\n")
    }

    func testDecodesWhatTheRuntimeWrites() throws {
        let event = try line(#"{"id":0,"ok":true,"event":{"kind":"held","subject":"apr_1","agent":"claude-code","summary":"claude-code wants to push","at":"2026-09-30T10:00:00.000Z","expiresAt":"2026-09-30T10:02:00.000Z"}}"#)
        XCTAssertEqual(event.event?.eventKind, .held)
        let chunk = try line(#"{"id":2,"ok":true,"chunk":{"kind":"done"}}"#)
        XCTAssertEqual(chunk.chunk?.endsTurn, true)
        XCTAssertThrowsError(try line("not json"))
    }

    func testReadsWhereASessionRuns() throws {
        let located = try line(#"{"id":7,"ok":true,"location":{"sessionId":"ses_1","agent":"claude-code","alive":true,"app":"iTerm","appPath":"/Applications/iTerm.app","tty":"ttys004","cwd":"/work/shop"}}"#)
        XCTAssertEqual(located.location?.appPath, "/Applications/iTerm.app")
        XCTAssertEqual(located.location?.alive, true)
    }

    func testSignsTheSameMessageTheRuntimeVerifies() {
        XCTAssertEqual(
            confirmationMessage(subject: "prp_1", answer: "confirmed"),
            "memnox-confirm:v1:prp_1:confirmed"
        )
    }

    func testReadsALiveSessionWithItsConversation() throws {
        let response = try line(#"{"id":7,"ok":true,"session":{"sessionId":"ses_1","agent":"claude-code","agentName":"Claude Code","task":"add a cancel button","state":"working","thinking":true,"waitingOnYou":0,"helpers":[],"steps":[{"at":"t","surface":"git","text":"Pushed main","refused":true}],"files":[{"path":"src/Cart.tsx","added":4,"removed":1}],"conversation":[{"at":"t1","who":"person","text":"add a cancel button"},{"at":"t2","who":"tool","text":"Edit: Cart.tsx"}]}}"#)
        let view = try XCTUnwrap(response.session)
        XCTAssertEqual(view.conversation?.map(\.who), ["person", "tool"])
        XCTAssertEqual(view.steps.first?.refused, true)
        XCTAssertTrue(view.thinking)
    }
}
