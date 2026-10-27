import XCTest

@testable import MemnoxVoiceCore

/// The workspace's live graph on the local graph: each tool joins this Mac's app of that slug, what arrived wears its
/// tool and its count, people and bots keep apart, every line is one the runtime sent, the status chip narrows only the
/// decisions, and the live picture stands in for the saved facts wherever the runtime answered it.
final class WorkspaceLiveGraphTests: XCTestCase {
    private func map(_ inputs: LocalGraphInputs) -> MemoryMap {
        LocalGraphs.map(inputs, kindLabel: { $0 })
    }

    private func node(_ map: MemoryMap, _ id: String) -> MemoryMapNode? {
        map.nodes.first { $0.id == id }
    }

    private func edges(_ map: MemoryMap, _ kind: MemoryLinkKind) -> [String] {
        map.edges.filter { $0.kind == kind }.map { "\($0.from)>\($0.to)" }.sorted()
    }

    private let live = WorkspaceGraphView(
        nodes: [
            WorkspaceGraphNode(id: "source:slack", kind: .source, label: "slack", tool: "slack", weight: 2),
            WorkspaceGraphNode(id: "item:ev1", kind: .document, label: "Beta on Monday", tool: "slack",
                               href: "https://acme.slack.com/archives/C1/p1", excerpt: "We ship the beta on Monday.",
                               saidBy: "Ana Lima", count: 21, weight: 3),
            WorkspaceGraphNode(id: "person:p1", kind: .person, label: "Ana Lima", weight: 1),
            WorkspaceGraphNode(id: "handle:github:dependabot", kind: .bot, label: "dependabot", tool: "github", count: 40),
            WorkspaceGraphNode(id: "fact:f1", kind: .decision, label: "payments", href: "https://linear.app/acme/issue/PAY-1",
                               statement: "Payments retry three times.", status: .verified, weight: 1),
            WorkspaceGraphNode(id: "candidate:c1", kind: .candidate, label: "beta", statement: "Ship the beta on Monday.",
                               status: .candidate, untrusted: true),
        ],
        links: [
            WorkspaceGraphLink(from: "source:slack", to: "item:ev1", kind: .carries),
            WorkspaceGraphLink(from: "person:p1", to: "item:ev1", kind: .said),
            WorkspaceGraphLink(from: "fact:f1", to: "item:ev1", kind: .readFrom),
            WorkspaceGraphLink(from: "candidate:c1", to: "source:slack", kind: .readFrom),
            WorkspaceGraphLink(from: "person:p1", to: "nowhere", kind: .mentions),
        ],
        withheld: 2, source: .live, readAt: "2026-11-01T09:00:00Z")

    func testDrawsEachToolAsTheAppThisMacKnowsAndWhatArrivedWithItsToolAndCount() {
        let graph = map(LocalGraphInputs(apps: [LocalApp(slug: "slack", name: "Slack HQ")], workspaceGraph: live))
        XCTAssertEqual(node(graph, "app:slack")?.label, "Slack HQ")
        XCTAssertEqual(node(graph, "app:slack")?.home, .workspace)
        let arrived = node(graph, "wsg:item:ev1")
        XCTAssertEqual(arrived?.kind, .document)
        XCTAssertEqual(arrived?.mark, "slack")
        XCTAssertEqual(arrived?.count, 21)
        XCTAssertEqual(arrived?.live?.saidBy, "Ana Lima")
        XCTAssertEqual(node(graph, "wsg:person:p1")?.kind, .person)
        XCTAssertEqual(node(graph, "wsg:handle:github:dependabot")?.live?.nodeKind, .bot)
        XCTAssertEqual(node(graph, "wsg:fact:f1")?.label, "Payments retry three times.")
        XCTAssertEqual(node(graph, "wsg:candidate:c1")?.tainted, true)
    }

    func testDrawsOnlyTheLinesTheRuntimeSentTurnedToReadAsTheMapReads() {
        let graph = map(LocalGraphInputs(workspaceGraph: live))
        XCTAssertEqual(edges(graph, .heldIn), ["wsg:item:ev1>app:slack"])
        XCTAssertEqual(edges(graph, .said), ["wsg:person:p1>wsg:item:ev1"])
        XCTAssertEqual(edges(graph, .cites), ["wsg:fact:f1>wsg:item:ev1"])
        // A line to a tool is where it was pulled from, and a decision's link host names its tool too.
        XCTAssertEqual(edges(graph, .pulledFrom), ["wsg:candidate:c1>app:slack", "wsg:fact:f1>app:linear"])
        XCTAssertEqual(edges(graph, .names), [])
    }

    func testTheStatusChipNarrowsTheDecisionsAndLeavesWhatArrived() {
        let verified = map(LocalGraphInputs(workspaceGraph: live, workspaceStatus: .verified))
        XCTAssertNotNil(node(verified, "wsg:fact:f1"))
        XCTAssertNil(node(verified, "wsg:candidate:c1"))
        XCTAssertNotNil(node(verified, "wsg:item:ev1"))

        let candidates = map(LocalGraphInputs(workspaceGraph: live, workspaceStatus: .candidate))
        XCTAssertNil(node(candidates, "wsg:fact:f1"))
        XCTAssertNotNil(node(candidates, "wsg:candidate:c1"))

        let rejected = map(LocalGraphInputs(workspaceGraph: live, workspaceStatus: .rejected))
        XCTAssertTrue(rejected.nodes.allSatisfy { $0.kind != .decision })
        XCTAssertNotNil(node(rejected, "wsg:person:p1"))
    }

