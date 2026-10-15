import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// The person's name kept in the app's own defaults.
final class DefaultsOwnerTests: XCTestCase {
    func testRemembersTheNameInTheAppsOwnDefaults() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "memnox-owner-test-\(UUID().uuidString)"))
        let owner = DefaultsOwner(defaults: defaults)
        XCTAssertNil(owner.name)
        owner.name = "Maya"
        XCTAssertEqual(DefaultsOwner(defaults: defaults).name, "Maya")
    }
}
