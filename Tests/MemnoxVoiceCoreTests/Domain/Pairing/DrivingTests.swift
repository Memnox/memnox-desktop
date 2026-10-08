import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// A phone driving this Mac: shown for exactly the grant, and a show it asked for is done here in silence.
final class DrivingTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-05T10:00:00Z") ?? .distantPast

    func testReadsAGrantWithOrWithoutMilliseconds() throws {
        let precise = try XCTUnwrap(DriveGrant(DrivenBy(deviceId: "dev_1", name: "iPhone", until: "2026-10-05T10:15:00.000Z"), now: now))
        let plain = try XCTUnwrap(DriveGrant(DrivenBy(deviceId: "dev_1", name: "iPhone", until: "2026-10-05T10:15:00Z"), now: now))
        XCTAssertEqual(precise, plain)
        XCTAssertEqual(precise.until.timeIntervalSince(now), 15 * 60)
    }

    func testNoUntilAnUnreadableOneOrOneAlreadyPastEndsTheDrive() {
        XCTAssertNil(DriveGrant(DrivenBy(deviceId: "dev_1", name: "iPhone"), now: now))
        XCTAssertNil(DriveGrant(DrivenBy(deviceId: "dev_1", name: "iPhone", until: "soon"), now: now))
        XCTAssertNil(DriveGrant(DrivenBy(deviceId: "dev_1", name: "iPhone", until: "2026-10-05T09:59:59Z"), now: now))
    }

    func testIsLiveUntilItsTimeComes() {
        let grant = DriveGrant(deviceId: "dev_1", name: "iPhone", until: now.addingTimeInterval(60))
        XCTAssertTrue(grant.isLive(at: now))
        XCTAssertFalse(grant.isLive(at: now.addingTimeInterval(60)))
    }

    func testNamesThePhoneOrSaysYourPhone() {
        XCTAssertEqual(DriveGrant(deviceId: "dev_1", name: "Sam's iPhone", until: now).label, "Driven from Sam's iPhone")
        XCTAssertEqual(DriveGrant(deviceId: "dev_1", name: " ", until: now).label, "Driven from your phone")
    }

    func testOnlyAShowAPhoneAskedForThatNeedsTheMacIsQuiet() throws {
        let fromPhone = try event(#"{"kind":"show","subject":"dsp_1","agent":"memnox","summary":"s","at":"t","display":"type","needsMac":true,"origin":{"deviceId":"dev_1"}}"#)
        let fromHere = try event(#"{"kind":"show","subject":"dsp_1","agent":"memnox","summary":"s","at":"t","display":"type","needsMac":true}"#)
        XCTAssertTrue(fromPhone.quietOnMac)
        XCTAssertFalse(fromPhone.isSaid(speakUp: true))
        XCTAssertFalse(fromHere.quietOnMac)
        XCTAssertTrue(fromHere.isSaid(speakUp: false))
    }

    func testANoticeOfADriveIsNeverSaid() throws {
        let notice = try event(#"{"kind":"notice","notice":"watched","subject":"drv_1","agent":"memnox","summary":"s","at":"t","drivenBy":{"deviceId":"dev_1","name":"iPhone"}}"#)
        XCTAssertFalse(notice.isSaid(speakUp: true))
    }
}
