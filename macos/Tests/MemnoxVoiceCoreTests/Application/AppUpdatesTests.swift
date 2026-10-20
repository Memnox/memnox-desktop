import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Whether the notch offers an update, read from GitHub's releases as the app reads them.
final class AppUpdatesTests: XCTestCase {
    private static let route = "GET /repos/Memnox/memnox-desktop/releases"
    private let github = ScriptedTransport()

    private var updates: AppUpdates { AppUpdates(feed: GitHubReleases(transport: github)) }

    private func publish(_ tags: String...) {
        github.answer(Self.route, 200, "[\(tags.map { AppReleaseTests.release($0) }.joined(separator: ","))]")
    }

    func testOffersANewerRelease() async {
        publish("app-v0.1.2", "app-v0.1.1")
        let offered = await updates.offer(running: "0.1.1", skipped: nil)
        XCTAssertEqual(offered?.version, "0.1.2")
    }

    func testOffersNothingToAnAppAlreadyOnTheNewest() async {
        publish("app-v0.1.1")
        let offered = await updates.offer(running: "0.1.1", skipped: nil)
        XCTAssertNil(offered)
    }

    func testOffersNothingTheyPutOff() async {
        publish("app-v0.1.2")
        let offered = await updates.offer(running: "0.1.1", skipped: "0.1.2")
        XCTAssertNil(offered)
    }

    func testOffersAReleaseNewerThanTheOneTheyPutOff() async {
        publish("app-v0.1.3", "app-v0.1.2")
        let offered = await updates.offer(running: "0.1.1", skipped: "0.1.2")
        XCTAssertEqual(offered?.version, "0.1.3")
    }

    func testOffersNothingWhenGitHubCannotBeRead() async {
        github.answer(Self.route, 404, #"{"message":"Not Found"}"#)
        let missing = await updates.offer(running: "0.1.1", skipped: nil)
        XCTAssertNil(missing)
        github.offline = true
        let offline = await updates.offer(running: "0.1.1", skipped: nil)
        XCTAssertNil(offline)
    }

    func testAsksWithoutSigningIn() async {
        publish("app-v0.1.2")
        _ = await updates.offer(running: "0.1.1", skipped: nil)
        XCTAssertEqual(github.sent(Self.route).count, 1)
        XCTAssertNil(github.sent(Self.route).first?.authorization)
    }
}
