import XCTest

@testable import MemnoxVoiceCore

/// The brain in layers from the core out: these check the shrunk silhouettes, which layer each node is drawn in, the
/// memory sectors, the skills, rules and servers folded into the graph, and the Timeline.
final class BrainArmsTests: XCTestCase {
    private static var inputs: LocalGraphInputs {
        let rule = MemoryRuleView(effect: "deny", actions: ["push"], reason: "r", sentence: "Never push")
        let items = [MemoryGroupsTests.item("a", source: "vault"), MemoryGroupsTests.item("b", source: "vault"),
                     MemoryGroupsTests.item("c", status: .candidate, source: "shop", rule: rule),
                     MemoryGroupsTests.item("d", project: MemoryGroupsTests.repo), MemoryGroupsTests.item("e")]
        return LocalGraphInputs(items: items, sources: [MemoryGroupsTests.notes, MemoryGroupsTests.rules],
                                skills: [LocalSkill(name: "review", agents: ["claude"], servers: ["github"], updatedAt: "2026-10-01T09:00:00Z"),
                                         LocalSkill(name: "deploy", path: "/Users/me/.claude/skills/deploy/SKILL.md")],
                                standings: [LocalStanding(name: "no-push", sentence: "Never push to main", effect: "deny")],
                                servers: [LocalServer(name: "github", agents: ["claude"])])
    }

    private static var map: MemoryMap { LocalGraphs.map(inputs, kindLabel: { $0 }) }

    private func layout(_ map: MemoryMap) -> BrainArmsLayout {
        BrainArms.layout(map, groups: MemoryGroups.groups(map, sources: [MemoryGroupsTests.notes, MemoryGroupsTests.rules]))
    }

    func testTheShellAtFullSizeIsTheOutlineAndShrinksTowardTheCore() {
        let middle = BrainOutline.middle
        for step in 0..<36 {
            let angle = Double(step) / 36 * 2 * Double.pi
            let edge = BrainShell.point(angle, share: 0.98)
            XCTAssertTrue(BrainOutline.contains(x: edge.x, y: edge.y), "inside at \(angle)")
            let past = BrainShell.point(angle, share: 1.05)
            XCTAssertFalse(BrainOutline.contains(x: past.x, y: past.y), "outside at \(angle)")
            let half = BrainShell.point(angle, share: 0.5)
            XCTAssertEqual(hypot(half.x - middle.x, half.y - middle.y), BrainShell.reach(angle) / 2, accuracy: 0.001)
        }
        XCTAssertEqual(BrainShell.reach(-Double.pi / 2), BrainShell.reach(3 * Double.pi / 2), accuracy: 0.001)
    }

    func testFoldsSkillsRulesAndServersIntoTheGraphWithTheirOwnLines() {
        let map = Self.map
        let ids = Set(map.nodes.map(\.id))
        XCTAssertTrue(ids.contains(LocalGraphs.skillId("review")))
        XCTAssertTrue(ids.contains(LocalGraphs.standingId("no-push")))
        XCTAssertTrue(ids.contains(LocalGraphs.serverId("github")))
        XCTAssertTrue(map.edges.contains { $0.from == LocalGraphs.skillId("review") && $0.to == LocalGraphs.serverId("github") })
        XCTAssertEqual(map.nodes.first { $0.id == LocalGraphs.skillId("review") }?.at, "2026-10-01T09:00:00Z")
        XCTAssertEqual(LocalGraphs.skillPath(Self.inputs.skills, LocalGraphs.skillId("deploy")), "/Users/me/.claude/skills/deploy/SKILL.md")
        XCTAssertEqual(map.nodes.first { $0.id == "a" }?.at, "2026-10-20T09:00:00Z")
    }

