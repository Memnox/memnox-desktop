import XCTest

@testable import MemnoxVoiceCore

/// Mirrors shared/tauri-core/test/memory-map.test.ts, so the Mac's map is drawn from the same record as the others.
final class MemoryMapTests: XCTestCase {
    private func evidence(_ document: String, stale: Bool = false, source: String = "Vault") -> MemoryEvidenceView {
        MemoryEvidenceView(ref: "\(document)#Top", document: document, heading: "Top", source: source, stale: stale)
    }

    private func item(_ id: String, kind: MemoryKind = .fact, rule: MemoryRuleView? = nil, duplicateOf: MemoryDuplicateView? = nil,
                      evidence: [MemoryEvidenceView] = []) -> MemoryItemView {
        MemoryItemView(id: id, kind: kind, statement: "Statement \(id)", subject: "subject", status: .verified, rule: rule,
                       duplicateOf: duplicateOf, evidence: evidence, createdAt: "2026-10-20T09:00:00Z")
    }

    private let vault = MemorySourceView(id: "src_vault", kind: .obsidian, name: "Vault", location: "/vault", watched: true)
    private let label: (String) -> String = { $0 == "obsidian" ? "Obsidian vault" : $0 }

    func testDrawsAFactTheDocumentItCitesAndTheSourceThatHoldsItEachLineAField() {
        let map = MemoryMaps.map([item("mem_1", evidence: [evidence("ops/releases.md")])], sources: [vault], kindLabel: label)
        let doc = MemoryMaps.documentId(source: "Vault", document: "ops/releases.md")
        let src = MemoryMaps.sourceId("Vault")
        XCTAssertEqual(map.nodes.map { "\($0.id) \($0.kind.rawValue)" }.sorted(), ["\(doc) document", "mem_1 memory", "\(src) source"])
        XCTAssertEqual(map.edges.map(\.kind.rawValue).sorted(), ["cites", "held_in"])
        XCTAssertEqual(map.nodes.first { $0.id == src }?.detail, "Obsidian vault")
        XCTAssertEqual(map.nodes.first { $0.id == doc }?.label, "releases.md")
    }

    func testHangsAFactThatCitesNothingOffNothing() {
        let map = MemoryMaps.map([item("mem_2")], sources: [], kindLabel: label)
        XCTAssertEqual(map.nodes.map(\.id), ["mem_2"])
        XCTAssertEqual(map.edges, [])
    }

    func testDrawsOneLineToADocumentCitedTwiceStaleOnlyWhenBothPassagesChanged() {
        let doc = MemoryMaps.documentId(source: "Vault", document: "a.md")
        let both = MemoryMaps.map([item("m", evidence: [evidence("a.md", stale: true), evidence("a.md", stale: true)])], sources: [], kindLabel: label)
        let one = MemoryMaps.map([item("m", evidence: [evidence("a.md", stale: true), evidence("a.md")])], sources: [], kindLabel: label)
        XCTAssertEqual(both.edges.filter { $0.to == doc }, [MemoryMapEdge(from: "m", to: doc, kind: .cites, stale: true)])
        XCTAssertEqual(one.edges.first { $0.to == doc }?.stale, false)
    }

    func testSharesOneDocumentBetweenTheFactsThatCiteItAndCarriesThemWhenItIsDragged() {
        let map = MemoryMaps.map([item("a", evidence: [evidence("x.md")]), item("b", evidence: [evidence("x.md")])], sources: [], kindLabel: label)
        XCTAssertEqual(map.nodes.filter { $0.kind == .document }.count, 1)
        XCTAssertEqual(MemoryMaps.carriedWith(map, MemoryMaps.documentId(source: "Vault", document: "x.md")).sorted(), ["a", "b"])
        XCTAssertEqual(MemoryMaps.carriedWith(map, "a"), [])
    }

