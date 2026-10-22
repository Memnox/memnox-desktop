import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Words typed in the notch into one session: signed over that session and those words, and sent as they are.
final class FollowingUpTests: XCTestCase {
    var link: ScriptedLink!
    var key: PersonKey!
    var following: FollowingUp!

    override func setUp() {
        link = ScriptedLink()
        key = PersonKey()
        following = FollowingUp(link: link, key: key, ids: RequestIds())
    }

    func testSignsTheSessionAndTheWordsAndSendsThemAsTheyAre() async throws {
        link.answers["follow-up"] = [try line(#"{"id":1,"ok":true,"outcome":"typed"}"#)]
        let state = await following.send("  add a dark mode  ", to: "0b5e1c2a-1111-2222-3333-444455556666")
        XCTAssertEqual(state, .sent(.typed))
        XCTAssertEqual(key.signed, [followUpMessage(sessionId: "0b5e1c2a-1111-2222-3333-444455556666", words: "add a dark mode")])
        XCTAssertEqual(link.sent.first?.said, "add a dark mode")
        XCTAssertEqual(link.sent.first?.sessionId, "0b5e1c2a-1111-2222-3333-444455556666")
        XCTAssertNotNil(link.sent.first?.signature)
    }

    func testSendsNothingWhenTouchIDIsClosed() async {
        key.touches = false
        let state = await following.send("add a dark mode", to: "ses_1")
        XCTAssertEqual(state, .cancelled)
        XCTAssertTrue(link.sent.isEmpty)
    }

    func testSaysWhyTheDaemonRefused() async throws {
        link.answers["follow-up"] = [try line(#"{"id":1,"ok":false,"reason":"That session is not on this Mac any more."}"#)]
        let state = await following.send("add a dark mode", to: "ses_1")
        XCTAssertEqual(state, .refused("That session is not on this Mac any more."))
    }

    func testSendsNothingEmpty() async {
        let state = await following.send("   ", to: "ses_1")
        XCTAssertEqual(state, .refused(FollowingUp.noReason))
        XCTAssertTrue(key.signed.isEmpty)
    }
}
