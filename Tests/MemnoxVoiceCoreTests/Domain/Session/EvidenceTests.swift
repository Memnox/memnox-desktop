import XCTest
@testable import MemnoxVoiceCore

final class EvidenceTests: XCTestCase {
    func testCallsWordsLandedOnlyWhenTheyShowOnceMoreThanBefore() {
        let before = "$ claude\n> fix the tests\nDone."
        XCTAssertTrue(Evidence.landed("push the branch", before: before, after: before + "\n> push the\n branch"))
        // The same words sent earlier are already there, so seeing them again proves nothing.
        XCTAssertFalse(Evidence.landed("fix the tests", before: before, after: before))
        XCTAssertTrue(Evidence.landed("fix the tests", before: before, after: before + "\n> fix the tests"))
        XCTAssertFalse(Evidence.landed("   ", before: "", after: "anything"))
    }

    func testShowsTheLinesTheWordsLandedOn() {
        let after = "one\ntwo\nthree\n> push the voice branch\n"
        XCTAssertEqual(Evidence.excerpt(after, around: "push the voice branch"), "two\nthree\n> push the voice branch")
    }

    func testNeverCallsAHeldCallOrARunningCommandDone() {
        XCTAssertEqual(Evidence.afterConfirm(.confirmed, outcome: "let-through"), "Very well. I have let it through, and it carries on from here.")
        XCTAssertEqual(Evidence.afterConfirm(.confirmed, outcome: "started"), "Very well. It is under way, and I will tell you if anything goes wrong.")
        XCTAssertEqual(Evidence.afterConfirm(.confirmed, outcome: "confirmed"), "Very well. It is done.")
        XCTAssertEqual(Evidence.afterConfirm(.declined, outcome: nil), "Very well. I have left it as it was.")
    }

    func testSpeaksForItselfOnlyWhatTheBrainCouldNotHear() {
        XCTAssertNil(Evidence.unheard(.verified, otherwise: "sorry"))
        XCTAssertNil(Evidence.unheard(.typed, otherwise: "sorry"))
        XCTAssertEqual(Evidence.unheard(.waiting, otherwise: "sorry"), "I kept it for its next prompt rather than take your window.")
        XCTAssertEqual(Evidence.unheard(.failed, otherwise: "sorry"), "sorry")
    }

    func testAProofReadsAsWhatWasCheckedThenWhatWasSeen() {
        XCTAssertEqual(Evidence.card(Proof(checked: "the words in its iTerm tab", seen: "> push it")), "Checked the words in its iTerm tab:\n> push it")
        XCTAssertEqual(Evidence.card(Proof(checked: "its message box emptying")), "Checked its message box emptying.")
    }

    func testOnlyASendWithProofIsVerified() {
        XCTAssertEqual(Typed.landed.verified(nil).outcome, .typed)
        XCTAssertEqual(Typed.landed.verified(Proof(checked: "x")).outcome, .verified)
        XCTAssertEqual(Typed(.failed).verified(Proof(checked: "x")).outcome, .failed)
    }
}
