import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Choosing the display the island lives on.
final class IslandScreenTests: XCTestCase {
    private let monitor = ScreenFacts(id: "MONITOR", hasNotch: false, holdsPointer: false)
    private let laptop = ScreenFacts(id: "LAPTOP", hasNotch: true, holdsPointer: false)
    private let side = ScreenFacts(id: "SIDE", hasNotch: false, holdsPointer: true)

    func testGoesOnTheNotchWhereverItIsListed() {
        XCTAssertEqual(islandScreenIndex(.notch, among: [monitor, laptop]), 1)
    }

    func testGoesOnTheMenuBarScreenWhenNoScreenHasANotch() {
        XCTAssertEqual(islandScreenIndex(.notch, among: [monitor, side]), 0)
    }

    func testFollowsThePointerWhileClosed() {
        XCTAssertEqual(islandScreenIndex(.pointer, among: [monitor, laptop, side]), 2)
    }

    func testStaysWhereItIsWhileOpenEvenWhenThePointerMoves() {
        XCTAssertEqual(islandScreenIndex(.pointer, among: [monitor, laptop, side], stayingOn: "LAPTOP"), 1)
    }

    func testFollowsThePointerWhenTheScreenItWasOnIsGone() {
        XCTAssertEqual(islandScreenIndex(.pointer, among: [monitor, side], stayingOn: "LAPTOP"), 1)
    }

    func testGoesOnTheChosenDisplay() {
        XCTAssertEqual(islandScreenIndex(.display("MONITOR"), among: [laptop, side, monitor]), 2)
    }

    func testFallsBackToTheNotchWhenTheChosenDisplayIsUnplugged() {
        XCTAssertEqual(islandScreenIndex(.display("MONITOR"), among: [side, laptop]), 1)
    }

    func testHasNowhereToGoWithNoScreen() {
        XCTAssertNil(islandScreenIndex(.notch, among: []))
    }

    func testRemembersEachChoice() {
        for choice in [IslandScreen.notch, .pointer, .display("37D8832A-2D66-02CA-B9F7-8F30A301B230")] {
            XCTAssertEqual(IslandScreen(stored: choice.stored), choice)
        }
    }

    func testReadsNothingOrSomethingUnknownAsTheNotch() {
        XCTAssertEqual(IslandScreen(stored: nil), .notch)
        XCTAssertEqual(IslandScreen(stored: "elsewhere"), .notch)
        XCTAssertEqual(IslandScreen(stored: "display:"), .notch)
    }
}
