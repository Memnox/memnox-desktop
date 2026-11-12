import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Whether the notch offers a newer Memnox service, read from npm as the first run's install reads it.
final class RuntimeUpdatesTests: XCTestCase {
    private static let route = "GET /memnox/latest"
    private let npm = ScriptedTransport()

    private var updates: RuntimeUpdates { RuntimeUpdates(feed: NpmRegistry(transport: npm)) }

    private func publish(_ version: String) {
        npm.answer(Self.route, 200, #"{"name":"memnox","version":"\#(version)"}"#)
    }

    func testOffersANewerService() async {
        publish("0.16.0")
        let offered = await updates.offer(running: "0.15.0", skipped: nil)
        XCTAssertEqual(offered, "0.16.0")
    }

    func testOffersNothingToAServiceAlreadyOnTheNewestOrOneThatDidNotAnswer() async {
        publish("0.16.0")
        let current = await updates.offer(running: "0.16.0", skipped: nil)
        XCTAssertNil(current)
        let away = await updates.offer(running: nil, skipped: nil)
        XCTAssertNil(away)
    }

    func testOffersNothingTheyPutOffAndAVersionAfterItAgain() async {
        publish("0.16.0")
        let putOff = await updates.offer(running: "0.15.0", skipped: "0.16.0")
        XCTAssertNil(putOff)
        publish("0.16.1")
        let next = await updates.offer(running: "0.15.0", skipped: "0.16.0")
        XCTAssertEqual(next, "0.16.1")
    }

    func testOffersNothingWhenTheRegistryCannotBeReadOrNamesNoVersion() async {
        npm.answer(Self.route, 500, "{}")
        let down = await updates.offer(running: "0.15.0", skipped: nil)
        XCTAssertNil(down)
        npm.answer(Self.route, 200, #"{"version":"latest"}"#)
        let odd = await updates.offer(running: "0.15.0", skipped: nil)
        XCTAssertNil(odd)
        XCTAssertNil(RuntimeRelease.newest(in: Data("<html>".utf8)))
    }

    func testKeepsEveryWordFreeOfDashes() {
        let words = [RuntimeUpdateLines.ready("0.16.0"), RuntimeUpdateLines.updating("0.16.0"), RuntimeUpdateLines.help("0.16.0"),
                     RuntimeUpdateLines.later]
        for line in words {
            XCTAssertFalse(line.contains("\u{2014}") || line.contains("\u{2013}") || line.contains(" - "), line)
        }
    }
}
