import XCTest

@testable import MemnoxVoiceCore

/// The local graph draws memory content only and links only what a field joins: every line here is checked against the
/// field it was read from, and every agent is said as who used a piece rather than drawn.
final class LocalGraphTests: XCTestCase {
    private let label: (String) -> String = { $0 == "obsidian" ? "Obsidian vault" : $0 }
    private let repo = "/Users/me/code/shop"

    private func item(_ id: String, project: String? = nil, suggestedBy: String? = nil, rule: MemoryRuleView? = nil,
                      evidence: [MemoryEvidenceView] = []) -> MemoryItemView {
        MemoryItemView(id: id, statement: "Statement \(id)", status: .verified, project: project, suggestedBy: suggestedBy, rule: rule,
                       evidence: evidence, createdAt: "2026-10-20T09:00:00Z")
    }

    private func edges(_ map: MemoryMap, _ kind: MemoryLinkKind) -> [String] {
        map.edges.filter { $0.kind == kind }.map { "\($0.from)>\($0.to)" }.sorted()
    }

    private func map(_ inputs: LocalGraphInputs) -> MemoryMap {
        LocalGraphs.map(inputs, kindLabel: label)
    }

    private func node(_ map: MemoryMap, _ id: String) -> MemoryMapNode? {
        map.nodes.first { $0.id == id }
    }

    func testNeverDrawsAnAgentAndNamesWhoUsedEachPieceInstead() {
        let graph = map(LocalGraphInputs(agents: [LocalAgent(kind: "claude-code", name: "Claude Code")],
                                         sessions: [LocalSession(id: "s1", agent: "claude-code", agentName: "Claude Code",
                                                                 title: "Fix the cart", state: "working")],
                                         apps: [LocalApp(slug: "gmail", name: "Gmail", uses: [AppUse(agent: "claude-code", sessionId: "s1", at: "x")])]))
        XCTAssertEqual(Set(graph.nodes.map(\.kind)), [.conversation, .app])
        XCTAssertEqual(node(graph, "conv:s1")?.usedBy, ["Claude Code"])
        XCTAssertEqual(node(graph, "app:gmail")?.usedBy, ["Claude Code"])
        XCTAssertEqual(node(graph, "app:gmail")?.mark, "gmail")
        XCTAssertEqual(edges(graph, .reads), ["conv:s1>app:gmail"])
    }

    func testLeavesOffAnAppWhoseCallsNeverFedMemory() {
        XCTAssertTrue(map(LocalGraphInputs(apps: [LocalApp(slug: "docker", name: "Docker")])).nodes.isEmpty)
    }

    func testNamesAConversationByItsTitleThenItsProjectThenItsAgentAndDropsOneThatSaysNothing() {
        let graph = map(LocalGraphInputs(sessions: [
            LocalSession(id: "titled", agent: "codex", agentName: "Codex", title: "Fix the cart", state: "idle"),
            LocalSession(id: "foldered", agent: "codex", agentName: "Codex", state: "idle", folder: repo),
            LocalSession(id: "bare", agent: "codex", agentName: "Codex", state: "idle"),
            LocalSession(id: "nobody", agent: "unknown", agentName: "Unknown", state: "idle"),
        ]))
        XCTAssertEqual(node(graph, "conv:titled")?.label, "Fix the cart")
        XCTAssertEqual(node(graph, "conv:foldered")?.label, "Work in shop")
        XCTAssertEqual(node(graph, "conv:bare")?.label, "Codex conversation")
        XCTAssertNil(node(graph, "conv:nobody"))
        XCTAssertFalse(graph.nodes.contains { $0.label.contains("Unknown") })
    }

    func testAConversationsFolderBecomesAProjectWhenNoneHoldsItAndASubfolderJoinsIt() {
        let graph = map(LocalGraphInputs(sessions: [
            LocalSession(id: "root", agent: "codex", agentName: "Codex", state: "idle", folder: repo),
            LocalSession(id: "sub", agent: "cursor", agentName: "Cursor", state: "idle", folder: repo + "/web"),
        ]))
        XCTAssertEqual(graph.nodes.filter { $0.kind == .workspace }.map(\.id), ["ws:\(repo)"])
        XCTAssertEqual(edges(graph, .worksIn), ["conv:root>ws:\(repo)", "conv:sub>ws:\(repo)"])
        XCTAssertEqual(node(graph, "ws:\(repo)")?.usedBy, ["Codex", "Cursor"])
    }

