import XCTest

@testable import MemnoxVoiceCore

/// The workspace's memory on the local graph: every decision, tool and person is held by the workspace, a tool this Mac
/// also uses is one node named by both, every line is read off a field, and the filter keeps either side alone.
final class WorkspaceGraphTests: XCTestCase {
    private func map(_ inputs: LocalGraphInputs) -> MemoryMap {
        LocalGraphs.map(inputs, kindLabel: { $0 })
    }

    private func node(_ map: MemoryMap, _ id: String) -> MemoryMapNode? {
        map.nodes.first { $0.id == id }
    }

    private func edges(_ map: MemoryMap, _ kind: MemoryLinkKind) -> [String] {
        map.edges.filter { $0.kind == kind }.map { "\($0.from)>\($0.to)" }.sorted()
    }

    private let pulled = WorkspaceMemoryView(
        hash: "h1",
        facts: [WorkspaceFact(id: "f1", kind: .responsibility, statement: "Ana owns payments.", subject: "payments",
                              principal: "Ana", sourceRef: "https://acme.atlassian.net/browse/PAY-1", verifiedBy: "Ben",
                              settledAt: "2026-10-20T09:00:00Z")],
        unconfirmed: [WorkspaceCandidate(id: "c1", statement: "Ship the beta on Monday.", subject: "beta", sources: ["Slack"],
                                         saidBy: ["Cara", "ana"], untrusted: true)],
        withheld: 2, syncedAt: "2026-10-30T12:00:00Z")

    func testDrawsEachDecisionWithItsToolAndItsPeopleAsTheRecordJoinsThem() {
        let graph = map(LocalGraphInputs(workspace: pulled))
        XCTAssertEqual(node(graph, "wsm:f1")?.kind, .decision)
        XCTAssertEqual(node(graph, "wsm:f1")?.status, MemoryStatus.verified.rawValue)
        XCTAssertEqual(node(graph, "wsm:c1")?.status, MemoryStatus.candidate.rawValue)
        XCTAssertEqual(node(graph, "wsm:c1")?.tainted, true)
        XCTAssertEqual(node(graph, "wsm:c1")?.detail, "Not approved by anyone")
        XCTAssertEqual(node(graph, "wsm:f1")?.workspace, .settled(pulled.facts[0]))
        XCTAssertEqual(edges(graph, .pulledFrom), ["wsm:c1>app:slack", "wsm:f1>app:jira"])
        XCTAssertEqual(edges(graph, .names), ["wsm:f1>person:ana"])
        XCTAssertEqual(edges(graph, .confirmed), ["person:ben>wsm:f1"])
        // Ana named by the fact and ana who said the candidate are one person.
        XCTAssertEqual(edges(graph, .said), ["person:ana>wsm:c1", "person:cara>wsm:c1"])
        XCTAssertEqual(graph.nodes.filter { $0.kind == .person }.count, 3)
        XCTAssertTrue(graph.nodes.allSatisfy { $0.home == .workspace })
    }

    func testATeamToolThisMacUsesIsOneNodeNamedByBoth() {
        let local = LocalGraphInputs(sessions: [LocalSession(id: "s1", agent: "claude-code", agentName: "Claude Code",
                                                             title: "Post the notes", state: "working")],
                                     apps: [LocalApp(slug: "slack", name: "Slack HQ", uses: [AppUse(agent: "claude-code", sessionId: "s1", at: "x")])],
                                     workspace: pulled)
        let graph = map(local)
        XCTAssertEqual(graph.nodes.filter { $0.id == "app:slack" }.count, 1)
        XCTAssertEqual(node(graph, "app:slack")?.home, .both)
        XCTAssertEqual(node(graph, "app:slack")?.label, "Slack HQ")
        XCTAssertEqual(node(graph, "conv:s1")?.home, .thisMac)
        XCTAssertEqual(node(graph, "app:jira")?.home, .workspace)

        let mine = MemoryMaps.held(graph, .thisMac)
        XCTAssertEqual(Set(mine.nodes.map(\.id)), ["conv:s1", "app:slack"])
        XCTAssertEqual(edges(mine, .reads), ["conv:s1>app:slack"])
        let team = MemoryMaps.held(graph, .workspace)
        XCTAssertFalse(team.nodes.contains { $0.id == "conv:s1" })
        XCTAssertTrue(team.nodes.contains { $0.id == "app:slack" })
        XCTAssertTrue(team.edges.allSatisfy { $0.kind != .reads })
        XCTAssertEqual(MemoryMaps.held(graph, .everything), graph)
    }

