import Foundation
import XCTest

@testable import MemnoxVoiceCore

final class ScanTallyTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private func tally() throws -> ScanTally {
        let agents = try decode([AgentStanding].self, #"[{"kind":"claude-code","name":"Claude Code","status":"protected","sessions":{"running":0,"idle":0,"finished":0},"mcpServers":[],"today":{"actions":0,"asked":0,"refused":0},"recent":[]},{"kind":"cursor","name":"Cursor","status":"unprotected","sessions":{"running":0,"idle":0,"finished":0},"mcpServers":[],"today":{"actions":0,"asked":0,"refused":0},"recent":[]}]"#)
        let skills = try decode(SkillsHubView.self, #"{"skills":[],"agents":[],"found":[{"id":"f1","name":"frontend-design","agent":"claude-code","kind":"skill","path":"p","tools":[],"grant":"g","imported":false},{"id":"f2","name":"frontend-design","agent":"cursor","kind":"skill","path":"p","tools":[],"grant":"g","imported":false}]}"#)
        let servers = try decode(McpHubView.self, #"{"servers":[],"agents":[],"drifted":[],"skipped":[],"found":[{"agent":"cursor","path":"p","name":"notion"},{"path":"/code/.mcp.json","name":"playwright"}]}"#)
        let source = MemorySourceView(id: "s", kind: .obsidian, name: "Vault", location: "/v", watched: true)
        let apps = [YourAppCard(slug: "gmail", name: "Gmail", standing: .connected, categories: []),
                    YourAppCard(slug: "slack", name: "Slack", standing: .available, categories: [])]
        return ScanLines.tally(agents: agents, skills: skills, servers: servers, sources: [source], apps: apps)
    }

    func testFindsEachKindInOrderAndCountsANameOnce() throws {
        let found = try tally()
        XCTAssertEqual(found.findings.map(\.kind), [.agents, .agents, .skills, .servers, .sources, .apps])
        XCTAssertEqual(found.count(.skills), 1)
        XCTAssertEqual(found.findings[3].detail, "In Cursor")
    }

    func testLeavesARepositorysOwnServersOffThisMac() throws {
        XCTAssertFalse(try tally().findings.contains { $0.name == "playwright" })
    }

    func testCountsNoPersonaAndNoSkillAlreadyImportedAsASkill() throws {
        let skills = try decode(SkillsHubView.self, #"{"skills":[],"agents":[],"found":[{"id":"f1","name":"reviewer","agent":"claude-code","kind":"agent","path":"p","tools":[],"grant":"g","imported":false},{"id":"f2","name":"pdf","agent":"claude-code","kind":"skill","path":"p","tools":[],"grant":"g","imported":true},{"id":"f3","name":"docx","agent":"claude-code","kind":"skill","path":"p","tools":[],"grant":"g","imported":false}]}"#)
        let found = ScanLines.tally(agents: [], skills: skills, servers: nil, sources: [], apps: [])
        XCTAssertEqual(found.findings.filter { $0.kind == .skills }.map(\.name), ["docx"])
    }

    func testCountsAServerOnceAcrossTheHubAndTwoAgentsButTwoProgramsByOneNameAsTwo() throws {
        let servers = try decode(McpHubView.self, #"{"servers":[{"name":"linear","transport":"stdio","command":"/usr/local/bin/npx","envNames":[],"governed":true,"toolCount":0,"health":{"state":"unknown"},"agents":["claude-code"],"secretsHeld":{},"callsThisWeek":0}],"agents":[],"drifted":[],"skipped":[],"found":[{"agent":"cursor","path":"p","name":"github"}]}"#)
        let scanned = AgentsScanView(agents: [
            AgentNode(id: "agt_claude-code", kind: "claude-code", name: "Claude Code",
                      mcp: [AgentServer(name: "linear", command: "memnox"), AgentServer(name: "github", command: "npx")]),
            AgentNode(id: "agt_cursor", kind: "cursor", name: "Cursor",
                      mcp: [AgentServer(name: "github", command: "npx"), AgentServer(name: "github", command: "docker")]),
        ], capabilities: CapabilityShare(total: 3))
        let found = ScanLines.tally(agents: [], scanned: scanned, skills: nil, servers: servers, sources: [], apps: [])
        XCTAssertEqual(found.findings.filter { $0.kind == .servers }.map(\.name), ["linear", "github", "github"])
        XCTAssertEqual(found.findings.filter { $0.kind == .agents }.map(\.name), ["Claude Code", "Cursor"])
    }

    func testDrawsEachAgentFromTheCardsWithItsServersButNoSessionsItCannotTellApart() throws {
        let agents = try decode([AgentStanding].self, #"[{"kind":"cursor","name":"Cursor","status":"protected","sessions":{"running":2,"idle":0,"finished":0},"mcpServers":["notion","github"],"today":{"actions":0,"asked":0,"refused":0},"recent":[]}]"#)
        let nodes = ScanLines.nodes(agents)
        let node = try XCTUnwrap(nodes.first)
        XCTAssertEqual(node.id, "agt_cursor")
        XCTAssertEqual(node.servers, 2)
        // Running on a card counts a session merely open, so it is never drawn as working.
        XCTAssertEqual(node.working, 0)
        XCTAssertEqual(node.mcp?.map(\.name), ["notion", "github"])
        XCTAssertEqual(ScanFigures.working(nodes, sessionsKnown: false), .unknown)
        XCTAssertEqual(ScanFigures.tools(nodes), .unknown)
        XCTAssertEqual(ScanFigures.capabilities(nodes), .unknown)
    }

    func testDecodesTheRuntimesScanWithWorkingAndOpenApart() throws {
        let response = try decode(DaemonResponse.self, #"{"id":1,"ok":true,"agentsScan":{"agents":[{"id":"agt_claude-code","kind":"claude-code","name":"Claude Code","servers":1,"reaches":["shell"],"working":1,"open":2,"mcp":[{"name":"github","command":"npx","tools":3,"changing":2}],"clis":[],"capabilities":{"total":2,"areas":[{"area":"code","count":2}]}}],"capabilities":{"total":2,"areas":[{"area":"code","count":2}]}}}"#)
        let scanned = try XCTUnwrap(response.agentsScan)
        XCTAssertEqual(scanned.agents.first?.working, 1)
        XCTAssertEqual(scanned.agents.first?.open, 2)
        XCTAssertEqual(scanned.agents.first?.mcp?.first?.command, "npx")
        XCTAssertEqual(ScanFigures.working(scanned.agents, sessionsKnown: true), .counted(1))
        XCTAssertEqual(ScanFigures.tools(scanned.agents), .counted(3))
        XCTAssertEqual(ScanFigures.capabilities(scanned.agents), .counted(2))
        XCTAssertNil(try decode(DaemonResponse.self, #"{"id":1,"ok":true}"#).agentsScan)
    }

    func testCountsAServerTwoAgentsShareOnceInTheTools() {
        let shared = AgentServer(name: "github", command: "npx", tools: 4, changing: 1)
        let agents = [AgentNode(id: "a", kind: "claude-code", name: "A", mcp: [shared], capabilities: CapabilityShare(total: 1)),
                      AgentNode(id: "b", kind: "cursor", name: "B", mcp: [shared], capabilities: CapabilityShare(total: 0))]
        XCTAssertEqual(ScanFigures.tools(agents), .counted(4))
        XCTAssertEqual(ScanFigures.capabilities(agents), .counted(1))
    }

    func testSaysCountingRatherThanZeroForToolsNoServerHasSaidYet() {
        let agents = [AgentNode(id: "a", kind: "claude-code", name: "A", mcp: [AgentServer(name: "github")], capabilities: CapabilityShare())]
        XCTAssertEqual(ScanFigures.tools(agents), .counting)
        XCTAssertEqual(ScanFigures.capabilities(agents), .counting)
    }

    func testCountsAnAgentWithNoServersAsNoTools() {
        let agents = [AgentNode(id: "a", kind: "claude-code", name: "A", mcp: [], capabilities: CapabilityShare(total: 0))]
        XCTAssertEqual(ScanFigures.tools(agents), .counted(0))
    }

    func testSaysTheWholeScanInALine() throws {
        XCTAssertEqual(ScanLines.summary(try tally()), "Found 2 agents, 1 skill, 1 tool, 1 memory source and 1 connected app.")
        XCTAssertEqual(ScanLines.summary(ScanTally(findings: [])),
                       "Found no agents, no skills, no tools, no memory sources and no connected apps.")
    }
}
