import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// How a session reads on its detail card.
final class SessionDetailTextTests: XCTestCase {
    private func session(_ extra: String) throws -> SessionView {
        let json = #"{"sessionId":"ses_1","agent":"claude-code","agentName":"Claude Code","state":"idle","thinking":false,"waitingOnYou":0,"helpers":[],"steps":[],"files":[]"# + extra + "}"
        return try JSONDecoder().decode(SessionView.self, from: Data(json.utf8))
    }

    func testSaysHowLongAQuietSessionHasRestedAndLeavesTheOtherBadgesAsTheyAre() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-05T01:00:00Z"))
        XCTAssertEqual(SessionDetailText.statusLabel(of: try session(#","lastActive":"2026-10-05T00:50:00Z""#), now: now), "Quiet, 10 min ago")
        XCTAssertEqual(SessionDetailText.statusLabel(of: try session(""), now: now), "Quiet")
        XCTAssertEqual(SessionDetailText.statusLabel(of: try session(#","paused":"too many failures""#), now: now), "Paused")
    }

    func testPlacesASessionByItsRepositoryAndTheAppItRunsIn() throws {
        XCTAssertEqual(SessionDetailText.place(of: try session(#","repository":"memnox-runtime","runningIn":"VS Code""#)), "memnox-runtime \u{00B7} VS Code")
        XCTAssertNil(SessionDetailText.place(of: try session("")))
    }

    func testNamesTheLastFewFoldersAboveAFile() {
        XCTAssertEqual(SessionDetailText.folder(of: "/Users/m/memnox-runtime/packages/cli/src/daemon/voice-ask.ts"), "cli/src/daemon")
        XCTAssertEqual(SessionDetailText.folder(of: "README.md"), "")
    }

    func testMarksEachChangedLineAndTakesOffTheIndentTheyAllShare() {
        let lines = SessionDetailText.diffLines(["+    ASK_INTENT,", "+    DAEMON_EVENT,", "-      folders,", "+  import x"])
        XCTAssertEqual(lines.map(\.added), [true, true, false, true])
        XCTAssertEqual(lines.map(\.text), ["  ASK_INTENT,", "  DAEMON_EVENT,", "    folders,", "import x"])
    }

    func testFindsTheCountsOfTheFileShownEvenWhenOnePathIsFullAndTheOtherRelative() throws {
        let files = try JSONDecoder().decode([CardFile].self, from: Data(#"[{"path":"packages/cli/src/daemon/voice-ask.ts","added":12,"removed":3}]"#.utf8))
        XCTAssertEqual(SessionDetailText.counts(for: "/Users/m/memnox-runtime/packages/cli/src/daemon/voice-ask.ts", in: files)?.added, 12)
        XCTAssertNil(SessionDetailText.counts(for: "other.ts", in: files))
    }
}
