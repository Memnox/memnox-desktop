import XCTest

@testable import MemnoxVoiceCore

/// One cluster to each hub, every piece around its hub, and the clusters packed inside the brain without lying over one
/// another: these check the outline, the clusters, the packing and the sway.
final class BrainClustersTests: XCTestCase {
    private func layout(_ map: MemoryMap) -> BrainLayout {
        BrainClusters.layout(map, groups: MemoryGroups.groups(map, sources: [MemoryGroupsTests.notes, MemoryGroupsTests.rules]))
    }

    /// Many sources, each citing many facts, so the packing has to work for its room.
    private var crowded: MemoryMap {
        let sources = (0..<24).map { MemorySourceView(id: "src_\($0)", kind: .markdown, name: "notes \($0)", location: "/n\($0)") }
        let items = (0..<24).flatMap { source in
            (0..<(source % 7 + 1) * 6).map { MemoryGroupsTests.item("f\(source)_\($0)", source: "notes \(source)") }
        }
        return LocalGraphs.map(LocalGraphInputs(items: items, sources: sources), kindLabel: { $0 })
    }

    func testTheOutlineHoldsItsMiddleAndNothingFarOutside() {
        let middle = BrainOutline.middle
        XCTAssertTrue(BrainOutline.contains(x: middle.x, y: middle.y))
        XCTAssertFalse(BrainOutline.contains(x: BrainOutline.halfLength * 2, y: 0))
        XCTAssertFalse(BrainOutline.contains(x: 0, y: -BrainOutline.halfHeight * 2))
        XCTAssertGreaterThan(BrainOutline.area, 0)
        XCTAssertLessThan(BrainOutline.area, 4 * BrainOutline.halfLength * BrainOutline.halfHeight)
    }

    func testEachPieceJoinsTheClusterOfTheHubItWasReadFrom() {
        let map = MemoryGroupsTests.graph
        let brain = layout(map)
        let vault = MemoryMaps.sourceId("vault")
        XCTAssertEqual(brain.cluster["a"], vault)
        XCTAssertEqual(brain.cluster[MemoryMaps.documentId(source: "vault", document: "a.md")], vault)
        XCTAssertEqual(brain.cluster[MemoryMaps.ruleId("c")], MemoryMaps.sourceId("shop"))
        XCTAssertEqual(brain.cluster["d"], "ws:\(MemoryGroupsTests.repo)")
        XCTAssertEqual(brain.cluster["e"], BrainClusters.looseId(.unsourced))
        XCTAssertNil(brain.clusters.first { $0.id == BrainClusters.looseId(.unsourced) }?.hub)
        XCTAssertEqual(brain.prominence[vault], 1)
        XCTAssertLessThan(brain.prominence["a"] ?? 1, 1)
        XCTAssertEqual(Set(brain.spots.keys), Set(map.nodes.map(\.id)))
    }

    func testAPersonIsAHubOnlyOnceManyLinesNameThem() {
        let person = LocalGraphs.round("p", "Ana", .person)
        XCTAssertTrue(BrainClusters.isHub(person, degree: BrainClusters.personHub))
        XCTAssertFalse(BrainClusters.isHub(person, degree: BrainClusters.personHub - 1))
        XCTAssertFalse(BrainClusters.isHub(LocalGraphs.round("m", "fact", .memory), degree: 99))
    }

    func testEveryPieceSitsWithinItsClusterAndTheClustersInsideTheBrainApart() {
        let map = crowded
        let brain = layout(map)
        XCTAssertEqual(brain, layout(map))
        let byId = Dictionary(brain.clusters.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (id, spot) in brain.spots {
            guard let cluster = brain.cluster[id].flatMap({ byId[$0] }) else { return XCTFail(id) }
            XCTAssertLessThanOrEqual(hypot(spot.x - cluster.x, spot.y - cluster.y), cluster.radius + 1e-6, id)
        }
        for cluster in brain.clusters {
            XCTAssertTrue(BrainOutline.contains(x: cluster.x, y: cluster.y), cluster.id)
        }
        for (index, left) in brain.clusters.enumerated() {
            for right in brain.clusters.dropFirst(index + 1) {
                XCTAssertGreaterThanOrEqual(hypot(left.x - right.x, left.y - right.y), left.radius + right.radius, "\(left.id) \(right.id)")
            }
        }
    }

    func testABiggerClusterHoldsMoreAndTheSwayStaysWithinItsReach() {
        XCTAssertLessThan(BrainClusters.radius(holding: 1), BrainClusters.radius(holding: 40))
        XCTAssertEqual(BrainClusters.radius(holding: 0), BrainClusters.clusterLeast)
        for second in stride(from: 0.0, to: BrainClusters.swayPeriod, by: 1) {
            XCTAssertLessThanOrEqual(abs(BrainClusters.sway(second)), BrainClusters.swayReach + 1e-9)
        }
        XCTAssertEqual(BrainClusters.sway(0), 0, accuracy: 1e-9)
    }
}
