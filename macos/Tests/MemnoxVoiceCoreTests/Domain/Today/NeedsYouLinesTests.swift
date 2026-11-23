import XCTest
@testable import MemnoxVoiceCore

final class NeedsYouLinesTests: XCTestCase {
    func testKeepsOnlyWhatAPersonAnsweredSaidTheWayTheyWouldTellIt() throws {
        let rows = try JSONDecoder().decode([ActivityRow].self, from: Data(#"""
            [{"id":"a","at":"2026-11-01T09:00:00Z","agent":"claude-code","agentName":"Claude Code","session":"s","kind":"command","operation":"git.push","target":"origin","effect":"allow","reason":"r","answeredBy":"Sam","answeredHow":"signed"},
             {"id":"b","at":"2026-11-01T09:01:00Z","agent":"codex","agentName":"Codex","session":"s","kind":"command","operation":"shell.exec","target":"rm -rf build","effect":"deny","reason":"r","answeredBy":"Sam"},
             {"id":"c","at":"2026-11-01T09:02:00Z","agent":"codex","agentName":"Codex","session":"s","kind":"command","operation":"git.status","effect":"allow","reason":"r"}]
            """#.utf8))
        let decided = NeedsYouLines.decided(rows)
        XCTAssertEqual(decided.map(\.id), ["a", "b"])
        XCTAssertEqual(decided.first?.caption, "Claude Code · Sam, signed")
        XCTAssertEqual(decided.map(\.outcome), ["Let go ahead", "Stopped"])
        XCTAssertEqual(NeedsYouView.allCases.map(\.title), ["Waiting for you", "Kept for later", "Decided today"])
    }
}
