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

    /// What `npm deprecate` leaves on one version's own entry, or a plain entry while the version stands.
    private func entry(_ version: String, deprecated: String? = nil) {
        let reason = deprecated.map { #","deprecated":"\#($0)""# } ?? ""
        npm.answer("GET /memnox/\(version)", 200, #"{"name":"memnox","version":"\#(version)"\#(reason)}"#)
    }

    func testMovesAWithdrawnServiceToTheNewestAtOnce() async {
        publish("0.15.2")
        entry("0.15.1", deprecated: "signature check fault, fixed in 0.15.2")
        entry("0.15.2")
        let moved = await updates.withdrawal(running: "0.15.1")
        XCTAssertEqual(moved, Withdrawal(running: "0.15.1", version: "0.15.2", reason: "signature check fault, fixed in 0.15.2"))
    }

    func testLeavesAServiceThatStandsToTheOfferAlone() async {
        publish("0.15.2")
        entry("0.15.1")
        let moved = await updates.withdrawal(running: "0.15.1")
        XCTAssertNil(moved)
    }

    func testWaitsWhileNothingNewerIsOutOrTheNewestWasWithdrawnToo() async {
        publish("0.15.1")
        entry("0.15.1", deprecated: "fault")
        let nothingNewer = await updates.withdrawal(running: "0.15.1")
        XCTAssertNil(nothingNewer)
        publish("0.15.2")
        entry("0.15.2", deprecated: "fault as well")
        let alsoWithdrawn = await updates.withdrawal(running: "0.15.1")
        XCTAssertNil(alsoWithdrawn)
    }

    func testMovesNothingWhenTheServiceIsAwayOrTheRegistryCannotBeRead() async {
        publish("0.15.2")
        let away = await updates.withdrawal(running: nil)
        XCTAssertNil(away)
        npm.answer("GET /memnox/0.15.1", 500, "{}")
        let down = await updates.withdrawal(running: "0.15.1")
        XCTAssertNil(down)
    }

    func testReadsADeprecationAndTakesAnEmptyOneAsLifted() {
        XCTAssertEqual(RuntimeRelease.deprecation(in: Data(#"{"deprecated":"fault"}"#.utf8)), "fault")
        XCTAssertNil(RuntimeRelease.deprecation(in: Data(#"{"deprecated":""}"#.utf8)))
        XCTAssertNil(RuntimeRelease.deprecation(in: Data(#"{"version":"0.15.1"}"#.utf8)))
    }

    func testPutsOnlyAPlainVersionInTheRegistryAddress() {
        XCTAssertTrue(RuntimeRelease.isPlainVersion("0.15.1"))
        for odd in ["../latest", "0.15", "0.15.1-beta", "0..1", "latest", ""] {
            XCTAssertFalse(RuntimeRelease.isPlainVersion(odd), odd)
        }
    }

    func testKeepsEveryWordFreeOfDashes() {
        let words = [RuntimeUpdateLines.ready("0.16.0"), RuntimeUpdateLines.updating("0.16.0"), RuntimeUpdateLines.help("0.16.0"),
                     RuntimeUpdateLines.later, RuntimeUpdateLines.withdrawn("0.15.1", "0.15.2")]
        for line in words {
            XCTAssertFalse(line.contains("\u{2014}") || line.contains("\u{2013}") || line.contains(" - "), line)
        }
    }
}
