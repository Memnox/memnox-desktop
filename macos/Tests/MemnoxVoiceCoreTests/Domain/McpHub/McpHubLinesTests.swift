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

    private func server(_ extra: String) throws -> McpHubServerView {
        let json = #"{"name":"github","transport":"stdio","envNames":[],"governed":true,"toolCount":0,"health":{"state":"unknown"},"agents":["claude-code","claude-code","cursor"],"secretsHeld":{},"callsThisWeek":0"# + extra + "}"
        return try JSONDecoder().decode(McpHubServerView.self, from: Data(json.utf8))
    }

    func testNamesTheAgentsThatUseAServerOnceEach() throws {
        XCTAssertEqual(McpHubLines.usedBy(try server("")), "Claude Code and Cursor")
        let none = try JSONDecoder().decode(McpHubServerView.self, from: Data(#"{"name":"x","transport":"http","envNames":[],"governed":false,"toolCount":0,"health":{"state":"unknown"},"agents":[],"secretsHeld":{},"callsThisWeek":0}"#.utf8))
        XCTAssertEqual(McpHubLines.usedBy(none), "Given to no agent yet")
        XCTAssertEqual(McpHubLines.transport(none), "Remote")
        XCTAssertEqual(McpHubLines.transport(try server("")), "Local")
    }

    func testNamesTheRepositoryAnAgentWasGivenAServerIn() throws {
        let given = try server(#","projects":[{"agent":"claude-code","project":"/Users/bo/code/billing"}]"#)
        XCTAssertEqual(McpHubLines.projects(given, agent: "claude-code"),
                       [McpHubLines.ProjectChip(name: "billing", path: "/Users/bo/code/billing")])
        XCTAssertEqual(McpHubLines.projects(given, agent: "cursor"), [])
        XCTAssertEqual(McpHubLines.projectHelp(agent: "claude-code", path: "/Users/bo/code/billing"),
                       "Given to Claude Code in /Users/bo/code/billing only")
        XCTAssertEqual(McpHubLines.agentsOnce(given), ["claude-code", "cursor"])
    }

    func testNamesNoRepositoryFromARuntimeThatSendsNone() throws {
        XCTAssertEqual(McpHubLines.projects(try server(""), agent: "claude-code"), [])
        XCTAssertEqual(McpHubLines.projectFolder("/Users/bo/code/web/"), "web")
    }

    func testTellsAnEverywhereAssignmentFromAProjectOnlyOneAndFromNone() throws {
        // Claude Code is listed twice: once everywhere and once in billing. Cursor only in web.
        let given = try server(#","projects":[{"agent":"claude-code","project":"/Users/bo/code/billing"},{"agent":"cursor","project":"/Users/bo/code/web"}]"#)
        XCTAssertEqual(McpHubLines.reach(given, agent: "claude-code"), .everywhere)
        XCTAssertEqual(McpHubLines.reach(given, agent: "cursor"), .projects)
        XCTAssertEqual(McpHubLines.reach(given, agent: "codex-cli"), .none)
        XCTAssertEqual(McpHubLines.reach(try server(""), agent: "cursor"), .everywhere)
        XCTAssertEqual(McpHubLines.reachCaption(given, agent: "claude-code"), "Has this server in every project")
        XCTAssertEqual(McpHubLines.reachCaption(given, agent: "cursor"), "Has this server only in web")
        XCTAssertNil(McpHubLines.reachCaption(given, agent: "codex-cli"))
        XCTAssertEqual(McpHubLines.projectOnlyHelp(given, agent: "cursor"),
                       "Cursor has this server only in /Users/bo/code/web, given in that project's settings in Projects.")
    }

    func testCountsTheProjectsOfAnAgentGivenAServerInMoreThanOne() throws {
        let given = try server(#","projects":[{"agent":"cursor","project":"/a/web"},{"agent":"cursor","project":"/a/api"}]"#)
        XCTAssertEqual(McpHubLines.reachCaption(given, agent: "cursor"), "Has this server only in 2 projects")
    }

    func testOffersAProjectOnlyAgentTheServerInEveryProject() throws {
        XCTAssertEqual(McpHubLines.giveEverywhere, "Give in every project")
        XCTAssertEqual(McpHubLines.projectOnlyLine,
                       "A folder means the agent has this server only in that project. It is given in that project's settings, so it is changed in Projects, and giving it here gives it in every project.")
    }

    func testAPressIsSaidInItsRowWaitingDoneOrRefused() {
        XCTAssertNil(McpHubLines.pressLine(nil))
        XCTAssertNil(McpHubLines.pressLine(.working))
        XCTAssertEqual(McpHubLines.pressLine(.waiting(nil))?.text, "Waiting for Touch ID on the island")
        XCTAssertEqual(McpHubLines.pressLine(.failed("No."))?.tone, .bad)
        XCTAssertEqual(McpHubLines.pressLine(.done("Given."))?.tone, .good)
    }

    func testAnAddedServerSaysWhatWaitsWhatRunsAndWhoIsAskedForNext() {
        let line = McpHubLines.added(.waiting("pip install comfy-mcp only installs comfy-mcp, so the hub starts it with uvx comfy-mcp."),
                                     server: "comfyui", agents: ["cursor", "claude-code"])
        XCTAssertEqual(line, "comfyui waits for Touch ID on the island. pip install comfy-mcp only installs comfy-mcp, so the hub starts it with uvx comfy-mcp. Once it is signed, giving it to Cursor and Claude Code asks for Touch ID again.")
        XCTAssertEqual(McpHubLines.added(.waiting(nil), server: "github", agents: []), "github waits for Touch ID on the island.")
    }
}
