import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// A choice tapped on an agent's question goes to the daemon as the pick itself, with no Touch ID.
final class AnsweringQuestionTests: XCTestCase {
    var link: ScriptedLink!
    var key: PersonKey!
    var conversation: Conversation!

    override func setUp() {
        link = ScriptedLink()
        key = PersonKey()
        conversation = Conversation(link: link, speaker: RecordingSpeaker(), key: key, face: RecordingFace(), owner: MemoryOwner(nil))
    }

    func testSendsThePickForItsQuestionUnsigned() async throws {
        link.answers["confirm"] = [try line(#"{"id":1,"ok":true,"outcome":"answered"}"#)]

        let outcome = await conversation.answerQuestion("aqn_1", number: 2, answer: "Mac, Watch")

        XCTAssertEqual(outcome, .answered)
        let sent = try XCTUnwrap(link.sent.last)
        XCTAssertEqual(sent.method, "confirm")
        XCTAssertEqual(sent.subject, "aqn_1")
        XCTAssertEqual(sent.answer, "Mac, Watch")
        XCTAssertEqual(sent.questionNumber, 2)
        XCTAssertNil(sent.signature)
        XCTAssertEqual(key.signed, [])
    }

    func testSaysWhyAPickDidNotGoThrough() async throws {
        link.answers["confirm"] = [try line(#"{"id":1,"ok":false,"error":"aqn_1 is no longer waiting on an answer"}"#)]
        let outcome = await conversation.answerQuestion("aqn_1", number: 1, answer: "Yes")
        XCTAssertEqual(outcome, .failed("aqn_1 is no longer waiting on an answer"))
    }
}
