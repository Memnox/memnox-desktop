import XCTest

@testable import MemnoxVoiceCore

final class FirstRunEndTests: XCTestCase {
    func testOffersTalkingOnlyOnceTheMicrophoneIsAllowed() {
        XCTAssertEqual(FirstRunEnd.next(hearing: true), .talk)
        XCTAssertEqual(FirstRunEnd.next(hearing: false), .openHome)
        XCTAssertEqual(FirstRunNext.talk.title, "Try it: press and talk")
        XCTAssertEqual(FirstRunNext.openHome.title, "Open Memnox")
    }

    func testListsWhatIsOptionalShortly() {
        let extras = FirstRunEnd.extras(hearing: false)
        XCTAssertEqual(extras.map(\.title), ["Talk to Memnox", "Keys to try"])
        XCTAssertTrue(extras.allSatisfy { !$0.done })
    }

    func testSaysWhereTheRestOfSetupWaitsOnceMemnoxOpens() {
        XCTAssertTrue(FirstRunEnd.later.contains("iPhone"))
        XCTAssertTrue(FirstRunEnd.later.contains("Memnox Cloud"))
        XCTAssertTrue(FirstRunEnd.later.contains(HomeSteps.cardTitle))
    }

    func testTicksWhatIsAlreadyInPlace() {
        let extras = FirstRunEnd.extras(hearing: true)
        XCTAssertEqual(extras.filter(\.done).map(\.id), [.voice])
        XCTAssertEqual(FirstRunLines.tryPrompt, "Make a folder called memnox-try, then delete it with rm -rf memnox-try.")
    }

    func testAsksThePersonOnlyForTheMicrophoneAndOnlyUntilItIsGranted() {
        XCTAssertNil(FirstRunEnd.permissionHint(hearing: true))
        XCTAssertTrue(FirstRunEnd.permissionHint(hearing: false)?.contains("microphone") == true)
    }

    func testGreetsByNameOnlyWhenOneWasGiven() {
        XCTAssertEqual(FirstRunEnd.title(name: " Sam "), "You're set, Sam.")
        XCTAssertEqual(FirstRunEnd.title(name: ""), "You're set.")
    }

    func testKeepsEveryWordFreeOfDashes() {
        let words = [FirstRunEnd.lead, FirstRunEnd.later, FirstRunEnd.talkHint, FirstRunLines.tryPrompt, FirstRunLines.tryDetail]
            + FirstRunEnd.extras(hearing: false).flatMap { [$0.title, $0.detail] }
        for line in words {
            XCTAssertFalse(line.contains("\u{2014}") || line.contains("\u{2013}") || line.contains(" - "), line)
        }
    }
}
