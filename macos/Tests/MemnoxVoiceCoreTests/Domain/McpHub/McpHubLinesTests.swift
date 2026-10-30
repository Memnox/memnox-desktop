import XCTest

@testable import MemnoxVoiceCore

/// The hub's words, the same as shared/tauri-core's mcp-hub-lines.ts says them.
final class McpHubLinesTests: XCTestCase {
    func testListsEachSecretOnceWithEveryServerThatNeedsIt() {
        let across = McpHubLines.secretsAcross([
            (name: "github", secretsHeld: ["token": true]),
            (name: "gh-enterprise", secretsHeld: ["token": false, "other": true]),
        ])
        XCTAssertEqual(across, [
            HubSecret(name: "other", held: true, usedBy: ["gh-enterprise"]),
            HubSecret(name: "token", held: false, usedBy: ["github", "gh-enterprise"]),
        ])
        XCTAssertEqual(McpHubLines.missingSecrets(["a": true, "b": false]), ["b"])
    }

    func testTurnsWhatAPersonTypedIntoANameAndALaunchLine() throws {
        XCTAssertEqual(McpHubLines.serverName(from: "  My GitHub! "), "my-github-")
        let split = try XCTUnwrap(McpHubLines.splitCommand(#"npx -y "@scope/server name" --flag"#))
        XCTAssertEqual(split.command, "npx")
        XCTAssertEqual(split.args, ["-y", "@scope/server name", "--flag"])
        XCTAssertNil(McpHubLines.splitCommand("   "))
        XCTAssertEqual(McpHubLines.secretName(server: "github", variable: "GITHUB_TOKEN"), "github-github-token")
    }

    func testSaysWhatASyncWroteOrThatNothingNeededWriting() {
        XCTAssertEqual(McpHubLines.synced(McpSyncSummary(added: 1, updated: 0, removed: 2, files: ["a", "b"])),
                       "Wrote 2 configs: 1 added, 2 removed.")
        XCTAssertEqual(McpHubLines.synced(McpSyncSummary(added: 0, updated: 0, removed: 0, files: [])),
                       "Every agent already has what the hub gives it.")
    }

    func testCountsInWords() {
        XCTAssertEqual(McpHubLines.tools(0), "No tools listed yet")
        XCTAssertEqual(McpHubLines.tools(1), "1 tool")
        XCTAssertEqual(McpHubLines.calls(3), "3 calls this week")
        XCTAssertEqual(McpHubLines.agents(0), "Given to no agent yet")
        XCTAssertEqual(McpHubLines.agents(2), "Given to 2 agents")
        XCTAssertEqual(McpHubLines.agentLabel("codex-cli"), "Codex")
        XCTAssertEqual(McpHubLines.agentLabel("newcomer"), "newcomer")
    }

    func testAnOrganizationServerIsReadOnlyOnThisComputer() {
        XCTAssertTrue(McpHubLines.fromOrganization(scope: "organization"))
        XCTAssertFalse(McpHubLines.fromOrganization(scope: "personal"))
        XCTAssertFalse(McpHubLines.fromOrganization(scope: nil))
    }
}
