import XCTest

@testable import MemnoxVoiceCore

/// Dictation sent to be polished, and the Mac's own cleanup kept whenever no polish comes back.
final class DictationPolishTests: XCTestCase {
    private let link = ScriptedLink()
    private lazy var polish = DictationPolish(link: link, sleep: { _ in
        try await Task.sleep(nanoseconds: 5_000_000_000)
    })

    func testSendsWhatWasSaidWithWhereItLandsAndAnswersThePolishedText() async throws {
        link.answers["polish"] = [try line(#"{"id":1,"ok":true,"polished":"  Can you send it?\n"}"#)]
        let text = await polish.polish("you can can you send it", family: .workChat, vocabulary: ["Memnox"])
        XCTAssertEqual(text, "Can you send it?")
        let sent = try XCTUnwrap(link.sent.last)
        XCTAssertEqual(sent.method, "polish")
        XCTAssertEqual(sent.family, "work_chat")
        XCTAssertEqual(sent.vocabulary, ["Memnox"])
        XCTAssertNil(sent.selection)
    }

    func testAnswersNothingWhenTheDaemonSaysNoOrCannotBeReached() async throws {
        link.answers["polish"] = [try line(#"{"id":1,"ok":false,"error":"not signed in"}"#)]
        let refused = await polish.polish("hi", family: .general, vocabulary: [])
        XCTAssertNil(refused)
        link.unreachable = true
        let gone = await polish.polish("hi", family: .general, vocabulary: [], selection: "old text")
        XCTAssertNil(gone)
        XCTAssertEqual(link.sent.last?.selection, "old text")
    }
}
