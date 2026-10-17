import XCTest

@testable import MemnoxVoiceCore

/// Session text made fit to read: terminal glyphs, diffs and markdown replies.
final class SessionReadingTests: XCTestCase {
    /// The live window of 2026-10-17 showed a pasted prompt as boxes with question marks between its words.
    func testDropsTerminalIconGlyphsAndJoinsTheWords() {
        let pasted = "memnox setup\n01:10:43 \u{F017} INT \u{2718} \u{F252} took 9s \u{E0B0}  system"
        XCTAssertEqual(SessionReading.readable(pasted), "memnox setup 01:10:43 INT \u{2718} took 9s system")
        XCTAssertNil(SessionReading.readable(" \u{E0B0} \n"))
        XCTAssertNil(SessionReading.readable(nil))
    }

    func testHidesARepositoryNamedOnlyByDots() {
        XCTAssertNil(SessionReading.repository(".."))
        XCTAssertNil(SessionReading.repository("."))
        XCTAssertEqual(SessionReading.repository("memnox-runtime"), "memnox-runtime")
    }

    func testNumbersEachDiffLineOnItsOwnSide() {
        let lines = DiffLine.of([
            "@@ -3,3 +3,4 @@ export function total()",
            " const a = 1;",
            "-const tva = 0.2;",
            "+const tva = 0.196;",
            "+const fee = 0;",
            "\\ No newline at end of file",
        ])
        XCTAssertEqual(lines, [
            DiffLine(kind: .hunk, text: "export function total()"),
            DiffLine(kind: .context, text: "const a = 1;", old: 3, new: 3),
            DiffLine(kind: .removed, text: "const tva = 0.2;", old: 4),
            DiffLine(kind: .added, text: "const tva = 0.196;", new: 4),
            DiffLine(kind: .added, text: "const fee = 0;", new: 5),
        ])
    }

    func testCutsAReplyIntoHeadingsListsAndCode() {
        let reply = "I fixed it.\nAll three.\n\n## The fixes\n\n**1. Paths.** Found.\n- It uses the root\n2. Then tests\n```\nlet a = 1\n```"
        XCTAssertEqual(ReplyBlock.of(reply), [
            .paragraph("I fixed it. All three."),
            .heading("The fixes"),
            .paragraph("**1. Paths.** Found."),
            .bullet("It uses the root"),
            .numbered(2, "Then tests"),
            .code("let a = 1"),
        ])
    }
}

/// A session's title and place on the notch read clean too.
final class SessionTitleReadingTests: XCTestCase {
    func testTitlesASessionWithoutTerminalGlyphsOrADotFolder() throws {
        let json = #"{"sessionId":"s","agent":"claude-code","agentName":"Claude Code","task":"memnox setup  INT","state":"idle","thinking":false,"repository":".."}"#
        let card = try JSONDecoder().decode(SessionCard.self, from: Data(json.utf8))
        XCTAssertEqual(card.title, "memnox setup INT")
        XCTAssertFalse(card.subtitle(now: Date()).contains(".."))
    }
}