    func testTheLivePictureStandsInForTheSavedFacts() {
        let saved = WorkspaceMemoryView(facts: [WorkspaceFact(id: "f9", statement: "Old.")], syncedAt: "2026-10-30T12:00:00Z")
        let graph = map(LocalGraphInputs(workspace: saved, workspaceGraph: live))
        XCTAssertNil(node(graph, "wsm:f9"))
        XCTAssertNotNil(node(graph, "wsg:fact:f1"))
        // With no live picture the saved facts are drawn, and the chip narrows them the same way.
        let alone = map(LocalGraphInputs(workspace: saved, workspaceStatus: .candidate))
        XCTAssertNil(node(alone, "wsm:f9"))
        XCTAssertNotNil(node(map(LocalGraphInputs(workspace: saved)), "wsm:f9"))
    }

    func testCarriesTheRecordWeightSoTheHeavyOnesAreNamed() {
        let graph = map(LocalGraphInputs(workspaceGraph: live))
        XCTAssertEqual(node(graph, "wsg:item:ev1")?.weight, 3)
        XCTAssertTrue(MapNames.named(graph, most: 1).contains("wsg:item:ev1"))
    }
}

/// Which names the map writes, and how short.
final class MapNamesTests: XCTestCase {
    private func place(_ id: String, weight: Int = 0) -> MemoryMapNode {
        var node = MemoryMapNode(place: Placed(id: id, x: 0, y: 0, depth: 0, width: 1, label: id), kind: .document, item: nil,
                                 status: nil, memoryKind: nil, tainted: false, detail: nil)
        node.weight = weight
        return node
    }

    func testNamesTheHeaviestByWeightOrLinesWithTiesByIdAndNamesWhatIsPointedAt() {
        let map = MemoryMap(nodes: [place("a"), place("b", weight: 5), place("c"), place("d")],
                            edges: [MemoryMapEdge(from: "c", to: "a", kind: .cites), MemoryMapEdge(from: "c", to: "d", kind: .cites)])
        let named = MapNames.named(map, most: 2)
        XCTAssertEqual(named, ["b", "c"])
        XCTAssertTrue(MapNames.shows("a", named: named, hovered: "a", selected: nil, zoomedIn: false))
        XCTAssertTrue(MapNames.shows("d", named: named, hovered: nil, selected: "d", zoomedIn: false))
        XCTAssertFalse(MapNames.shows("b", named: named, hovered: nil, selected: nil, zoomedIn: false))
        XCTAssertTrue(MapNames.shows("b", named: named, hovered: nil, selected: nil, zoomedIn: true))
        XCTAssertFalse(MapNames.shows("a", named: named, hovered: nil, selected: nil, zoomedIn: true))
    }

    func testCutsALongNameOnAWordWithAnEllipsis() {
        XCTAssertEqual(MapNames.short("  Beta on Monday  "), "Beta on Monday")
        XCTAssertEqual(MapNames.short("We ship the beta on Monday after review", longest: 20), "We ship the beta on…")
        XCTAssertEqual(MapNames.short("Supercalifragilisticexpialidocious", longest: 10), "Supercalif…")
    }
}

/// What the page says about the live graph.
final class WorkspaceLiveLinesTests: XCTestCase {
    func testSaysWhereThePictureCameFrom() {
        XCTAssertEqual(WorkspaceLiveLines.sourceLine(WorkspaceGraphView(source: .live)), "Read live from your workspace")
        XCTAssertEqual(WorkspaceLiveLines.sourceLine(WorkspaceGraphView(source: .saved, fallback: .unreachable)),
                       "Showing saved facts, the cloud could not be reached.")
        XCTAssertEqual(WorkspaceLiveLines.sourceLine(WorkspaceGraphView(source: .saved, fallback: .refused)),
                       "Showing saved facts, your workspace did not answer this Mac.")
        XCTAssertNil(WorkspaceLiveLines.sourceLine(WorkspaceGraphView(source: .saved, fallback: .notJoined)))
        XCTAssertEqual(WorkspaceLiveLines.emptyLine(WorkspaceGraphView(source: .live)), "Your workspace has taken nothing in yet.")
        XCTAssertNil(WorkspaceLiveLines.emptyLine(WorkspaceGraphView(source: .saved, fallback: .unreachable)))
    }

    func testSaysWhoSaidItThroughWhichToolWhenAndHowOften() {
        let node = WorkspaceGraphNode(id: "item:ev1", kind: .document, label: "Beta", tool: "slack",
                                      href: "https://acme.slack.com/p1", saidBy: "Ana Lima", at: "2026-10-31T08:00:00Z", count: 21)
        let rows = Dictionary(WorkspaceLiveLines.rows(node).map { ($0.0, $0.1) }, uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(rows["Said by"], "Ana Lima")
        XCTAssertEqual(rows["Tool"], "Slack")
        XCTAssertEqual(rows["When"], "2026-10-31")
        XCTAssertEqual(rows["Count"], "Said 21 times")
        XCTAssertEqual(WorkspaceLiveLines.link(node)?.absoluteString, "https://acme.slack.com/p1")
        XCTAssertNil(WorkspaceLiveLines.link(WorkspaceGraphNode(id: "x", kind: .document, label: "x", href: "http://plain")))
        XCTAssertEqual(WorkspaceLiveLines.badge(21), "×21")
    }

    func testDrawsInitialsForAPersonWithNoPicture() {
        XCTAssertEqual(WorkspaceLiveLines.initials("Ana Lima"), "AL")
        XCTAssertEqual(WorkspaceLiveLines.initials("cara"), "C")
        XCTAssertEqual(WorkspaceLiveLines.initials("jean.paul.sartre"), "JP")
    }
}
