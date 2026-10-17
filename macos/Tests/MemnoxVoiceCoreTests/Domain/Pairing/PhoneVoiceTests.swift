import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Which phone the island says holds the voice, and when it says nothing.
final class PhoneVoiceTests: XCTestCase {
    func testNamesThePhoneWhileItHoldsTheVoice() {
        let phone = PhoneVoice(VoiceOn(deviceId: "dev_1", name: "Sam's iPhone", holding: true))
        XCTAssertEqual(phone, PhoneVoice(deviceId: "dev_1", name: "Sam's iPhone"))
        XCTAssertEqual(phone?.label, "Talking on Sam's iPhone")
    }

    func testSaysNothingOnceTheVoiceIsBack() {
        XCTAssertNil(PhoneVoice(VoiceOn(deviceId: "dev_1", name: "Sam's iPhone", holding: false)))
    }

    func testSaysYourPhoneWhenThePhoneGaveNoName() {
        XCTAssertEqual(PhoneVoice(deviceId: "dev_1", name: " ").label, "Talking on your phone")
    }
}
