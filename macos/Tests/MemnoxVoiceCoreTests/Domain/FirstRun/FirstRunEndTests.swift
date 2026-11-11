import XCTest

@testable import MemnoxVoiceCore

final class FirstRunEndTests: XCTestCase {
    func testOffersTalkingOnlyOnceTheMicrophoneIsAllowed() {
        XCTAssertEqual(FirstRunEnd.next(hearing: true), .talk)
        XCTAssertEqual(FirstRunEnd.next(hearing: false), .openHome)
        XCTAssertEqual(FirstRunNext.talk.title, "Try it: press and talk")
        XCTAssertEqual(FirstRunNext.openHome.title, "Open Memnox")
    }

    func testListsWhatIsOptionalShortlyEachLinkedToItsSettingsPage() {
        let extras = FirstRunEnd.extras(hearing: false)
        XCTAssertEqual(extras.map(\.title), ["Talk to Memnox", "Keys to try"])
        XCTAssertEqual(extras.map(\.id.settingsTab), ["voice", "listening"])
        for tab in extras.map(\.id.settingsTab) {
            XCTAssertEqual(Destinations.route(forPage: tab), WindowRoute(.settings, tab: tab))
        }
        XCTAssertTrue(extras.allSatisfy { !$0.done })
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
        let words = [FirstRunEnd.lead, FirstRunEnd.talkHint, FirstRunLines.tryPrompt, FirstRunLines.tryDetail] + FirstRunAudience.allCases.flatMap { [$0.title, $0.detail] }
            + FirstRunAskRoute.allCases.flatMap { [$0.title, $0.detail] } + FirstRunEnd.extras(hearing: false)
            .flatMap { [$0.title, $0.detail] }
        for line in words {
            XCTAssertFalse(line.contains("\u{2014}") || line.contains("\u{2013}") || line.contains(" - "), line)
        }
    }
}
