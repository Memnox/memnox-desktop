import XCTest

@testable import MemnoxVoiceCore

/// A message is called sent on the first thing that shows the app took it, and never while the box still holds it unchanged.
final class SendCheckTests: XCTestCase {
    private let words = "Start a React Native Expo app"
    private let long = "please set up a new React Native Expo application in this folder with TypeScript and a tab layout"

    func testSentWhenTheBoxEmpties() {
        XCTAssertEqual(SendCheck.sign(sent: words, boxNow: " \n", textBefore: [], textNow: [], windowChanged: false), .boxEmptied)
    }

    func testNotSentWhileTheBoxStillHoldsTheWords() {
        XCTAssertNil(SendCheck.sign(sent: words, boxNow: words, textBefore: [words], textNow: [words], windowChanged: false))
    }

    func testNotSentWhenTheBoxCannotBeReadAndNothingElseShows() {
        XCTAssertNil(SendCheck.sign(sent: words, boxNow: nil, textBefore: [], textNow: [], windowChanged: false))
    }

    func testSentWhenTheWordsShowAsANewLineInTheWindow() {
        let sign = SendCheck.sign(sent: words, boxNow: words, textBefore: ["Earlier reply"], textNow: ["Earlier reply", words], windowChanged: false)
        XCTAssertEqual(sign, .shownInWindow)
    }

    func testNotSentByALineThatWasThereBefore() {
        XCTAssertNil(SendCheck.sign(sent: words, boxNow: words, textBefore: [words], textNow: [words], windowChanged: false))
    }

    func testAShortMessageCountsOnlyAsAWholeLine() {
        XCTAssertNil(SendCheck.sign(sent: "yes", boxNow: "yes", textBefore: [], textNow: ["yes, I can do that"], windowChanged: false))
        XCTAssertEqual(SendCheck.sign(sent: "yes", boxNow: "yes", textBefore: [], textNow: ["Yes"], windowChanged: false), .shownInWindow)
    }

    func testALongMessageCountsByItsStart() {
        let shown = "Please set up a new React Native Expo application in this folder with TypeScript"
        XCTAssertEqual(SendCheck.sign(sent: long, boxNow: nil, textBefore: [], textNow: [shown], windowChanged: false), .shownInWindow)
    }

    func testSentWhenTheBoxLetsTheWordsGo() {
        XCTAssertEqual(SendCheck.sign(sent: words, boxNow: "Ask anything", textBefore: [], textNow: [], windowChanged: false), .boxMovedOn)
    }

    func testSentWhenTheWindowChanged() {
        XCTAssertEqual(SendCheck.sign(sent: words, boxNow: words, textBefore: [], textNow: [], windowChanged: true), .windowChanged)
    }
}