    func testPlacesEveryNodeInTheClusterOfItsSourceTheSameEveryTime() {
        let source = MemorySourceView(id: "src_i", kind: .instructions, name: "shop", location: repo, project: repo)
        let cited = MemoryEvidenceView(ref: "CLAUDE.md#Top", document: "CLAUDE.md", source: "shop")
        let inputs = LocalGraphInputs(items: [item("m1", evidence: [cited])], sources: [source],
                                      sessions: [LocalSession(id: "s", agent: "codex", agentName: "Codex", title: "t", state: "idle")])
        let graph = map(inputs)
        XCTAssertEqual(graph, map(inputs))
        let groups = MemoryGroups.groups(graph, sources: [source])
        let layout = BrainClusters.layout(graph, groups: groups)
        XCTAssertEqual(layout, BrainClusters.layout(map(inputs), groups: groups))
        XCTAssertEqual(groups["m1"], .instructions)
        XCTAssertEqual(groups["conv:s"], .conversations)
        XCTAssertEqual(groups["ws:\(repo)"], .projects)
        XCTAssertEqual(layout.cluster["m1"], MemoryMaps.sourceId("shop"))
    }

    func testReadsTheSessionCardsOwnFields() {
        let card = SessionCard(sessionId: "s9", agent: nil, agentName: "Claude Code", task: "Ship it", focus: "  ", state: "open",
                               host: DisplayHost(cwd: "/Users/me/code/shop/web"))
        let session = LocalSession(card)
        XCTAssertEqual(session.agent, "Claude Code")
        XCTAssertEqual(session.title, "Ship it")
        XCTAssertEqual(session.folder, "/Users/me/code/shop/web")
    }

    func testPutsASessionInTheWorkspaceItsFolderIsInsideAndAFolderThatOnlySharesAPrefixInItsOwn() {
        let source = MemorySourceView(id: "src_i", kind: .instructions, name: "shop", location: repo, project: repo)
        let graph = map(LocalGraphInputs(sources: [source],
                                         sessions: [LocalSession(id: "in", agent: "codex", agentName: "Codex", state: "working", folder: repo + "/web"),
                                                    LocalSession(id: "out", agent: "codex", agentName: "Codex", state: "working", folder: repo + "-old")]))
        XCTAssertEqual(edges(graph, .worksIn), ["conv:in>ws:\(repo)", "conv:out>ws:\(repo)-old"])
        XCTAssertEqual(edges(graph, .within), ["src:shop>ws:\(repo)"])
        XCTAssertEqual(graph.nodes.first { $0.id == "ws:\(repo)" }?.label, "shop")
    }

    func testTheMostParticularWorkspaceHoldsAFolder() {
        XCTAssertEqual(LocalGraphs.workspaceHolding("/a/b/c", ["/a", "/a/b"]), "/a/b")
        XCTAssertEqual(LocalGraphs.workspaceHolding("/a/b", ["/a/b"]), "/a/b")
        XCTAssertNil(LocalGraphs.workspaceHolding("/a/bc", ["/a/b"]))
    }

    func testAnMcpSourceIsUsedByTheAgentsTheHubGivesItsServerTo() {
        let source = MemorySourceView(id: "src_m", kind: .mcp, name: "Mem", location: "mcp://memory-server")
        let folder = MemorySourceView(id: "src_f", kind: .markdown, name: "Notes", location: "/notes")
        let graph = map(LocalGraphInputs(sources: [source, folder],
                                         agents: [LocalAgent(kind: "claude-code", name: "Claude Code", mcpServers: ["memory-server"]),
                                                  LocalAgent(kind: "codex", name: "Codex", mcpServers: ["github"])]))
        XCTAssertEqual(node(graph, "src:Mem")?.usedBy, ["Claude Code"])
        XCTAssertEqual(node(graph, "src:Notes")?.usedBy, [])
        XCTAssertEqual(LocalGraphs.hubServer(source), "memory-server")
        XCTAssertNil(LocalGraphs.hubServer(folder))
    }

    func testAFactIsUsedByTheAgentThatSuggestedItAndARuleByTheAgentsItBinds() {
        let rule = MemoryRuleView(effect: "deny", actions: ["push"], agents: ["codex", "unknown"], reason: "r", sentence: "Never push")
        let graph = map(LocalGraphInputs(items: [item("m1", suggestedBy: "claude-code", rule: rule)],
                                         agents: [LocalAgent(kind: "claude-code", name: "Claude Code"), LocalAgent(kind: "codex", name: "Codex")]))
        XCTAssertEqual(node(graph, "m1")?.usedBy, ["Claude Code"])
        XCTAssertEqual(node(graph, "rule:m1")?.usedBy, ["Codex"])
    }

