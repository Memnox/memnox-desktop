import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Finding the newest Mac release in GitHub's list, and reading the checksum published beside it.
final class AppReleaseTests: XCTestCase {
    private static let digest = String(repeating: "ab", count: 32)

    static func release(_ tag: String, draft: Bool = false, assets: [String] = [AppRelease.Asset.image, AppRelease.Asset.checksum]) -> String {
        let listed = assets.map { #"{"name":"\#($0)","browser_download_url":"https://github.com/Memnox/memnox-desktop/releases/download/\#(tag)/\#($0)"}"# }
        return #"{"tag_name":"\#(tag)","draft":\#(draft),"assets":[\#(listed.joined(separator: ","))]}"#
    }

    private func newest(_ releases: String...) -> AppRelease? {
        AppRelease.newest(in: Data("[\(releases.joined(separator: ","))]".utf8))
    }

    func testTakesTheHighestVersionWhateverTheOrder() {
        XCTAssertEqual(newest(Self.release("app-v0.1.2"), Self.release("app-v0.1.10"), Self.release("app-v0.1.9"))?.version, "0.1.10")
    }

    func testReadsTheImageAndItsChecksum() {
        let found = newest(Self.release("app-v0.2.0"))
        XCTAssertEqual(found?.image.lastPathComponent, "Memnox.dmg")
        XCTAssertEqual(found?.checksum.lastPathComponent, "Memnox.dmg.sha256")
    }

    func testPassesOverAReleaseTheMacImageWasNeverAddedTo() {
        XCTAssertEqual(newest(Self.release("app-v0.3.0", assets: ["Memnox_0.3.0_x64-setup.exe"]), Self.release("app-v0.2.0"))?.version, "0.2.0")
    }

    func testPassesOverAnImageWithNoChecksum() {
        XCTAssertNil(newest(Self.release("app-v0.3.0", assets: [AppRelease.Asset.image])))
    }

    func testPassesOverADraft() {
        XCTAssertEqual(newest(Self.release("app-v0.3.0", draft: true), Self.release("app-v0.2.0"))?.version, "0.2.0")
    }

    func testPassesOverATagFromAnotherScheme() {
        XCTAssertEqual(newest(Self.release("v9.0.0-preview"), Self.release("app-v0.2.0"))?.version, "0.2.0")
    }

    func testReadsNothingFromAnAnswerThatIsNotAList() {
        XCTAssertNil(AppRelease.newest(in: Data(#"{"message":"Not Found"}"#.utf8)))
    }

    func testIsNewerOnlyThanAnOlderApp() {
        let release = AppRelease(version: "0.1.2", image: URL(fileURLWithPath: "/i"), checksum: URL(fileURLWithPath: "/c"))
        XCTAssertTrue(release.isNewer(than: "0.1.1"))
        XCTAssertFalse(release.isNewer(than: "0.1.2"))
        XCTAssertFalse(release.isNewer(than: "0.2.0"))
    }

    func testReadsTheDigestAsShasumWritesIt() {
        XCTAssertEqual(publishedDigest("\(Self.digest.uppercased())  build/Memnox-0.1.2.dmg\n"), Self.digest)
        XCTAssertEqual(publishedDigest("\(Self.digest)\n"), Self.digest)
    }

    func testRefusesADigestThatIsNotOne() {
        XCTAssertNil(publishedDigest(""))
        XCTAssertNil(publishedDigest("Not Found"))
        XCTAssertNil(publishedDigest(String(repeating: "z", count: 64)))
    }

    func testChecksAnImageAgainstItsPublishedDigest() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("memnox-image-\(UUID().uuidString)")
        try Data("memnox".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        // What `printf memnox | shasum -a 256` prints.
        let digest = "82e33f124462bccae3fbc2b7262f607d851a46965d3920e83e7781957478d93f"
        XCTAssertEqual(try ImageChecksum.sha256(of: file), digest)
        XCTAssertTrue(ImageChecksum.matches(file, published: "\(digest)  Memnox.dmg"))
        XCTAssertFalse(ImageChecksum.matches(file, published: Self.digest))
    }
}