    func testDrawsTheRuleAFactGovernsAndARestatementOnlyWhereBothFactsAreListed() {
        let rule = MemoryRuleView(effect: "ask", actions: ["git.push"], reason: "protected", sentence: "Ask before any agent pushes to main.")
        let map = MemoryMaps.map([
            item("r", kind: .rule, rule: rule),
            item("d", duplicateOf: MemoryDuplicateView(id: "r", statement: "x")),
            item("e", duplicateOf: MemoryDuplicateView(id: "gone", statement: "y")),
        ], sources: [], kindLabel: label)
        let node = map.nodes.first { $0.id == MemoryMaps.ruleId("r") }
        XCTAssertEqual(node?.kind, .rule)
        XCTAssertEqual(node?.label, rule.sentence)
        XCTAssertEqual(node?.detail, "ask")
        XCTAssertEqual(node?.item, "r")
        XCTAssertEqual(map.edges.map { [$0.from, $0.to, $0.kind.rawValue] }, [
            ["r", MemoryMaps.ruleId("r"), "governs"],
            ["d", "r", "restates"],
        ])
    }

    func testSeedsTheSamePictureFromTheSameRecordWhateverOrderItArrivesIn() {
        let items = [item("a", evidence: [evidence("x.md")]), item("b"), item("c", evidence: [evidence("y.md")])]
        XCTAssertEqual(MemoryMaps.map(items, sources: [], kindLabel: label), MemoryMaps.map(items.reversed(), sources: [], kindLabel: label))
    }

    func testWalksFactsFirstThenRulesDocumentsAndSources() {
        let map = MemoryMaps.map([item("a", evidence: [evidence("x.md")])], sources: [], kindLabel: label)
        XCTAssertEqual(MemoryMaps.walkOrder(map), ["a", MemoryMaps.documentId(source: "Vault", document: "x.md"), MemoryMaps.sourceId("Vault")])
    }

    func testSaysADocumentByItsLastPart() {
        XCTAssertEqual(MemoryMaps.documentLabel("ops/releases.md"), "releases.md")
        XCTAssertEqual(MemoryMaps.documentLabel("C:\\notes\\a.md"), "a.md")
        XCTAssertEqual(MemoryMaps.documentLabel("Staging-4f2a.md"), "Staging-4f2a.md")
    }

    func testSettlesToAStopRatherThanShiveringAndNeverMovesAPinnedNode() {
        let map = MemoryMaps.map([item("a", evidence: [evidence("x.md")]), item("b", evidence: [evidence("x.md")]), item("c")],
                                 sources: [], kindLabel: label)
        var bodies = SurfaceGeometry.seeded(map.nodes.map(\.place)).map { SurfaceBody(id: $0.id, x: $0.x, y: $0.y) }
        let pinned = bodies[0]
        var nodes: [String: Placed] = [:]
        for node in map.nodes { nodes[node.id] = node.place }
        let links = map.edges.map { SurfaceLink(from: $0.from, to: $0.to) }
        var heat = 1.0
        var fastest = Double.infinity
        for _ in 0..<400 {
            fastest = SurfaceSettling.step(&bodies, nodes: nodes, links: links, sized: 1, forces: .standard, pinned: pinned.id, heat: heat)
            heat -= heat * SurfaceSettling.heatFade
        }
        XCTAssertLessThan(fastest, 0.5)
        XCTAssertEqual(bodies[0].x, pinned.x)
        XCTAssertEqual(bodies[0].y, pinned.y)
    }

    func testStopsALineAtTheEdgeOfEachCardRatherThanItsMiddle() throws {
        let card = Placed(id: "a", x: 0, y: 0, depth: 0.5, width: 100, height: 40, label: "a")
        let other = Placed(id: "b", x: 300, y: 0, depth: 0.5, width: 100, height: 40, label: "b")
        let line = try XCTUnwrap(SurfaceGeometry.between(card, other, sized: 1))
        XCTAssertGreaterThan(line.x1, 50)
        XCTAssertLessThan(line.x2, 250)
    }

    func testZoomsAboutThePointerAndFitsTheWholeDrawingNoCloserThanLifeSize() {
        let size = (width: 800.0, height: 600.0)
        XCTAssertEqual(SurfaceCamera.atRest.zoomed(by: 2, at: (400, 300), size: size), SurfaceCamera(x: 0, y: 0, k: 2))
        let one = [Placed(id: "a", x: 0, y: 0, depth: 0.5, width: 40, label: "a")]
        XCTAssertEqual(SurfaceCamera.fitted(one, size: size, sized: 1).k, 1)
    }
}
