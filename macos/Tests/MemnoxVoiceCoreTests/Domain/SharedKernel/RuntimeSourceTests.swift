import XCTest

@testable import MemnoxVoiceCore

final class RuntimeSourceTests: XCTestCase {
    func testALocalBuildRunsTheCheckoutItWasBuiltBeside() {
        let info: [String: Any] = ["MemnoxRuntimeSource": "local", "MemnoxRuntimeCheckout": "/Users/me/memnox-runtime"]
        XCTAssertEqual(RuntimeSource.ofThisApp(info), .local("/Users/me/memnox-runtime"))
    }

    /// A release carries no keys, and a local build missing its checkout must never guess one.
    func testAnythingElseInstallsThePublishedPackage() {
        XCTAssertEqual(RuntimeSource.ofThisApp([:]), .npm)
        XCTAssertEqual(RuntimeSource.ofThisApp(["MemnoxRuntimeSource": "npm"]), .npm)
        XCTAssertEqual(RuntimeSource.ofThisApp(["MemnoxRuntimeSource": "local"]), .npm)
    }
}