    func testEachNodeIsDrawnInItsLayerAtItsLayersShare() {
        let map = Self.map
        let brain = layout(map)
        XCTAssertEqual(Set(brain.spots.keys), Set(map.nodes.map(\.id)))
        XCTAssertEqual(brain.spots[LocalGraphs.skillId("review")]?.layer, .skills)
        XCTAssertEqual(brain.spots[MemoryMaps.sourceId("shop")]?.layer, .skills)
        XCTAssertEqual(brain.spots[LocalGraphs.standingId("no-push")]?.layer, .rules)
        XCTAssertEqual(brain.spots[MemoryMaps.ruleId("c")]?.layer, .rules)
        XCTAssertEqual(brain.spots[LocalGraphs.serverId("github")]?.layer, .applications)
        XCTAssertEqual(brain.spots["a"]?.layer, .memory)
        let reaches = brain.reaches
        for spot in brain.spots.values {
            switch spot.layer {
            case .skills: XCTAssertLessThanOrEqual(spot.share, reaches[.skills] ?? 0)
            case .memory: XCTAssertLessThanOrEqual(spot.share, reaches[.memory] ?? 0)
            case .rules: XCTAssertEqual(spot.share, reaches[.rules] ?? 0)
            case .applications: XCTAssertGreaterThan(spot.share, reaches[.rules] ?? 0)
            }
        }
        XCTAssertGreaterThan(reaches[.rules] ?? 0, max(reaches[.skills] ?? 0, reaches[.memory] ?? 0), "the ring sits past what it rings")
        XCTAssertEqual(brain.coreLabel, "c.md")
    }

    func testMemoryIsSplitIntoASectorToEachAreaThatNeverOverlapAndHoldTheirPieces() {
        let map = Self.map
        let groups = MemoryGroups.groups(map, sources: [MemoryGroupsTests.notes, MemoryGroupsTests.rules])
        let brain = layout(map)
        XCTAssertGreaterThanOrEqual(brain.sectors.count, 2)
        for (left, right) in zip(brain.sectors, brain.sectors.dropFirst()) { XCTAssertLessThan(left.end, right.start) }
        let total = brain.sectors.reduce(0) { $0 + $1.end - $1.start } + BrainArms.sectorGap * Double(brain.sectors.count)
        XCTAssertEqual(total, 2 * Double.pi, accuracy: 0.0001)
        for (id, spot) in brain.spots where spot.layer == .memory {
            let sector = brain.sectors.first { $0.group == groups[id] }
            XCTAssertNotNil(sector)
            XCTAssertTrue(sector?.holds(spot.angle) ?? false, "\(id) in its sector")
        }
        let vault = MemoryMaps.sourceId("vault")
        XCTAssertEqual(brain.spots[vault]?.size, 1)
        XCTAssertEqual(Set(brain.areas.map(\.group)), Set(brain.sectors.map(\.group)))
        for (id, anchor) in brain.anchors {
            let area = brain.areas.first { $0.group == groups[id] }
            XCTAssertEqual(area?.x, anchor.x)
            XCTAssertEqual(area?.y, anchor.y)
        }
        XCTAssertEqual(brain.hub["a"], vault)
        XCTAssertEqual(brain.counts[vault], 4, "two facts and the two files they cite")
    }

    func testTheSameRecordDrawsTheSameBrainAndNoTwoPiecesLieOverEachOther() {
        let source = MemorySourceView(id: "src_n", kind: .markdown, name: "n", location: "/n")
        let items = (0..<200).map { MemoryGroupsTests.item("f\($0)", source: "n") }
        let map = LocalGraphs.map(LocalGraphInputs(items: items, sources: [source]), kindLabel: { $0 })
        let first = layout(map)
        XCTAssertEqual(first, layout(map))
        let rings = first.spots.values.filter { $0.layer == .memory }.map(\.ring)
        XCTAssertEqual(rings.min(), 0)
        XCTAssertLessThanOrEqual(rings.max() ?? 0, BrainArms.memoryRings - 1)
        let spots = first.spots.values.filter { $0.layer == .memory }.map { BrainArms.flat($0) }
        let least = 2 * BrainArms.pieceRoom + BrainArms.pieceGap - 1e-6
        for left in spots.indices {
            for right in spots.indices where right > left {
                XCTAssertGreaterThanOrEqual(hypot(spots[left].x - spots[right].x, spots[left].y - spots[right].y), least)
            }
        }
    }

