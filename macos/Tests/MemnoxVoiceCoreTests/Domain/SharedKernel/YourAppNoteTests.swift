import XCTest

@testable import MemnoxVoiceCore

/// A press on an app that already works is no failure, and one that did fail is said cleanly on its own card.
final class YourAppNoteTests: XCTestCase {
    private let gmail = ToolConnection(toolkit: "gmail", connected: true)
    private let slack = ToolConnection(toolkit: "slack", connected: false)
    private let github = ToolConnection(toolkit: "github", connected: true, local: true)

    func testOpensNoSignInForAnAppAlreadyWorkingUnlessAskedForAnotherAccount() {
        let list = [gmail, slack, github]
        XCTAssertFalse(YourAppPress.opensSignIn("gmail", again: false, connections: list))
        XCTAssertFalse(YourAppPress.opensSignIn("GitHub", again: false, connections: list))
        XCTAssertTrue(YourAppPress.opensSignIn("gmail", again: true, connections: list))
        XCTAssertTrue(YourAppPress.opensSignIn("slack", again: false, connections: list))
        XCTAssertTrue(YourAppPress.opensSignIn("notion", again: false, connections: list))
    }

    func testCountsOnlyAWorkingOrLocalAppAsSettled() {
        XCTAssertTrue(YourAppPress.isSettled("gmail", in: [gmail]))
        XCTAssertTrue(YourAppPress.isSettled("github", in: [github]))
        XCTAssertFalse(YourAppPress.isSettled("slack", in: [slack]))
        XCTAssertFalse(YourAppPress.isSettled("gmail", in: []))
    }

    func testHoldsAFailureOnItsAppAndNamesWhatDidNotHappen() {
        let note = YourAppNote.failed(.connect, toolkit: "googlecalendar", said: "The cloud did not answer")
        XCTAssertEqual(note.toolkit, "googlecalendar")
        XCTAssertEqual(note.title, "Could not connect Google Calendar")
        XCTAssertEqual(note.words, "The cloud did not answer.")
        XCTAssertEqual(YourAppNote.failed(.disconnect, toolkit: "slack", said: nil).title, "Could not disconnect Slack")
        XCTAssertNil(YourAppNote.failed(.voice, toolkit: nil, said: "x").toolkit)
    }

    func testCleansTheDaemonsWordsAndFallsBackWhereItSaidNothing() {
        XCTAssertEqual(YourAppNote.sentence("  Notion said no.\n\n Try later  "), "Notion said no. Try later.")
        XCTAssertEqual(YourAppNote.sentence("Is it on?"), "Is it on?")
        XCTAssertNil(YourAppNote.sentence(" \n "))
        XCTAssertEqual(YourAppNote.failed(.connect, toolkit: "gmail", said: "  ").words, "Nothing was connected. Try again in a moment.")
        XCTAssertEqual(YourAppNote.failed(.cloudSignIn, toolkit: nil, said: nil).words, YourApps.signInStopped)
    }

    func testSaysWhatDisconnectingDoesInTheConsolesWords() {
        XCTAssertEqual(YourAppDisconnect.title("Slack"), "Disconnect Slack?")
        XCTAssertEqual(YourAppDisconnect.message("Slack"), "Memnox stops reading from Slack straight away.")
        XCTAssertTrue(YourAppDisconnect.detail("Slack").contains("stays on this Mac"))
    }

    func testWritesNoDashInItsCopy() {
        let notes = [YourAppAct.connect, .disconnect, .voice, .cloudSignIn].map { YourAppNote.failed($0, toolkit: "slack", said: nil) }
        let copy = notes.flatMap { [$0.title, $0.words] } + [
            YourAppPress.anotherAccountButton, YourAppDisconnect.title("Slack"), YourAppDisconnect.message("Slack"),
            YourAppDisconnect.detail("Slack"), YourAppDisconnect.confirm,
        ]
        XCTAssertFalse(copy.contains { $0.contains("\u{2014}") || $0.contains("\u{2013}") || $0.contains(" - ") })
    }
}
