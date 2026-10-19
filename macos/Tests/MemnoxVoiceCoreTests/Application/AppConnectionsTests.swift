import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Connecting any app with no admin in between: the catalogue searched, a sign in opened, and one taken away.
final class AppConnectionsTests: XCTestCase {
    var link: ScriptedLink!
    var slept: [TimeInterval] = []
    var apps: AppConnections!

    override func setUp() {
        link = ScriptedLink()
        slept = []
        apps = AppConnections(link: link, sleep: { [unowned self] seconds in slept.append(seconds) })
    }

    func testSearchesTheCatalogueWithTheWordsTrimmed() async throws {
        link.answers["toolkits-search"] = [try line(#"{"id":1,"ok":true,"toolkits":[{"slug":"notion","name":"Notion","logo":"https://logos.composio.dev/api/notion"}]}"#)]
        let answer = await apps.search("  notion ")
        XCTAssertEqual(link.sent.first?.query, "notion")
        XCTAssertEqual(answer, .toolkits([ToolkitSummary(slug: "notion", name: "Notion", logo: "https://logos.composio.dev/api/notion")]))
    }

    func testAsksForTheFirstPageWhenNothingIsTyped() async throws {
        link.answers["toolkits-search"] = [try line(#"{"id":1,"ok":true,"toolkits":[]}"#)]
        _ = await apps.search("   ")
        XCTAssertNil(link.sent.first?.query)
    }

    func testSaysWhyTheCatalogueCannotBeSearched() async throws {
        link.answers["toolkits-search"] = [try line(#"{"id":1,"ok":false,"error":"Sign in to Memnox Cloud first"}"#)]
        let answer = await apps.search("slack")
        XCTAssertEqual(answer, .refused("Sign in to Memnox Cloud first"))
    }

    func testOpensTheToolsSignInAndSaysWhetherTheDaemonOpenedIt() async throws {
        link.answers["connections-sign-in"] = [try line(#"{"id":1,"ok":true,"signIn":{"toolkit":"notion","url":"https://connect.composio.dev/x","opened":true}}"#)]
        let answer = await apps.signIn("notion")
        XCTAssertEqual(link.sent.first?.toolkit, "notion")
        // A first sign in sends no again, so the daemon still refuses a tool that already works.
        XCTAssertNil(link.sent.first?.again)
        XCTAssertEqual(answer, .started(ConnectionSignIn(toolkit: "notion", url: "https://connect.composio.dev/x", opened: true)))
    }

    func testSignsInAgainOnlyWhenAsked() async throws {
        link.answers["connections-sign-in"] = [try line(#"{"id":1,"ok":true,"signIn":{"toolkit":"slack","url":"https://connect.composio.dev/y","opened":false}}"#)]
        _ = await apps.signIn("slack", again: true)
        XCTAssertEqual(link.sent.first?.again, true)
    }

    func testKeepsTheDaemonsWordsForAToolAlreadyConnected() async throws {
        link.answers["connections-sign-in"] = [try line(#"{"id":1,"ok":false,"error":"Notion is already connected. Connect it again only to use another account."}"#)]
        let answer = await apps.signIn("notion")
        XCTAssertEqual(answer, .refused("Notion is already connected. Connect it again only to use another account."))
    }

    func testCallsADaemonWithNoSignInOlderRatherThanStarted() async throws {
        link.answers["connections-sign-in"] = [try line(#"{"id":1,"ok":true}"#)]
        let answer = await apps.signIn("notion")
        XCTAssertEqual(answer, .refused("This Memnox is older than the app"))
    }

    func testDisconnectsAndHandsBackTheListAsItStandsAfter() async throws {
        link.answers["connections-sign-out"] = [try line(#"{"id":1,"ok":true,"connections":[{"toolkit":"github","connected":true}]}"#)]
        let answer = await apps.signOut("slack")
        XCTAssertEqual(link.sent.first?.method, "connections-sign-out")
        XCTAssertEqual(link.sent.first?.toolkit, "slack")
        XCTAssertEqual(answer, .connections([ToolConnection(toolkit: "github", connected: true)]))
    }

    func testSaysWhyADisconnectWasRefused() async throws {
        link.answers["connections-sign-out"] = [try line(#"{"id":1,"ok":false,"error":"Slack is not connected"}"#)]
        let answer = await apps.signOut("slack")
        XCTAssertEqual(answer, .refused("Slack is not connected"))
    }

    func testCannotReachTheDaemon() async {
        link.unreachable = true
        let search = await apps.search("x")
        let signIn = await apps.signIn("x")
        let signOut = await apps.signOut("x")
        XCTAssertEqual(search, .unreachable)
        XCTAssertEqual(signIn, .unreachable)
        XCTAssertEqual(signOut, .unreachable)
    }

    func testWatchesTheListUntilTheNewSignInShowsUp() async throws {
        let before = [ToolConnection(toolkit: "github", connected: true)]
        link.answers["connections-list"] = [try line(#"{"id":1,"ok":true,"connections":[{"toolkit":"github","connected":true}]}"#)]
        let arrived = try line(#"{"id":1,"ok":true,"connections":[{"toolkit":"github","connected":true},{"toolkit":"notion","connected":true}]}"#)
        apps = AppConnections(link: link, sleep: { [unowned self] seconds in
            slept.append(seconds)
            // The browser sign in finishes during the third wait.
            if slept.count == 3 { link.answers["connections-list"] = [arrived] }
        })
        let answer = await apps.watch(from: before)
        XCTAssertEqual(slept.count, 3)
        XCTAssertEqual(answer, .connections([ToolConnection(toolkit: "github", connected: true), ToolConnection(toolkit: "notion", connected: true)]))
    }

    func testStopsWatchingAfterTwoMinutesForASignInLeftUnfinished() async throws {
        let before = [ToolConnection(toolkit: "github", connected: true)]
        link.answers["connections-list"] = [try line(#"{"id":1,"ok":true,"connections":[{"toolkit":"github","connected":true}]}"#)]
        let answer = await apps.watch(from: before)
        XCTAssertEqual(slept.count, AppConnections.watchReads)
        XCTAssertEqual(slept.reduce(0, +), 120)
        XCTAssertEqual(answer, .connections(before))
    }
}
