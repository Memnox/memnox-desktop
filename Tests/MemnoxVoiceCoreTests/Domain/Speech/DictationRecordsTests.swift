import XCTest

@testable import MemnoxVoiceCore

/// Where dictation lands, the person's own words, and fitting it to the cursor.
final class DictationRecordsTests: XCTestCase {
    func testKnowsTheKindOfPlaceFromTheAppAndForABrowserFromThePage() {
        XCTAssertEqual(DictationFamily(bundleID: "com.apple.mail"), .email)
        XCTAssertEqual(DictationFamily(bundleID: "com.tinyspeck.slackmacgap"), .workChat)
        XCTAssertEqual(DictationFamily(bundleID: "com.microsoft.VSCode"), .prompt)
        XCTAssertEqual(DictationFamily(bundleID: "com.jetbrains.intellij"), .prompt)
        XCTAssertEqual(DictationFamily(bundleID: "com.google.Chrome", windowTitle: "Inbox (3) - Gmail"), .email)
        XCTAssertEqual(DictationFamily(bundleID: "com.apple.Safari", windowTitle: "ORB-1 Rate limits - Linear"), .project)
        XCTAssertEqual(DictationFamily(bundleID: "com.apple.Safari", windowTitle: "Recipes"), .general)
        XCTAssertEqual(DictationFamily(bundleID: nil), .general)
        XCTAssertEqual(DictationFamily.prompt.style, .bare)
    }

    func testWritesShortcutsAndReplacementsTheirWay() {
        let words = [DictationWord(said: "my email", written: "moise@memnox.com")]
        XCTAssertEqual(replaced("send it to my email please", by: words), "send it to moise@memnox.com please")
        // Only the phrase whole, never inside another word.
        XCTAssertEqual(replaced("my emails", by: words), "my emails")
        XCTAssertEqual(
            cleanedDictation("um reply to my email", replacements: words, style: .bare),
            "Reply to moise@memnox.com"
        )
    }

    func testFitsDictationToTheTextAroundTheCursor() {
        XCTAssertEqual(fitted("And then we ship.", after: "We test it", before: nil), " and then we ship.")
        XCTAssertEqual(fitted("Then.", after: "Done. ", before: nil), "Then.")
        XCTAssertEqual(fitted("The tests.", after: "Run ", before: "before lunch"), "the tests ")
        XCTAssertEqual(fitted("GitHub is down.", after: "and ", before: nil), "GitHub is down.")
        XCTAssertEqual(fitted("I agree.", after: "and", before: nil), " I agree.")
        XCTAssertEqual(fitted("Hello.", after: nil, before: nil), "Hello.")
    }

    func testKeepsOneEntryPerPhraseAndLearnsWhatThePersonFixed() {
        var dictionary = DictationDictionary()
        dictionary.add(DictationWord(written: "WakoAI"))
        dictionary.add(DictationWord(written: "wakoai"))
        XCTAssertEqual(dictionary.spellings, ["wakoai"])
        dictionary.learn([WordCorrection(heard: "surgeons", meant: "sessions")])
        dictionary.learn([WordCorrection(heard: "surgeons", meant: "sessions")])
        XCTAssertEqual(dictionary.replacements.map(\.written), ["sessions"])
        dictionary.add(DictationWord(said: " ", written: "  "))
        XCTAssertEqual(dictionary.words.count, 2)
    }

    func testKeepsTheLatestDictationsNewestFirst() {
        var history = DictationHistory()
        for index in 0..<(DictationHistory.kept + 5) {
            history.add(DictationEntry(at: Date(timeIntervalSince1970: TimeInterval(index)), heard: "\(index)", written: "\(index)", app: nil))
        }
        XCTAssertEqual(history.entries.count, DictationHistory.kept)
        XCTAssertEqual(history.last?.heard, "\(DictationHistory.kept + 4)")
    }
}
