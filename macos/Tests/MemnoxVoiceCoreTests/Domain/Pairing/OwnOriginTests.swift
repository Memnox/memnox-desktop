import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// A server stamps this Mac's own asks with the device id it paired as, so those are said here and never left for a phone.
final class OwnOriginTests: XCTestCase {
    override func tearDown() {
        OwnDevices.shared.set([])
    }

    func testAnEventForThisMacsOwnAskOnAServerIsNotQuiet() throws {
        let asked = try event(#"{"kind":"held","subject":"apr_1","agent":"claude-code","summary":"push","at":"t","origin":{"deviceId":"dev_mac"}}"#)
        XCTAssertFalse(asked.quietOnMac(own: ["dev_mac"]))
    }

    func testAVoiceThisMacHoldsOnAServerIsNotQuiet() throws {
        let held = try event(#"{"kind":"notice","notice":"question","subject":"ntc_1","agent":"a","summary":"Which?","at":"t","heardOn":{"deviceId":"dev_mac","name":"Studio Mac"},"origin":{"deviceId":"dev_mac"}}"#)
        XCTAssertFalse(held.quietOnMac(own: ["dev_mac"]))
    }

    func testAPhonesEventStaysQuietWhateverThisMacIsCalled() throws {
        let fromPhone = try event(#"{"kind":"held","subject":"apr_1","agent":"a","summary":"push","at":"t","heardOn":{"deviceId":"dev_phone","name":"iPhone"}}"#)
        XCTAssertTrue(fromPhone.quietOnMac(own: ["dev_mac"]))
        XCTAssertTrue(fromPhone.quietOnMac(own: []))
    }

    func testAPhoneHoldingTheVoiceKeepsThisMacsOwnAskQuiet() throws {
        let both = try event(#"{"kind":"held","subject":"apr_1","agent":"a","summary":"push","at":"t","origin":{"deviceId":"dev_mac"},"heardOn":{"deviceId":"dev_phone","name":"iPhone"}}"#)
        XCTAssertTrue(both.quietOnMac(own: ["dev_mac"]))
    }

    func testAnEventWithNoDeviceIsNeverQuiet() throws {
        let here = try event(#"{"kind":"held","subject":"apr_1","agent":"a","summary":"push","at":"t"}"#)
        XCTAssertFalse(here.quietOnMac(own: []))
    }

    func testTheRegisteredIdsDecideWhatTheAnnouncingRulesSee() throws {
        let asked = try event(#"{"kind":"held","subject":"apr_1","agent":"a","summary":"push","at":"t","origin":{"deviceId":"dev_mac"}}"#)
        XCTAssertTrue(asked.quietOnMac)
        XCTAssertFalse(asked.isSaid(speakUp: false))
        OwnDevices.shared.set(["dev_mac"])
        XCTAssertFalse(asked.quietOnMac)
        XCTAssertTrue(asked.isSaid(speakUp: false))
        XCTAssertTrue(asked.awaitsAnswer)
    }
}