    func testNoPullDrawsNothingFromTheWorkspace() {
        let graph = map(LocalGraphInputs())
        XCTAssertTrue(graph.nodes.isEmpty)
    }

    func testSeatsTheWorkspaceInARegionOfItsOwn() {
        let graph = map(LocalGraphInputs(workspace: pulled))
        let groups = MemoryGroups.groups(graph, sources: [])
        for node in graph.nodes where node.kind == .decision || node.kind == .person {
            XCTAssertEqual(groups[node.id], .team, node.id)
        }
    }

    func testSaysTheSourceAndWhoSaidItAsTheConsoleDoes() {
        let fact = WorkspaceMemoryLines.rows(.settled(pulled.facts[0]))
        XCTAssertEqual(fact.first { $0.0 == "Owner" }?.1, "Ana")
        XCTAssertEqual(fact.first { $0.0 == "Confirmed by" }?.1, "Ben")
        XCTAssertEqual(fact.first { $0.0 == "Settled" }?.1, "2026-10-20")
        XCTAssertEqual(fact.first { $0.0 == "Source" }?.1, "Jira, https://acme.atlassian.net/browse/PAY-1")
        let candidate = WorkspaceMemoryLines.rows(.unconfirmed(pulled.unconfirmed[0]))
        XCTAssertEqual(candidate.first { $0.0 == "Read from" }?.1, "Slack")
        XCTAssertEqual(candidate.first { $0.0 == "Said by" }?.1, "Cara, ana")
        XCTAssertNotNil(candidate.first { $0.0 == "Trust" })
        XCTAssertEqual(WorkspaceMemoryLines.toolOf("https://acme.slack.com/archives/C1"), "slack")
        XCTAssertNil(WorkspaceMemoryLines.toolOf("https://acme.example/notes"))
        XCTAssertNil(WorkspaceMemoryLines.toolOf("PAY-1"))
    }

    func testTellsASignedOutMacToJoinAndAnEmptyPullWhatItHolds() {
        XCTAssertTrue(WorkspaceMemoryLines.emptyLine(joined: false, memory: nil)?.contains("Account") == true)
        XCTAssertTrue(WorkspaceMemoryLines.emptyLine(joined: true, memory: nil)?.contains("next pull") == true)
        XCTAssertNil(WorkspaceMemoryLines.emptyLine(joined: nil, memory: nil))
        XCTAssertNil(WorkspaceMemoryLines.emptyLine(joined: true, memory: pulled))
        XCTAssertEqual(WorkspaceMemoryLines.emptyLine(joined: true, memory: WorkspaceMemoryView(withheld: 1)),
                       "1 more your workspace keeps from this Mac.")
        XCTAssertEqual(WorkspaceMemoryLines.emptyLine(joined: true, memory: WorkspaceMemoryView()), "Your workspace has settled nothing yet.")
        // What was pulled before signing out is still shown, since the runtime keeps it in force.
        XCTAssertNil(WorkspaceMemoryLines.emptyLine(joined: false, memory: pulled))
    }

    func testFilterKeepsANodeBothNameUnderEither() {
        XCTAssertTrue(MemoryHomeFilter.thisMac.shows(.both))
        XCTAssertTrue(MemoryHomeFilter.workspace.shows(.both))
        XCTAssertFalse(MemoryHomeFilter.thisMac.shows(.workspace))
        XCTAssertFalse(MemoryHomeFilter.workspace.shows(.thisMac))
    }
}
