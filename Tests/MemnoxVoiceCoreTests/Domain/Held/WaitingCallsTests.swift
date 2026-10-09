import XCTest

@testable import MemnoxVoiceCore

/// Calls waiting on the person queue rather than replace one another, and the header says how many wait and where.
final class WaitingCallsTests: XCTestCase {
    private var calls = WaitingCalls<String>()

    private func add(_ subject: String, on machine: String, keepShown: Bool = false) {
        calls.add("card \(subject)", subject: subject, machine: machine, keepShown: keepShown)
    }

    func testOneCallNeedsNoHeader() {
        add("a", on: "your Mac")
        XCTAssertEqual(calls.shown, "card a")
        XCTAssertNil(calls.header)
        XCTAssertNil(calls.positionText)
    }

    func testASecondCallJoinsTheQueueAndTheNewestComesUp() {
        add("a", on: "your Mac")
        add("b", on: "build-box")
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls.shown, "card b")
        XCTAssertEqual(calls.positionText, "1 of 2")
    }

    func testTheHeaderCountsByMachineMostFirst() {
        add("a", on: "build-box")
        add("b", on: "your Mac")
        add("c", on: "build-box")
        XCTAssertEqual(calls.header, "3 waiting: 2 on build-box, 1 on your Mac")
    }

    func testMachinesWithAsManyPutTheLatestFirst() {
        add("a", on: "build-box")
        add("b", on: "your Mac")
        XCTAssertEqual(calls.header, "2 waiting: 1 on your Mac, 1 on build-box")
    }

    func testCallsAllOnOneMachineSayItOnce() {
        add("a", on: "build-box")
        add("b", on: "build-box")
        XCTAssertEqual(calls.header, "2 waiting on build-box")
    }

    func testStepWalksOlderAndNewerAndStopsAtTheEnds() {
        add("a", on: "your Mac")
        add("b", on: "your Mac")
        add("c", on: "your Mac")
        XCTAssertFalse(calls.canStepNewer)
        calls.step(1)
        XCTAssertEqual(calls.shown, "card b")
        XCTAssertEqual(calls.positionText, "2 of 3")
        calls.step(5)
        XCTAssertEqual(calls.shown, "card a")
        XCTAssertFalse(calls.canStepOlder)
        calls.step(-1)
        XCTAssertEqual(calls.shown, "card b")
    }

    func testACallArrivingNeverMovesTheCardThePersonSteppedTo() {
        add("a", on: "your Mac")
        add("b", on: "build-box")
        calls.step(1)
        add("c", on: "your Mac")
        XCTAssertEqual(calls.shown, "card a")
        XCTAssertEqual(calls.positionText, "3 of 3")
    }

    func testACallBeingAnsweredStaysOnScreen() {
        add("a", on: "your Mac")
        add("b", on: "build-box", keepShown: true)
        XCTAssertEqual(calls.shown, "card a")
    }

    func testRemovingTheShownCallBringsUpTheNewestLeft() {
        add("a", on: "your Mac")
        add("b", on: "your Mac")
        add("c", on: "your Mac")
        calls.step(1)
        XCTAssertTrue(calls.remove("b"))
        XCTAssertEqual(calls.shown, "card c")
        // Arrivals show again once the call stepped to has gone.
        add("d", on: "your Mac")
        XCTAssertEqual(calls.shown, "card d")
    }

    func testRemovingAQueuedCallLeavesTheShownOneAlone() {
        add("a", on: "your Mac")
        add("b", on: "your Mac")
        XCTAssertTrue(calls.remove("a"))
        XCTAssertEqual(calls.shown, "card b")
        XCTAssertFalse(calls.remove("a"))
        XCTAssertTrue(calls.remove("b"))
        XCTAssertTrue(calls.isEmpty)
        XCTAssertNil(calls.shown)
    }

    func testACallToldAgainKeepsItsPlace() {
        add("a", on: "your Mac")
        add("b", on: "your Mac")
        calls.add("card a again", subject: "a", machine: "your Mac")
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls.shown, "card b")
        XCTAssertEqual(calls.newestFirst.map(\.subject), ["b", "a"])
    }
}