    func testEveryAreaIsItsOwnClusterAndNoTwoClustersTouch() {
        let sources = ["n", "m", "k"].map { MemorySourceView(id: "src_\($0)", kind: .markdown, name: $0, location: "/\($0)") }
        let items = (0..<60).map { MemoryGroupsTests.item("f\($0)", source: "n") } + (0..<9).map { MemoryGroupsTests.item("g\($0)", source: "m") }
            + (0..<3).map { MemoryGroupsTests.item("h\($0)", project: "/p\($0)") }
        let map = LocalGraphs.map(LocalGraphInputs(items: items, sources: sources), kindLabel: { $0 })
        let brain = BrainArms.layout(map, groups: MemoryGroups.groups(map, sources: sources))
        XCTAssertGreaterThanOrEqual(brain.areas.count, 2)
        for left in brain.areas.indices {
            for right in brain.areas.indices where right > left {
                let a = brain.areas[left]
                let b = brain.areas[right]
                XCTAssertGreaterThanOrEqual(hypot(a.x - b.x, a.y - b.y), a.radius + b.radius, "\(a.group) clear of \(b.group)")
            }
        }
        let distances = brain.areas.map { hypot($0.x - BrainOutline.middle.x, $0.y - BrainOutline.middle.y) }
        XCTAssertGreaterThan(Set(distances.map { Int($0) }).count, 1, "the hubs are not all on one circle")
        for (id, spot) in brain.spots where spot.layer == .memory {
            guard let anchor = brain.anchors[id], let area = brain.areas.first(where: { $0.x == anchor.x && $0.y == anchor.y }) else {
                return XCTFail("\(id) has its area")
            }
            let at = BrainArms.flat(spot)
            XCTAssertLessThanOrEqual(hypot(at.x - area.x, at.y - area.y), area.radius + 1e-6)
        }
    }

    func testTheMemoryIndexStandsAtTheCoreAsAHub() {
        let node = MemoryMapNode(place: Placed(id: "doc:index", x: 0, y: 0, depth: 0, width: 1, label: "/Users/me/.claude/memory/MEMORY.md"),
                                 kind: .document, item: nil, status: nil, memoryKind: nil, tainted: false, detail: nil)
        let fact = MemoryMapNode(place: Placed(id: "fact", x: 0, y: 0, depth: 0, width: 1, label: "A fact"),
                                 kind: .memory, item: "fact", status: nil, memoryKind: nil, tainted: false, detail: nil)
        let map = MemoryMap(nodes: [node, fact], edges: [MemoryMapEdge(from: "fact", to: "doc:index", kind: .cites)])
        let brain = BrainArms.layout(map, groups: MemoryGroups.groups(map, sources: []))
        XCTAssertEqual(brain.index, "doc:index")
        XCTAssertEqual(brain.spots["doc:index"]?.layer, .skills)
        XCTAssertEqual(brain.spots["doc:index"]?.size, 1)
        XCTAssertNil(brain.coreLabel, "the index does not name the core")
    }

    func testTheApplicationsAreNumberedClockwiseAndSpacedEvenlyByLength() {
        let servers = (0..<12).map { LocalServer(name: "s\($0)") }
        let map = LocalGraphs.map(LocalGraphInputs(servers: servers), kindLabel: { $0 })
        let brain = layout(map)
        XCTAssertEqual(brain, layout(map))
        let ids = map.nodes.filter { $0.kind == .app }.map(\.id).sorted()
        XCTAssertEqual(ids.compactMap { brain.numbers[$0] }, Array(1...ids.count))
        let points = ids.compactMap { brain.spots[$0] }.map { BrainArms.flat($0) }
        var gaps: [Double] = []
        for (at, point) in points.enumerated() {
            let next = points[(at + 1) % points.count]
            gaps.append(hypot(next.x - point.x, next.y - point.y))
        }
        XCTAssertLessThan((gaps.max() ?? 0) / (gaps.min() ?? 1), 1.6, "evenly apart by length, not by angle")
    }