    func testAFactIsKeptForItsProjectOnlyWhereNoSourceItCitesAlreadyCarriesItThere() {
        let source = MemorySourceView(id: "src_i", kind: .instructions, name: "shop", location: repo, project: repo)
        let cited = MemoryEvidenceView(ref: "CLAUDE.md#Top", document: "CLAUDE.md", source: "shop")
        let graph = map(LocalGraphInputs(items: [item("carried", project: repo, evidence: [cited]), item("alone", project: repo)],
                                         sources: [source]))
        XCTAssertEqual(edges(graph, .within), ["alone>ws:\(repo)", "src:shop>ws:\(repo)"])
    }

    func testKeepsEveryMemoryLineAndListsASourceNothingCitesOnce() {
        let vault = MemorySourceView(id: "src_v", kind: .obsidian, name: "Vault", location: "/vault")
        let cited = MemoryEvidenceView(ref: "a.md#Top", document: "a.md", source: "Vault")
        let graph = map(LocalGraphInputs(items: [item("m1", evidence: [cited])], sources: [vault]))
        XCTAssertEqual(graph.nodes.filter { $0.kind == .source }.map(\.id), ["src:Vault"])
        XCTAssertEqual(edges(graph, .cites).count, 1)
        XCTAssertEqual(edges(graph, .heldIn).count, 1)
        XCTAssertEqual(Set(graph.nodes.map(\.id)).count, graph.nodes.count)
    }

    func testEveryLineJoinsTwoNodesOnTheMap() {
        let graph = map(LocalGraphInputs(items: [item("m1", project: "/gone", suggestedBy: "ghost")],
                                         sessions: [LocalSession(id: "s", agent: "codex", agentName: "Codex", state: "idle", folder: "/x")]))
        let ids = Set(graph.nodes.map(\.id))
        XCTAssertTrue(graph.edges.allSatisfy { ids.contains($0.from) && ids.contains($0.to) })
        XCTAssertEqual(edges(graph, .worksIn), ["conv:s>ws:/x"])
    }

    func testACallIsNamedForItsToolAndJoinedToItsConversationAndItsApp() {
        let call = MemoryCallView(via: "app", agent: "claude-code", sessionId: "s1", app: "github", tool: "GITHUB_LIST_ISSUES",
                                  at: "2026-10-31T09:00:00Z")
        let cited = MemoryEvidenceView(ref: "call_1", document: "call_1", source: "github", call: call)
        let graph = map(LocalGraphInputs(items: [item("m1", evidence: [cited])],
                                         agents: [LocalAgent(kind: "claude-code", name: "Claude Code")],
                                         sessions: [LocalSession(id: "s1", agent: "claude-code", agentName: "Claude Code", title: "Triage",
                                                                 state: "working")],
                                         apps: [LocalApp(slug: "github", name: "GitHub"), LocalApp(slug: "gmail", name: "Gmail")]))
        let document = MemoryMaps.documentId(source: "github", document: "call_1")
        XCTAssertEqual(node(graph, document)?.label, "GITHUB_LIST_ISSUES")
        XCTAssertEqual(node(graph, document)?.usedBy, ["Claude Code"])
        XCTAssertEqual(node(graph, "m1")?.usedBy, ["Claude Code"])
        XCTAssertTrue(edges(graph, .cites).contains("m1>\(document)"))
        XCTAssertTrue(edges(graph, .heldIn).contains("\(document)>app:github"))
        XCTAssertEqual(edges(graph, .reads), ["conv:s1>\(document)"])
        XCTAssertNil(node(graph, "app:gmail"))
    }

    func testADraggedProjectCarriesItsConversationsAndEachListsWhatItIsLinkedTo() {
        let graph = map(LocalGraphInputs(sessions: [LocalSession(id: "a", agent: "codex", agentName: "Codex", state: "idle", folder: repo),
                                                    LocalSession(id: "b", agent: "codex", agentName: "Codex", state: "idle", folder: repo)]))
        XCTAssertEqual(MemoryMaps.carriedWith(graph, "ws:\(repo)").sorted(), ["conv:a", "conv:b"])
        XCTAssertEqual(MemoryMaps.linked(graph, "conv:a").map(\.node.id), ["ws:\(repo)"])
        XCTAssertEqual(MemoryMaps.linked(graph, "ws:\(repo)").map(\.node.id), ["conv:a", "conv:b"])
        XCTAssertEqual(MemoryMaps.linked(graph, "ws:\(repo)").map(\.kind), [.worksIn, .worksIn])
    }
}
