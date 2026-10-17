import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// The fields a server adds to the wire, read as protocol.ts and remote.ts write them.
final class RemoteFieldsTests: XCTestCase {
    func testReadsWhetherTheMachineSpeaksOnPing() throws {
        XCTAssertEqual(try line(#"{"id":1,"ok":true,"version":"0.14.0","speaks":false}"#).speaks, false)
        XCTAssertNil(try line(#"{"id":1,"ok":true}"#).speaks)
    }

    func testReadsHowManyTriesAreLeftOnAWrongCode() throws {
        let refused = try line(#"{"id":1,"ok":false,"outcome":"refused","reason":"Those digits do not match.","triesLeft":2}"#)
        XCTAssertEqual(refused.triesLeft, 2)
    }

    func testReadsWhoApprovesAPairingAndHowADeviceWasApproved() throws {
        let pending = try line(#"{"id":1,"ok":true,"pairing":{"id":"pai_1","state":"answered","approver":"local-shell","phone":{"name":"Studio Mac","fingerprint":"fp","code":"482913"}}}"#)
        XCTAssertEqual(pending.pairing?.approver, "local-shell")
        let listed = try line(#"{"id":1,"ok":true,"devices":[{"id":"dev_1","name":"Studio Mac","kind":"desktop","fingerprint":"fp","capabilities":["see"],"pairedAt":"t","approvedBy":"local-shell"}]}"#)
        XCTAssertEqual(listed.devices?.first?.approvedBy, "local-shell")
        XCTAssertEqual(listed.devices?.first?.deviceKind, .desktop)
    }

    func testSendsTheTypedDigitsOnPairAccept() throws {
        var accept = DaemonRequest(id: 3, method: .pairAccept)
        accept.pairingId = "pai_1"
        accept.code = "482913"
        let sent = try XCTUnwrap(String(data: try encodeLine(accept), encoding: .utf8))
        XCTAssertTrue(sent.contains(#""code":"482913""#))
        XCTAssertFalse(try XCTUnwrap(String(data: try encodeLine(DaemonRequest(id: 4, method: .ping)), encoding: .utf8)).contains("code"))
    }
}
