import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Mirrors shared/tauri-core/test/scope-chip.test.ts, so an item's scope reads the same on every desktop.
final class ScopeLinesTests: XCTestCase {
    private func rule(source: String, agents: [String]? = nil, folders: [String]? = nil) -> PolicyRuleView {
        PolicyRuleView(name: "r", effect: "ask", match: PolicyRuleMatch(actions: ["git.push"], agents: agents, workingDirectories: folders),
                       sentence: "s", source: source, editable: false)
    }

    private func server(_ extra: String) throws -> McpHubServerView {
        let json = #"{"name":"github","transport":"stdio","envNames":[],"governed":true,"toolCount":0,"health":{"state":"unknown"},"secretsHeld":{},"callsThisWeek":0"# + extra + "}"
        return try JSONDecoder().decode(McpHubServerView.self, from: Data(json.utf8))
    }

    func testNamesEveryScopeWithAWord() {
        XCTAssertEqual(ScopeKind.allCases.map(\.word), ["Personal", "Project", "Agent", "Organization"])
        XCTAssertEqual(ScopeKind.agent.label, "Scope: Agent")
    }

    func testReadsARuleAsTheOrganizationsOneAgentsOneFoldersOrThePersons() {
        XCTAssertEqual(ScopeLines.rule(rule(source: "workspace", agents: ["codex"])), .organization)
        XCTAssertEqual(ScopeLines.rule(rule(source: "person", agents: ["codex"])), .agent)
        XCTAssertEqual(ScopeLines.rule(rule(source: "file", folders: ["/code/app"])), .project)
        XCTAssertEqual(ScopeLines.rule(rule(source: "person")), .personal)
    }

    func testReadsAServerGivenOnlyInsideRepositoriesAsAProjects() throws {
        XCTAssertEqual(ScopeLines.server(try server(#","scope":"organization","agents":[]"#)), .organization)
        XCTAssertEqual(ScopeLines.server(try server(#","agents":[],"projects":[{"agent":"codex","project":"/code/app"}]"#)), .project)
        XCTAssertEqual(ScopeLines.server(try server(#","agents":["codex"]"#)), .personal)
    }

    func testTakesASkillsAMemoryItemsAndAProjectsScopeAsTheRuntimeNamesIt() throws {
        let organizational = SkillsProtocolTests.skill.replacingOccurrences(of: #""scope":"personal""#, with: #""scope":"organization""#)
        XCTAssertEqual(ScopeLines.skill(try JSONDecoder().decode(SkillView.self, from: Data(organizational.utf8))), .organization)
        XCTAssertEqual(ScopeLines.memory(MemoryItemView(id: "m", statement: "s", status: .verified, scope: .project, createdAt: "2026-10-27T00:00:00Z")), .project)
        XCTAssertEqual(ScopeLines.memory(MemoryItemView(id: "m", statement: "s", status: .verified, createdAt: "2026-10-27T00:00:00Z")), .personal)
        XCTAssertEqual(ScopeLines.project(sampleProject), .project)
        XCTAssertEqual(ScopeLines.profile, .personal)
    }
}
