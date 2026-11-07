import XCTest

@testable import MemnoxVoiceCore

final class TomlTokensTests: XCTestCase {
    func testColoursATableHeaderWhole() {
        XCTAssertEqual(TomlTokens.line("[[policies]]"), [TomlToken("[[policies]]", .table)])
        XCTAssertEqual(TomlTokens.line("  [policies.match]"), [TomlToken("  [policies.match]", .table)])
    }

    func testSplitsAKeyFromItsStringsAndSeparators() {
        let tokens = TomlTokens.line("actions = [ \"git.push\", \"a, b\" ]")
        XCTAssertEqual(tokens, [
            TomlToken("actions", .key), TomlToken(" ", .plain), TomlToken("=", .punctuation), TomlToken(" ", .plain),
            TomlToken("[", .punctuation), TomlToken(" ", .plain), TomlToken("\"git.push\"", .string),
            TomlToken(",", .punctuation), TomlToken(" ", .plain), TomlToken("\"a, b\"", .string), TomlToken(" ", .plain),
            TomlToken("]", .punctuation),
        ])
    }

    func testKeepsAnEscapedQuoteInsideItsString() {
        let tokens = TomlTokens.line("reason = \"say \\\"no\\\" # once\"")
        XCTAssertEqual(tokens.last, TomlToken("\"say \\\"no\\\" # once\"", .string))
    }

    func testGivesEveryCharacterBackAndLeavesCommentsAndBlankLinesAlone() {
        let text = "# rules\nversion = 1\n\nname = \"x\" # trailing"
        let lines = TomlTokens.lines(text)
        XCTAssertEqual(lines.map { $0.map(\.text).joined() }.joined(separator: "\n"), text)
        XCTAssertEqual(lines[0], [TomlToken("# rules", .comment)])
        XCTAssertEqual(lines[2], [])
        XCTAssertEqual(lines[3].last, TomlToken("# trailing", .comment))
    }
}
