import Speech
import XCTest

@testable import MemnoxVoiceCore

/// What the recognizer's own language model is taught: names in the sentences they come in, and how odd names sound.
final class RecognizerVocabularyTests: XCTestCase {
    func testEveryNameKeepsItsWeightHoweverManyOthersThereAre() {
        let few = taughtNamePhrases(names: ["babco"])
        let many = taughtNamePhrases(names: ["babco"] + (1...300).map { "folder \($0)" })
        let alone = { (phrases: [TaughtPhrase]) in phrases.first { $0.phrase == "babco" }?.count }
        XCTAssertNotNil(alone(few))
        XCTAssertEqual(alone(few), alone(many))
    }

    func testAFolderIsExpectedWhereAPlaceIsSaid() {
        let phrases = taughtNamePhrases(names: ["babco"]).map(\.phrase)
        XCTAssertTrue(phrases.contains("within the babco folder"))
        XCTAssertTrue(phrases.contains("start a new session in the babco folder"))
        // A folder is never taught in an agent's sentences, which made "open a new babco session" a likely thing to say.
        XCTAssertFalse(phrases.contains("open a new babco session"))
    }

    func testAnAgentIsTaughtInItsOwnSentencesOnce() {
        let phrases = taughtNamePhrases(names: ["claude code", "Claude Code", " ", ""]).map(\.phrase)
        XCTAssertTrue(phrases.contains("open a new Claude Code session"))
        XCTAssertFalse(phrases.contains("within the claude code folder"))
        XCTAssertEqual(phrases.count, Set(phrases.map { $0.lowercased() }).count)
        XCTAssertFalse(phrases.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    func testAgentsOutweighTheNamesOfFolders() {
        let phrases = taughtNamePhrases(names: ["babco"])
        let agent = phrases.first { $0.phrase == "Codex" }?.count ?? 0
        let folder = phrases.first { $0.phrase == "babco" }?.count ?? 0
        XCTAssertGreaterThan(agent, folder)
    }

    func testEveryPronunciationIsOneTheRecognizerCanRead() throws {
        let known = Set(SFCustomLanguageModelData.supportedPhonemes(locale: Locale(identifier: "en-US")))
        try XCTSkipIf(known.isEmpty, "this Mac reports no phonemes for English")
        for pronunciation in taughtPronunciations {
            XCTAssertTrue(pronunciation.readable(by: known), "\(pronunciation.grapheme): \(pronunciation.phonemes)")
        }
        // The ones the diary said it left out are taught now.
        let taught = Set(taughtPronunciations.filter { $0.readable(by: known) }.map(\.grapheme))
        XCTAssertTrue(taught.isSuperset(of: ["iTerm", "Hermes", "Cursor"]))
    }

    func testASoundTheRecognizerDoesNotKnowIsCaught() {
        XCTAssertFalse(TaughtPronunciation("Hermes", "h 3` m i z").readable(by: ["h", "@r", "m", "i", "z"]))
        XCTAssertTrue(TaughtPronunciation("Hermes", "h @r m i z").readable(by: ["h", "@r", "m", "i", "z"]))
    }
}
