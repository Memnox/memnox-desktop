import XCTest

@testable import MemnoxVoiceCore

/// Mirrors the use case half of shared/tauri-core/test/community-index.test.ts.
final class CommunityIndexTests: XCTestCase {
    private static let index = #"{"source":"https://memnox.com/index.json","complete":true,"entries":[{"id":"lst_1","name":"release-notes","kind":"skill","description":"d","publisher":{"kind":"member","name":"Sam"},"agents":[],"yanked":[],"unsafe":false}]}"#

    func testAsksWithTheWordsAndKindAndKeepsWhatCameBack() async throws {
        let link = ScriptedLink()
        link.answers["index-list"] = [try line(#"{"id":1,"ok":true,"communityIndex":"# + Self.index + "}")]
        let community = CommunityIndex(link: link)
        await community.refresh(IndexFilter(query: " notes ", kind: .skill), fresh: true)
        XCTAssertEqual(link.sent.first?.indexQuery, "notes")
        XCTAssertEqual(link.sent.first?.indexKind, "skill")
        XCTAssertEqual(link.sent.first?.indexRefresh, true)
        XCTAssertEqual(community.index?.entries.count, 1)
        XCTAssertEqual(community.filter.kind, .skill)
        XCTAssertNil(community.busy)
        await community.readPacks()
        XCTAssertEqual(link.sent.last?.indexKind, "rule_pack")
        XCTAssertEqual(community.packs?.count, 1)
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

    func testProposesAnotherIndexAndResetsToTheMarketplaceAtOnce() async throws {
        let link = ScriptedLink()
        link.answers["index-source-set"] = [try line(#"{"id":1,"ok":true,"proposed":"prp_1","communityIndex":"# + Self.index + "}")]
        let community = CommunityIndex(link: link)
        let proposed = await community.setSource(" https://example.com/index.json ")
        XCTAssertEqual(proposed, .proposed("Waiting on the island: sign it with Touch ID and listings come from there."))
        XCTAssertEqual(link.sent.first?.indexSource, "https://example.com/index.json")
        XCTAssertEqual(community.index?.marketplace, true)
        XCTAssertNil(community.busy)

        link.answers["index-source-set"] = [try line(#"{"id":2,"ok":true}"#)]
        let reset = await community.setSource()
        XCTAssertEqual(reset, .done("Listings come from the Memnox marketplace again."))
        XCTAssertEqual(link.sent.last?.indexSource, "marketplace")
        XCTAssertEqual(link.sent.last?.method, "index-source-set")

        link.answers["index-list"] = [try line(#"{"id":3,"ok":true,"communityIndex":"# + Self.index + "}")]
        await community.refresh()
        XCTAssertNil(link.sent.last?.indexSource)
    }

    func testSaysASourceTheRuntimeRefused() async throws {
        let link = ScriptedLink()
        link.answers["index-source-set"] = [try line(#"{"id":1,"ok":false,"error":"Only this machine names where the index comes from."}"#)]
        let refused = await CommunityIndex(link: link).setSource("https://example.com/index.json")
        XCTAssertEqual(refused, .failed("Only this machine names where the index comes from."))
    }
}
