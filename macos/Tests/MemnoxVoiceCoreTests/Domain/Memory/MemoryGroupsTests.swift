import XCTest

@testable import MemnoxVoiceCore

/// A piece takes the group of what it was read from, and the overlays count off the record: these check both, the
/// replay's timing and the filters.
final class MemoryGroupsTests: XCTestCase {
    static let repo = "/Users/me/code/shop"
    static let notes = MemorySourceView(id: "src_o", kind: .obsidian, name: "vault", location: "/vault",
                                        counts: MemorySourceCounts(candidate: 1, verified: 3))
    static let rules = MemorySourceView(id: "src_i", kind: .instructions, name: "shop", location: "/shop",
                                        counts: MemorySourceCounts(verified: 2, conflicting: 2))

    static func item(_ id: String, status: MemoryStatus = .verified, project: String? = nil, source: String? = nil,
                     rule: MemoryRuleView? = nil) -> MemoryItemView {
        let evidence = source.map { [MemoryEvidenceView(ref: "\(id).md#Top", document: "\(id).md", source: $0)] } ?? []
        return MemoryItemView(id: id, statement: "Statement \(id)", status: status, project: project, rule: rule,
                              evidence: evidence, createdAt: "2026-10-20T09:00:00Z")
    }

    static var graph: MemoryMap {
        let rule = MemoryRuleView(effect: "deny", actions: ["push"], reason: "r", sentence: "Never push")
        return LocalGraphs.map(LocalGraphInputs(items: [item("a", source: "vault"), item("b", source: "vault"),
                                                        item("c", status: .candidate, source: "shop", rule: rule),
                                                        item("d", project: repo), item("e")],
                                                sources: [notes, rules],
                                                sessions: [LocalSession(id: "s", agent: "codex", agentName: "Codex", title: "t",
                                                                        state: "idle", folder: repo)]),
                               kindLabel: { $0 })
    }

    func testAFactTakesTheGroupOfWhatItWasReadFromAndItsRuleFollowsIt() {
        let groups = MemoryGroups.groups(Self.graph, sources: [Self.notes, Self.rules])
        XCTAssertEqual(groups["a"], .notes)
        XCTAssertEqual(groups[MemoryMaps.sourceId("vault")], .notes)
        XCTAssertEqual(groups[MemoryMaps.documentId(source: "vault", document: "a.md")], .notes)
        XCTAssertEqual(groups["c"], .instructions)
        XCTAssertEqual(groups[MemoryMaps.ruleId("c")], .instructions)
        XCTAssertEqual(groups["d"], .projects)
        XCTAssertEqual(groups["e"], .unsourced)
        XCTAssertEqual(groups["conv:s"], .conversations)
    }

    func testAReplayFliesEachGroupInAfterTheOneBefore() {
        XCTAssertEqual(MemoryGroups.arrival(0, seconds: 0), 0)
        XCTAssertEqual(MemoryGroups.arrival(0, seconds: MemoryGroups.replayFlight), 1)
        XCTAssertEqual(MemoryGroups.arrival(1, seconds: MemoryGroups.replayStagger), 0)
        XCTAssertGreaterThan(MemoryGroups.arrival(0, seconds: 1), MemoryGroups.arrival(1, seconds: 1))
        XCTAssertEqual(MemoryGroups.arrival(3, seconds: MemoryGroups.replayLength(4)), 1)
        XCTAssertEqual(MemoryGroups.replayLength(0), MemoryGroups.replayFlight)
    }

    func testAttentionKeepsWhatNeedsLookingAtAndWhatItWasReadFrom() {
        let kept = MemoryGroups.attention(Self.graph)
        let ids = Set(kept.nodes.map(\.id))
        XCTAssertTrue(ids.contains("c"))
        XCTAssertTrue(ids.contains(MemoryMaps.ruleId("c")))
        XCTAssertTrue(ids.contains(MemoryMaps.documentId(source: "shop", document: "c.md")))
        XCTAssertFalse(ids.contains("a"))
        XCTAssertTrue(kept.edges.allSatisfy { ids.contains($0.from) && ids.contains($0.to) })
    }

    func testHidingAGroupTakesItsNodesAndTheirLinesOff() {
        let map = Self.graph
        let groups = MemoryGroups.groups(map, sources: [Self.notes, Self.rules])
        let shown = MemoryGroups.without(map, hidden: [.notes], groups: groups)
        XCTAssertFalse(shown.nodes.contains { groups[$0.id] == .notes })
        XCTAssertFalse(shown.edges.contains { groups[$0.from] == .notes || groups[$0.to] == .notes })
        XCTAssertEqual(MemoryGroups.without(map, hidden: [], groups: groups), map)
    }

    func testCountsTheLegendTheHeadlineAndTheGrowth() {
        let map = Self.graph
        let legend = MemoryGroups.legend(map, groups: MemoryGroups.groups(map, sources: [Self.notes, Self.rules]))
        XCTAssertEqual(legend.map(\.group), [.notes, .instructions, .conversations, .projects, .unsourced])
        XCTAssertEqual(legend.map(\.count).reduce(0, +), map.nodes.count)
        let stats = MemoryGroups.stats(map)
        XCTAssertEqual(stats.memories, 5)
        XCTAssertEqual(stats.sources, 2)
        XCTAssertEqual(stats.connections, map.edges.count)
        let growth = MemoryGroups.growth(map, sources: [Self.notes, Self.rules])
        XCTAssertEqual(growth.verified, 5)
        XCTAssertEqual(growth.total, 8)
        let fromMap = MemoryGroups.growth(map, sources: [])
        XCTAssertEqual(fromMap.verified, 4)
        XCTAssertEqual(fromMap.total, 5)
    }
}
