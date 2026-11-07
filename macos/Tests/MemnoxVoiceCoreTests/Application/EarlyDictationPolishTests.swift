import XCTest

@testable import MemnoxVoiceCore

/// A polish started at a pause and used when the dictation ended there, asked afresh when it went on.
final class EarlyDictationPolishTests: XCTestCase {
    private let link = ScriptedLink()
    private lazy var polish = DictationPolish(link: link, sleep: { _ in
        try await Task.sleep(nanoseconds: 5_000_000_000)
    })

    func testUsesThePolishStartedAtThePauseWhenNothingWasSaidAfterIt() async throws {
        link.answers["polish"] = [try line(#"{"id":1,"ok":true,"polished":"Send the report."}"#)]
        let early = EarlyDictationPolish(polish: polish, family: .general, vocabulary: [], textBefore: "Dear Sam,")
        let spoke = Date()
        early.hear("send the report", at: spoke)
        early.look(at: spoke.addingTimeInterval(0.5))
        let answer = await early.answer(for: "Send the report.")
        XCTAssertEqual(answer, "Send the report.")
        XCTAssertEqual(link.sent.count, 1)
        XCTAssertEqual(link.sent.first?.said, "send the report")
        XCTAssertEqual(link.sent.first?.textBefore, "Dear Sam,")
    }

    func testAsksAfreshWhenTheWordsWentOnAfterThePause() async throws {
        link.answers["polish"] = [try line(#"{"id":1,"ok":true,"polished":"Done."}"#)]
        let early = EarlyDictationPolish(polish: polish, family: .general, vocabulary: [], textBefore: nil)
        let spoke = Date()
        early.hear("send the report", at: spoke)
        early.look(at: spoke.addingTimeInterval(0.5))
        _ = await early.answer(for: "send the report to the team")
        XCTAssertEqual(link.sent.last?.said, "send the report to the team")
    }

    func testStartsNothingBeforeThePause() async throws {
        link.answers["polish"] = [try line(#"{"id":1,"ok":true,"polished":"Done."}"#)]
        let early = EarlyDictationPolish(polish: polish, family: .general, vocabulary: [], textBefore: nil)
        let spoke = Date()
        early.hear("send the report", at: spoke)
        early.look(at: spoke.addingTimeInterval(0.1))
        _ = await early.answer(for: "send the report")
        XCTAssertEqual(link.sent.count, 1)
    }

    func testSendsOnlyTheEndOfTheTextBeforeTheCursor() async throws {
        link.answers["polish"] = [try line(#"{"id":1,"ok":true,"polished":"Hi."}"#)]
        let long = String(repeating: "a", count: 700) + "Memnox"
        _ = await polish.polish("hi", family: .general, vocabulary: [], textBefore: long)
        XCTAssertEqual(link.sent.last?.textBefore?.count, DictationPolish.mostTextBefore)
        XCTAssertEqual(link.sent.last?.textBefore?.hasSuffix("Memnox"), true)
        _ = await polish.polish("hi", family: .general, vocabulary: [], textBefore: "  \n")
        XCTAssertNil(link.sent.last?.textBefore)
    }
}