    func testAnAgeChipSaysDaysUpToAMonthAndNothingWithoutATime() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        XCTAssertNil(BrainArms.ageChip(nil, now: now))
        XCTAssertEqual(BrainArms.ageChip(now.addingTimeInterval(-60), now: now), "1D")
        XCTAssertEqual(BrainArms.ageChip(now.addingTimeInterval(-2.5 * BrainArms.day), now: now), "3D")
        XCTAssertEqual(BrainArms.ageChip(now.addingTimeInterval(-45 * BrainArms.day), now: now), "30D+")
    }

    func testRingsAreEvenlySpacedAndManyApplicationsTakeTwoRows() {
        let servers = (0..<40).map { LocalServer(name: "s\($0)") }
        let map = LocalGraphs.map(LocalGraphInputs(servers: servers), kindLabel: { $0 })
        let brain = layout(map)
        let shares = Set(brain.spots.values.map(\.share))
        let inner = shares.min() ?? 0
        XCTAssertEqual(shares, [inner, inner + BrainArms.applicationsRow])
    }

    func testAnOrbStaysOnItsShellWhateverItsLatitude() {
        let spot = BrainArmSpot(layer: .memory, angle: 0, share: 0.5, ring: 2, size: 0.3, latitude: 0)
        let flat = BrainArms.flat(spot)
        let middle = BrainOutline.middle
        let orb = BrainArms.orb(spot)
        XCTAssertEqual(orb.x, flat.x - middle.x, accuracy: 0.0001)
        XCTAssertEqual(orb.z, 0, accuracy: 0.0001)
        let lifted = BrainArms.orb(BrainArmSpot(layer: .memory, angle: 0, share: 0.5, ring: 2, size: 0.3, latitude: 1))
        XCTAssertEqual(lifted.x, orb.x, accuracy: 0.0001, "a latitude lifts a spot without squeezing it in")
        XCTAssertGreaterThan(lifted.z, 0)
    }

    func testTheTimelineLaysEachPieceByItsMomentInItsLayersLane() {
        let old = BrainTimeline.moment("2026-01-01T00:00:00Z")
        let new = BrainTimeline.moment("2026-10-01T00:00:00.500Z")
        XCTAssertNotNil(old)
        XCTAssertNotNil(new)
        let laid = BrainTimeline.layout(ids: ["a", "b", "c"], layers: [.memory, .skills, .memory], moments: [old, new, nil])
        XCTAssertEqual(laid.spots[0].x, -BrainOutline.halfLength, accuracy: 0.001)
        XCTAssertEqual(laid.spots[1].x, BrainOutline.halfLength, accuracy: 0.001)
        XCTAssertEqual(laid.undated.map(\.layer), [.memory])
        XCTAssertGreaterThan(laid.spots[2].y, laid.lanes.first { $0.layer == .memory }?.y ?? 0, "the undated row is at the lane's foot")
        XCTAssertEqual(laid.lanes.map(\.layer), [.skills, .memory])
        XCTAssertEqual(laid.ticks.count, BrainTimeline.tickCount)
        XCTAssertEqual(laid.ticks.first?.at, old)
        let lane = laid.lanes.first { $0.layer == .memory }?.y ?? 0
        XCTAssertLessThanOrEqual(abs(laid.spots[0].y - lane), BrainTimeline.laneHeight / 2)
    }

    func testWhatSaysNoTimeIsSpreadOverItsOwnLaneInEachLayer() {
        let ids = (0..<30).map { "r\($0)" } + (0..<5).map { "a\($0)" }
        let layers = Array(repeating: BrainLayer.rules, count: 30) + Array(repeating: BrainLayer.applications, count: 5)
        let laid = BrainTimeline.layout(ids: ids, layers: layers, moments: Array(repeating: nil, count: ids.count))
        let spots = laid.spots.map { "\($0.x),\($0.y)" }
        XCTAssertEqual(Set(spots).count, ids.count, "no two undated marks share a spot")
        for (at, layer) in layers.enumerated() {
            let lane = laid.lanes.first { $0.layer == layer }?.y ?? 0
            XCTAssertLessThanOrEqual(abs(laid.spots[at].y - lane), BrainTimeline.laneHeight / 2)
            XCTAssertLessThanOrEqual(abs(laid.spots[at].x), BrainOutline.halfLength)
        }
        let rules = laid.spots.prefix(30).map(\.x).sorted()
        XCTAssertEqual(rules.first ?? 0, -rules.last!, accuracy: 0.001, "the row is spread across the whole width")
        XCTAssertEqual(laid.undated.count, 2)
        XCTAssertEqual(laid, BrainTimeline.layout(ids: ids, layers: layers, moments: Array(repeating: nil, count: ids.count)))
    }

    func testDrawsEveryHubSkillAndEachFoundSkillNotBroughtInOnce() {
        let found = [FoundSkillView(id: "1", name: "lint", agent: "claude", kind: "skill", path: "/a/lint", tools: [], grant: "reads", imported: false),
                     FoundSkillView(id: "2", name: "lint", agent: "codex", kind: "skill", path: "/b/lint", tools: [], grant: "reads", imported: false),
                     FoundSkillView(id: "3", name: "kept", agent: "claude", kind: "skill", path: "/a/kept", tools: [], grant: "", imported: true),
                     FoundSkillView(id: "4", name: "helper", agent: "claude", kind: "agent", path: "/a/helper.md", tools: [], grant: "", imported: false)]
        let hub = SkillsHubView(skills: [], found: found, agents: [])
        let skills = LocalGraphs.skills(hub)
        XCTAssertEqual(skills.map(\.name), ["lint"])
        XCTAssertEqual(skills.first?.path, "/a/lint/SKILL.md")
        XCTAssertTrue(LocalGraphs.skills(nil).isEmpty)
    }
}
