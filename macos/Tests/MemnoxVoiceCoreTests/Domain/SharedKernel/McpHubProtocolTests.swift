import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// The MCP Hub as the runtime's daemon/mcp-hub.ts writes it.
final class McpHubProtocolTests: XCTestCase {
    private let hub = #"{"id":3,"ok":true,"mcpHub":{"servers":[{"name":"github","description":"Issues and pull requests","transport":"stdio","command":"npx","args":["-y","server-github"],"envNames":["LOG_LEVEL"],"governed":true,"toolCount":2,"tools":[{"name":"create_issue","description":"Opens an issue"},{"name":"list_prs"}],"health":{"state":"healthy","checkedAt":"2026-10-30T09:00:00.000Z"},"agents":["claude-code"],"secretsHeld":{"github-token":true},"callsThisWeek":4},{"name":"linear","transport":"http","url":"https://mcp.linear.app/mcp","envNames":[],"governed":false,"toolCount":0,"health":{"state":"unknown"},"agents":[],"secretsHeld":{},"callsThisWeek":0}],"agents":[{"agent":"claude-code","path":"/Users/me/.claude.json"}],"found":[{"agent":"cursor","path":"/Users/me/.cursor/mcp.json","name":"notion"},{"path":"/repo/.mcp.json","name":"shared"}],"drifted":[{"agent":"claude-code","path":"/Users/me/.claude.json","name":"github","kind":"edited"}],"skipped":[{"agent":"codex-cli","path":"/Users/me/.codex/config.toml","name":"linear","reason":"Codex reads no remote servers."}]}}"#

    func testReadsEveryPartOfTheHub() throws {
        let view = try XCTUnwrap(try line(hub).mcpHub)
        XCTAssertEqual(view.servers.map(\.name), ["github", "linear"])
        let github = view.servers[0]
        XCTAssertEqual(github.hubTransport, .stdio)
        XCTAssertEqual(github.args, ["-y", "server-github"])
        XCTAssertEqual(github.envNames, ["LOG_LEVEL"])
        XCTAssertTrue(github.governed)
        XCTAssertEqual(github.tools?.map(\.name), ["create_issue", "list_prs"])
        XCTAssertNil(github.tools?.last?.description)
        XCTAssertEqual(github.health.healthState, .healthy)
        XCTAssertEqual(github.secretsHeld, ["github-token": true])
        XCTAssertEqual(github.callsThisWeek, 4)
        let linear = view.servers[1]
        XCTAssertEqual(linear.hubTransport, .http)
        XCTAssertEqual(linear.url, "https://mcp.linear.app/mcp")
        XCTAssertNil(linear.command)
        XCTAssertNil(linear.tools)
        XCTAssertEqual(view.agents, [McpHubAgentView(agent: "claude-code", path: "/Users/me/.claude.json")])
        XCTAssertEqual(view.found.map(\.agent), ["cursor", nil])
        XCTAssertEqual(view.drifted.first?.kind, "edited")
        XCTAssertEqual(view.skipped.first?.reason, "Codex reads no remote servers.")
    }

    func testReadsATestAndASync() throws {
        let tested = try line(#"{"id":4,"ok":true,"mcpHealth":{"state":"error","checkedAt":"2026-10-30T09:00:00.000Z","error":"spawn npx ENOENT"}}"#)
        XCTAssertEqual(tested.mcpHealth?.healthState, .error)
        XCTAssertEqual(tested.mcpHealth?.error, "spawn npx ENOENT")
        let synced = try line(#"{"id":5,"ok":true,"mcpSynced":{"added":1,"updated":0,"removed":2,"files":["/a","/b"]}}"#)
        XCTAssertEqual(synced.mcpSynced, McpSyncSummary(added: 1, updated: 0, removed: 2, files: ["/a", "/b"]))
    }

    func testReadsAWideningChangeAsAProposal() throws {
        let response = try line(#"{"id":6,"ok":true,"proposed":"prp_4"}"#)
        XCTAssertEqual(response.proposed, "prp_4")
        XCTAssertNil(response.mcpHub)
    }

    func testAnUnknownHealthIsKeptButNotNamed() throws {
        let response = try line(#"{"id":7,"ok":true,"mcpHealth":{"state":"warming"}}"#)
        XCTAssertEqual(response.mcpHealth?.state, "warming")
        XCTAssertNil(response.mcpHealth?.healthState)
    }

    func testAnOlderDaemonLeavesTheHubOut() throws {
        let response = try line(#"{"id":8,"ok":false,"error":"unknown method mcp-hub"}"#)
        XCTAssertNil(response.mcpHub)
        XCTAssertNil(response.mcpHealth)
        XCTAssertNil(response.mcpSynced)
    }

    func testWritesAServerWithSecretsByNameOnly() throws {
        var request = DaemonRequest(id: 9, method: .mcpServerPut)
        request.mcpServer = HubServer(name: "github", transport: .stdio, command: "npx", args: ["-y", "server-github"],
                                      env: ["LOG_LEVEL": "info"], secrets: ["GITHUB_TOKEN": "github-github-token"])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encodeLine(request)) as? [String: Any])
        XCTAssertEqual(object["method"] as? String, "mcp-server-put")
        let server = try XCTUnwrap(object["mcpServer"] as? [String: Any])
        XCTAssertEqual(server["transport"] as? String, "stdio")
        XCTAssertEqual(server["secrets"] as? [String: String], ["GITHUB_TOKEN": "github-github-token"])
        XCTAssertNil(server["url"])
        XCTAssertNil(server["description"])
    }

    func testWritesAnAssignment() throws {
        var request = DaemonRequest(id: 10, method: .mcpAssign)
        request.mcpServerName = "github"
        request.mcpAgent = "codex-cli"
        request.mcpOn = false
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encodeLine(request)) as? [String: Any])
        XCTAssertEqual(object["mcpServerName"] as? String, "github")
        XCTAssertEqual(object["mcpAgent"] as? String, "codex-cli")
        XCTAssertEqual(object["mcpOn"] as? Bool, false)
        XCTAssertNil(object["mcpSecretValue"])
    }

    func testNamesEveryHubMethodAsTheRuntimeDoes() {
        let methods: [DaemonMethod] = [.mcpHub, .mcpServerPut, .mcpServerRemove, .mcpAssign, .mcpImport, .mcpSync, .mcpTest,
                                       .mcpSecretSet, .mcpSecretRemove]
        XCTAssertEqual(methods.map(\.rawValue), ["mcp-hub", "mcp-server-put", "mcp-server-remove", "mcp-assign", "mcp-import",
                                                 "mcp-sync", "mcp-test", "mcp-secret-set", "mcp-secret-remove"])
    }
}
