import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// The words said as a phone pairs, named the way the phone names itself.
final class PairingLinesTests: XCTestCase {
    func testSaysYourBeforeAPlainName() {
        XCTAssertEqual(PairingLines.paired("iPhone"), "Your iPhone is paired.")
    }

    func testLeavesYourOutWhenTheNameAlreadySaysWhose() {
        XCTAssertEqual(PairingLines.paired("Sam's iPhone"), "Sam's iPhone is paired.")
        XCTAssertEqual(PairingLines.paired("Sam\u{2019}s iPhone"), "Sam\u{2019}s iPhone is paired.")
    }

    func testFallsBackToPhoneWhenThereIsNoName() {
        XCTAssertEqual(PairingLines.paired("  "), "Your phone is paired.")
    }
}
