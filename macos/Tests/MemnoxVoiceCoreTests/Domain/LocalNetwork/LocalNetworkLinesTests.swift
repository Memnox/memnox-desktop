import XCTest

@testable import MemnoxVoiceCore

/// Mirrors the wording half of shared/tauri-core/test/local-network.test.ts, with this Mac and Touch ID named.
final class LocalNetworkLinesTests: XCTestCase {
    private let off = LanStatus(on: false, listening: false)
    private let listening = LanStatus(on: true, listening: true, addresses: ["192.168.1.20"], port: 47820, advertised: true,
                                      instance: "mx-7f3a", reachable: [LanPhone(deviceId: "dev_1", name: "Sam’s iPhone")])

    func testSaysOffOnWithNothingListeningAndWhereItListens() {
        XCTAssertEqual(LocalNetworkLines.statusLine(off), "Off. Your phones reach this Mac through the relay.")
        XCTAssertEqual(LocalNetworkLines.statusLine(LanStatus(on: true, listening: false)),
                       "On, but this Mac has no private network address right now, so nothing is listening.")
        XCTAssertEqual(LocalNetworkLines.statusLine(listening),
                       "Listening on 192.168.1.20:47820, announced to phones nearby under a name that says nothing about this Mac.")
        XCTAssertEqual(LocalNetworkLines.statusLine(LanStatus(on: true, listening: true, addresses: ["10.0.0.4", "192.168.1.20"], port: 47820)),
                       "Listening on 10.0.0.4:47820, 192.168.1.20:47820.")
    }

    func testNamesThePhonesOverItAndAsksForTouchIDOnlyToTurnItOn() {
        XCTAssertEqual(LocalNetworkLines.phonesLine(listening), "Sam’s iPhone is connected over it now.")
        let two = LanStatus(on: true, listening: true, reachable: [LanPhone(deviceId: "a", name: "One"), LanPhone(deviceId: "b", name: "Two")])
        XCTAssertEqual(LocalNetworkLines.phonesLine(two), "One and Two are connected over it now.")
        XCTAssertEqual(LocalNetworkLines.phonesLine(LanStatus(on: true, listening: true)), "No phone is connected over it now.")
        XCTAssertEqual(LocalNetworkLines.switchCaption(on: false), "Touch ID to turn on")
        XCTAssertEqual(LocalNetworkLines.switchCaption(on: true), "Turn off to stop it at once")
        XCTAssertTrue(LocalNetworkLines.waitsLine.contains("signature with Touch ID on the island"))
    }
}
