import XCTest

@testable import MemnoxVoiceCore

/// Mirrors the use case half of shared/tauri-core/test/community-index.test.ts.
final class CommunityIndexTests: XCTestCase {
    private static let index = #"{"source":"https://memnox.com/index.json","complete":true,"entries":[{"id":"lst_1","name":"release-notes","kind":"skill","description":"d","publisher":{"kind":"member","name":"Sam"},"agents":[],"yanked":[],"unsafe":false}]}"#

    func testReadsTheRulePacksAlone() async throws {
        let link = ScriptedLink()
        link.answers["index-list"] = [try line(#"{"id":1,"ok":true,"communityIndex":"# + Self.index + "}")]
        let community = CommunityIndex(link: link)
        await community.readPacks()
        XCTAssertEqual(link.sent.last?.indexKind, "rule_pack")
        XCTAssertEqual(community.packs?.count, 1)
        XCTAssertNil(community.busy)
    }

    func testSaysAnInstallAndARuntimeThatRefusedIt() async throws {
        let link = ScriptedLink()
        link.answers["index-install"] = [try line(#"{"id":1,"ok":true,"indexInstalled":{"id":"lst_1","name":"release-notes","kind":"skill","version":"1.2.0","digest":"sha256:abc","proposed":[],"held":true,"said":""}}"#)]
        let community = CommunityIndex(link: link)
        let installed = await community.install("release-notes", version: "1.2.0")
        XCTAssertEqual(installed, .done("release-notes v1.2.0 is in My Skills, waiting for you to accept it."))
        XCTAssertEqual(link.sent.first?.indexName, "release-notes")
        XCTAssertEqual(link.sent.first?.indexVersion, "1.2.0")

        let refusing = ScriptedLink()
        refusing.answers["index-install"] = [try line(#"{"id":1,"ok":false,"error":"Every version of careful-pushes is marked unsafe."}"#)]
        let refused = await CommunityIndex(link: refusing).install("careful-pushes")
        XCTAssertEqual(refused, .failed("Every version of careful-pushes is marked unsafe."))
    }
}
