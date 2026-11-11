import XCTest

@testable import MemnoxVoiceCore

/// Mirrors the use case half of shared/tauri-core/test/local-network.test.ts.
final class LocalNetworkTests: XCTestCase {
    private static let on = #"{"on":true,"listening":true,"addresses":["192.168.1.20"],"port":47820,"advertised":true,"reachable":[]}"#

    func testReadsTheStatusAndSaysWhenTheRuntimeIsAway() async throws {
        let link = ScriptedLink()
        link.answers["lan-status"] = [try line(#"{"id":1,"ok":true,"lan":"# + Self.on + "}")]
        let lan = LocalNetwork(link: link)
        await lan.refresh()
        XCTAssertEqual(lan.status?.port, 47820)
        XCTAssertFalse(lan.unreadable)

        let down = ScriptedLink()
        down.unreachable = true
        let gone = LocalNetwork(link: down)
        await gone.refresh()
        XCTAssertTrue(gone.unreadable)
    }
}
