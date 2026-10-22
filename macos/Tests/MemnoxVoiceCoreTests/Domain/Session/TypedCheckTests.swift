import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Words are called typed only when the box shows them, never because it reads empty.
final class TypedCheckTests: XCTestCase {
    func testFindsTheWordsInTheBox() {
        XCTAssertTrue(TypedCheck.holds("Start a React Native Expo app", "start a react native expo app"))
    }

    func testFindsThemThroughWrappingAndSpacing() {
        XCTAssertTrue(TypedCheck.holds("Start a React\nNative  Expo app", "Start a React Native Expo app"))
    }

    func testRefusesAnEmptyBox() {
        XCTAssertFalse(TypedCheck.holds("", "Start a React Native Expo app"))
    }

    func testRefusesABoxHoldingSomethingElse() {
        XCTAssertFalse(TypedCheck.holds("Search files by name", "Start a React Native Expo app"))
    }

    func testFindsTheEndOfALongMessageWhoseStartTheAppTidied() {
        let words = "please set up a new React Native Expo application in this folder with TypeScript and a tab layout"
        let shown = "Please set up a new React Native Expo application in this folder with TypeScript and a tab layout"
        XCTAssertTrue(TypedCheck.holds(String(shown.dropFirst(10)), words))
    }
}
