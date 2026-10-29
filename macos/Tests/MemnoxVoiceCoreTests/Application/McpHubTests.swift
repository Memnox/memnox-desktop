import XCTest

@testable import MemnoxVoiceCore

/// Mirrors shared/tauri-core/test/mcp-hub.test.ts, so the Mac keeps the hub the way Windows and Linux do.
final class McpHubTests: XCTestCase {
    private static func view(servers: Bool = true) -> String {
        let github = #"{"name":"github","transport":"stdio","command":"npx","args":["-y","server-github"],"envNames":[],"governed":true,"toolCount":3,"health":{"state":"unknown"},"agents":["claude-code"],"secretsHeld":{"github-token":true},"callsThisWeek":4}"#
        return #"{"servers":["# + (servers ? github : "") + #"],"agents":[{"agent":"claude-code","path":"/home/me/.claude.json"}],"found":[{"agent":"cursor","path":"/home/me/.cursor/mcp.json","name":"notion"}],"drifted":[],"skipped":[]}"#
    }

    func testReadsTheHubAndRedrawsFromEveryAnswer() async throws {
        let link = ScriptedLink()
        link.answers["mcp-hub"] = [try line(#"{"id":1,"ok":true,"mcpHub":"# + Self.view() + "}")]
        let hub = McpHub(link: link)
        await hub.refresh()
        XCTAssertEqual(hub.hub?.servers.first?.name, "github")
        XCTAssertFalse(hub.unreadable)
    }

    func testARefusedOrMissingRuntimeReadsAsUnreadable() async throws {
        let link = ScriptedLink()
        link.unreachable = true
        let hub = McpHub(link: link)
        await hub.refresh()
        XCTAssertTrue(hub.unreadable)
        XCTAssertNil(hub.hub)
        let outcome = await hub.sync()
        XCTAssertEqual(outcome, .failed("The runtime is not answering."))
    }

    func testSaysAWideningChangeWaitsForASignatureRatherThanClaimingItIsDone() async throws {
        let link = ScriptedLink()
        link.answers["mcp-assign"] = [try line(#"{"id":1,"ok":true,"proposed":"prp_1"}"#)]
        let hub = McpHub(link: link)
        let outcome = await hub.assign("github", agent: "codex-cli", on: true)
        XCTAssertEqual(outcome, .proposed("prp_1"))
        let sent = try XCTUnwrap(link.sent.first)
        XCTAssertEqual(sent.method, "mcp-assign")
        XCTAssertEqual(sent.mcpServerName, "github")
        XCTAssertEqual(sent.mcpAgent, "codex-cli")
        XCTAssertEqual(sent.mcpOn, true)
        XCTAssertNil(hub.busy)
    }

    func testTakingAwayIsDoneAtOnceAndSaidSo() async throws {
        let link = ScriptedLink()
        link.answers["mcp-assign"] = [try line(#"{"id":1,"ok":true}"#)]
        let hub = McpHub(link: link)
        let outcome = await hub.assign("github", agent: "cursor", on: false)
        XCTAssertEqual(outcome, .done("Cursor no longer has github."))
    }

    func testPassesOnTheRuntimesRefusalInItsOwnWords() async throws {
        let link = ScriptedLink()
        link.answers["mcp-secret-set"] = [try line(#"{"id":1,"ok":false,"error":"only on this computer"}"#)]
        let hub = McpHub(link: link)
        let outcome = await hub.setSecret("github-token", value: "value")
        XCTAssertEqual(outcome, .failed("only on this computer"))
        XCTAssertEqual(link.sent.first?.mcpSecretValue, "value")
    }

    func testSaysWhatASyncWrote() async throws {
        let link = ScriptedLink()
        link.answers["mcp-sync"] = [try line(#"{"id":1,"ok":true,"mcpSynced":{"added":1,"updated":0,"removed":2,"files":["a","b"]}}"#)]
        let hub = McpHub(link: link)
        let outcome = await hub.sync()
        XCTAssertEqual(outcome, .done("Wrote 2 configs: 1 added, 2 removed."))
    }

    func testKeepsATestNewerThanTheViewAndSaysWhetherItAnswered() async throws {
        let link = ScriptedLink()
        link.answers["mcp-test"] = [try line(#"{"id":1,"ok":true,"mcpHealth":{"state":"healthy","tools":[{"name":"create_issue"}]}}"#)]
        let hub = McpHub(link: link)
        let outcome = await hub.test("github")
        XCTAssertEqual(outcome, .done("github answered."))
        XCTAssertEqual(hub.testOf("github")?.tools?.map(\.name), ["create_issue"])
        XCTAssertNil(hub.busy)
    }

    func testGivesAServerAddedWithAgentsChosenOnlyOnceTheSignedServerIsInTheHub() async throws {
        let link = ScriptedLink()
        link.answers["mcp-hub"] = [try line(#"{"id":1,"ok":true,"mcpHub":"# + Self.view(servers: false) + "}")]
        link.answers["mcp-assign"] = [try line(#"{"id":2,"ok":true,"proposed":"prp_2"}"#)]
        let hub = McpHub(link: link)
        hub.giveOnceAdded("github", agents: ["codex-cli"])
        await hub.refresh()
        XCTAssertTrue(link.sent.filter { $0.method == "mcp-assign" }.isEmpty)
        link.answers["mcp-hub"] = [try line(#"{"id":3,"ok":true,"mcpHub":"# + Self.view() + "}")]
        await hub.refresh()
        await hub.refresh()
        let assigned = link.sent.filter { $0.method == "mcp-assign" }
        XCTAssertEqual(assigned.count, 1)
        XCTAssertEqual(assigned.first?.mcpAgent, "codex-cli")
    }

    private static let comfyui = HubServer(name: "comfyui", transport: .stdio, command: "pip", args: ["install", "comfy-mcp"],
                                           env: [:], secrets: [:])

    private static func hubWith(_ servers: String) -> String {
        #"{"servers":["# + servers + #"],"agents":[{"agent":"cursor","path":"/home/me/.cursor/mcp.json"}],"found":[],"drifted":[],"skipped":[]}"#
    }

    private static func comfyuiView(agents: [String]) -> String {
        let given = agents.map { "\"\($0)\"" }.joined(separator: ",")
        return #"{"name":"comfyui","transport":"stdio","command":"uvx","args":["comfy-mcp"],"envNames":[],"governed":true,"toolCount":0,"health":{"state":"unknown"},"agents":["# + given + #"],"secretsHeld":{},"callsThisWeek":0}"#
    }

    func testAServerAddedIsGivenToItsAgentsOnceTheIslandSignsItAndTheDaemonSaysItSettled() async throws {
        let link = ScriptedLink()
        link.answers["mcp-server-put"] = [try line(#"{"id":1,"ok":true,"proposed":"prp_put","outcome":"pip install comfy-mcp only installs comfy-mcp, so the hub starts it with uvx comfy-mcp, which installs it the first time it starts."}"#)]
        let hub = McpHub(link: link)
        let outcome = await hub.putServer(Self.comfyui, giveTo: ["cursor"])
        XCTAssertEqual(outcome, .proposed("prp_put"))
        guard case .waiting(let note)? = hub.press("comfyui") else { return XCTFail("the row says it waits on the island") }
        XCTAssertTrue(note?.contains("uvx comfy-mcp") == true)
        XCTAssertTrue(link.sent.filter { $0.method == "mcp-assign" }.isEmpty)

        link.answers["mcp-hub"] = [try line(#"{"id":2,"ok":true,"mcpHub":"# + Self.hubWith(Self.comfyuiView(agents: [])) + "}")]
        link.answers["mcp-assign"] = [try line(#"{"id":3,"ok":true,"proposed":"prp_give"}"#)]
        await hub.settled("prp_put")
        XCTAssertEqual(hub.press("comfyui"), .done("comfyui is in the hub."))
        let assigned = link.sent.filter { $0.method == "mcp-assign" }
        XCTAssertEqual(assigned.map(\.mcpAgent), ["cursor"])
        XCTAssertEqual(assigned.first?.mcpServerName, "comfyui")
        XCTAssertEqual(hub.press(McpHub.pair("comfyui", "cursor")), .waiting(nil))

        link.answers["mcp-hub"] = [try line(#"{"id":4,"ok":true,"mcpHub":"# + Self.hubWith(Self.comfyuiView(agents: ["cursor"])) + "}")]
        await hub.settled("prp_give")
        XCTAssertEqual(hub.press(McpHub.pair("comfyui", "cursor")), .done("Cursor has comfyui now."))
    }

    func testAProposalThatSettlesWithoutBeingWrittenSaysSoAndGivesNothing() async throws {
        let link = ScriptedLink()
        link.answers["mcp-server-put"] = [try line(#"{"id":1,"ok":true,"proposed":"prp_put"}"#)]
        let hub = McpHub(link: link)
        _ = await hub.putServer(Self.comfyui, giveTo: ["cursor"])
        link.answers["mcp-hub"] = [try line(#"{"id":2,"ok":true,"mcpHub":"# + Self.hubWith("") + "}")]
        await hub.settled("prp_put")
        XCTAssertEqual(hub.press("comfyui"), .failed(McpHubLines.notSigned))
        link.answers["mcp-hub"] = [try line(#"{"id":3,"ok":true,"mcpHub":"# + Self.hubWith(Self.comfyuiView(agents: [])) + "}")]
        await hub.refresh()
        XCTAssertTrue(link.sent.filter { $0.method == "mcp-assign" }.isEmpty)
    }

    func testASettledEventForSomethingElseReadsNothing() async throws {
        let link = ScriptedLink()
        let hub = McpHub(link: link)
        await hub.settled("prp_other")
        XCTAssertTrue(link.sent.isEmpty)
    }

    func testAnImportIsKeptUnderItsFoundLineAndARefusalIsSaidThere() async throws {
        let link = ScriptedLink()
        link.answers["mcp-import"] = [try line(#"{"id":1,"ok":false,"error":"The hub already has a different server named notion."}"#)]
        let hub = McpHub(link: link)
        _ = await hub.importServer(agent: "cursor", server: "notion")
        XCTAssertEqual(hub.press(McpHub.found("notion", "cursor")), .failed("The hub already has a different server named notion."))
        XCTAssertNil(hub.press("notion"))
        XCTAssertNil(hub.busy)
    }
}
