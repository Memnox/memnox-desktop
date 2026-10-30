import XCTest

@testable import MemnoxVoiceCore

/// The canonical call is JSON.stringify's own writing, so a quote, a backslash or a control character matches the runtime.
final class HeldConfirmationTests: XCTestCase {
    func testWritesAStringTheWayJSONStringifyDoes() {
        XCTAssertEqual(jsonString("plain"), #""plain""#)
        XCTAssertEqual(jsonString(#"say "hi"\now"#), #""say \"hi\"\\now""#)
        XCTAssertEqual(jsonString("a\nb\tc\u{01}/é"), "\"a\\nb\\tc\\u0001/é\"")
    }

    func testWritesEveryFieldEvenWhenEmpty() {
        let canonical = canonicalAction(operation: "fs.write", target: nil, command: nil, fingerprint: "fp", cwd: nil, agent: "codex-cli")
        XCTAssertTrue(canonical.hasPrefix(#"{"operation":"fs.write","target":"","argumentDigest":""#))
        XCTAssertTrue(canonical.hasSuffix(#"","cwd":"","agent":"codex-cli"}"#))
    }

    func testSaysHowAYesIsSignedBeforeItIsGiven() {
        XCTAssertEqual(HeldSigning.line(touchID: false, actionDigest: "e1b4"), "Inside its own repository, so a yes needs no signature")
        XCTAssertEqual(HeldSigning.line(touchID: true, actionDigest: nil), "A yes is signed with Touch ID")
        XCTAssertEqual(HeldSigning.line(touchID: true, actionDigest: "e1b4"),
                       "A yes is signed with Touch ID over exactly this call, so one changed since is refused")
    }
}
