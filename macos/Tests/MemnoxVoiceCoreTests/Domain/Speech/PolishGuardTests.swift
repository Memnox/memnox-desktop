import XCTest

@testable import MemnoxVoiceCore

/// A polish typed only while it still says what was said, and the Mac's own cleanup typed when it strays.
final class PolishGuardTests: XCTestCase {
    func testKeepsAPolishThatOnlyCleansUpTheSpeech() {
        XCTAssertTrue(polishKeepsWhatWasSaid("So I think we should ship it on Friday.",
                                             said: "um so I think we should ship it on friday"))
        XCTAssertTrue(polishKeepsWhatWasSaid("Can you send it?", said: "you can can you send it"))
        XCTAssertTrue(polishKeepsWhatWasSaid("I don't know yet.", said: "I do not know yet"))
    }

    func testKeepsNumbersListsAndTheirOwnSpellings() {
        XCTAssertTrue(polishKeepsWhatWasSaid("We need 25 servers.", said: "we need twenty five servers"))
        XCTAssertTrue(polishKeepsWhatWasSaid("1. Buy milk\n2. Call mom\n3. Pay rent",
                                             said: "first buy milk second call mom third pay rent"))
        let said = "ask memnocks to check the railway deploy"
        let polished = "Ask Memnox to check the Railway deploy."
        XCTAssertTrue(polishKeepsWhatWasSaid(polished, said: said, vocabulary: ["Memnox", "Railway"]))
        // Spelled too far from anything heard, the name is only familiar because it is one of theirs.
        XCTAssertFalse(polishKeepsWhatWasSaid(polished, said: said))
    }

    func testRefusesAPolishThatAnswersOrAddsToTheSpeech() {
        XCTAssertFalse(polishKeepsWhatWasSaid("The capital of France is Paris.", said: "what is the capital of france"))
        XCTAssertFalse(polishKeepsWhatWasSaid("Ship it now, and tell the team it shipped today.", said: "ship it"))
    }

    func testRefusesANegationPutInOrTakenOut() {
        XCTAssertFalse(polishKeepsWhatWasSaid("Don't send it to the team.", said: "send it to the team"))
        XCTAssertFalse(polishKeepsWhatWasSaid("I think it works.", said: "I don't think it works"))
        XCTAssertFalse(polishKeepsWhatWasSaid("We should merge it.", said: "we should never merge it"))
    }

    func testRefusesAPolishThatSummarizesOrDropsTooMuch() {
        let said = "so the thing is the deploy failed last night because the migration ran twice and "
            + "the second run locked the users table for about ten minutes which is why people saw errors"
        XCTAssertFalse(polishKeepsWhatWasSaid("The deploy failed overnight.", said: said))
        let long = Array(repeating: "we checked the logs and the queue and the cache", count: 6).joined(separator: " ")
        let shortened = long.split(separator: " ").dropLast(11).joined(separator: " ")
        XCTAssertFalse(polishKeepsWhatWasSaid(shortened, said: long))
        let trimmed = long.split(separator: " ").dropLast(8).joined(separator: " ")
        XCTAssertTrue(polishKeepsWhatWasSaid(trimmed, said: long))
    }

    func testNothingSaidHasNothingToKeepAndNothingWrittenKeepsNothing() {
        XCTAssertTrue(polishKeepsWhatWasSaid("", said: "  "))
        XCTAssertFalse(polishKeepsWhatWasSaid("  ", said: "send it"))
    }
}
