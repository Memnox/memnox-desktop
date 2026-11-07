import XCTest

@testable import MemnoxVoiceCore

/// Mirrors the use case half of shared/tauri-core/test/local-network.test.ts.
final class LocalNetworkTests: XCTestCase {
    private static let off = #"{"on":false,"listening":false,"addresses":[],"advertised":false,"reachable":[]}"#
    private static let on = #"{"on":true,"listening":true,"addresses":["192.168.1.20"],"port":47820,"advertised":true,"reachable":[]}"#

    func testReadsTheStatusAndTurnsItOffAtOnce() async throws {
        let link = ScriptedLink()
        link.answers["lan-status"] = [try line(#"{"id":1,"ok":true,"lan":"# + Self.on + "}")]
        link.answers["lan-set"] = [try line(#"{"id":2,"ok":true,"lan":"# + Self.off + "}")]
        let lan = LocalNetwork(link: link)
        await lan.refresh()
        XCTAssertEqual(lan.status?.port, 47820)
        let outcome = await lan.set(on: false)
        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(link.sent.last?.lanOn, false)
        XCTAssertEqual(lan.status?.on, false)
    }

    func testOnlyProposesTurningItOnAndPassesARefusalOn() async throws {
        let link = ScriptedLink()
        link.answers["lan-set"] = [try line(#"{"id":1,"ok":true,"proposed":"prp_lan","lan":"# + Self.off + "}")]
        let proposed = await LocalNetwork(link: link).set(on: true)
        XCTAssertEqual(proposed, .proposed(id: "prp_lan"))

        let refusing = ScriptedLink()
        refusing.answers["lan-set"] = [try line(#"{"id":1,"ok":false,"error":"Not from a phone."}"#)]
        let refused = await LocalNetwork(link: refusing).set(on: true)
        XCTAssertEqual(refused, .failed("Not from a phone."))

        let down = ScriptedLink()
        down.unreachable = true
        let gone = LocalNetwork(link: down)
        await gone.refresh()
        XCTAssertTrue(gone.unreadable)
    }
}
