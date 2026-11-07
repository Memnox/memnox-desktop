import XCTest

@testable import MemnoxVoiceCore

/// The packing every cluster is built by, the names placed on the brain, the canvas search and the fit.
final class BrainPackingTests: XCTestCase {
    private func circles(_ count: Int) -> [PackCircle] {
        (0..<count).map { PackCircle(id: "c\($0)", radius: $0 < 3 ? 20 : ($0 % 4 == 0 ? 9 : 5)) }
            .sorted { $0.radius == $1.radius ? $0.id < $1.id : $0.radius > $1.radius }
    }

    func testNoTwoPackedCirclesLieOverEachOtherAndTheSameCirclesPackTheSameWay() {
        let each = circles(400)
        let packed = BrainPacking.pack(each, gap: 3)
        XCTAssertEqual(packed.spots.count, each.count)
        XCTAssertFalse(BrainPacking.overlaps(each, packed, gap: 3))
        XCTAssertEqual(packed, BrainPacking.pack(each, gap: 3))
        for (at, spot) in packed.spots.enumerated() {
            XCTAssertLessThanOrEqual(hypot(spot.x, spot.y) + each[at].radius, packed.radius + 1e-9)
        }
        XCTAssertEqual(BrainPacking.pack([], gap: 3).radius, 0)
    }

    func testAPackGrowsWithTheSquareRootOfWhatItHolds() {
        let small = BrainPacking.pack((0..<100).map { PackCircle(id: "a\($0)", radius: 5) }, gap: 3).radius
        let large = BrainPacking.pack((0..<400).map { PackCircle(id: "a\($0)", radius: 5) }, gap: 3).radius
        XCTAssertEqual(large / small, 2, accuracy: 0.35)
    }

    func testTheHeaviestNamesArePlacedAndOneThatWouldCoverAnotherIsLeftOff() {
        let names = [LabelCandidate(id: 0, x: 0, y: 0, width: 50, height: 12, weight: 1),
                     LabelCandidate(id: 1, x: 20, y: 4, width: 50, height: 12, weight: 5),
                     LabelCandidate(id: 2, x: 200, y: 0, width: 50, height: 12, weight: 0),
                     LabelCandidate(id: 3, x: 10, y: 2, width: 50, height: 12, weight: 0)]
        XCTAssertEqual(BrainLabels.place(names, always: []), [1, 2])
        XCTAssertEqual(BrainLabels.place(names, always: [3]), [3, 2], "the hovered name always shows and pushes the rest off")
    }

    func testTheCanvasSearchFindsEveryWordInAnyLayerLabelFirst() {
        let labels = ["Deploy checklist", "Release notes", "deploy", "Rule: never push"]
        let haystacks = [["Deploy checklist", "skill", "/a/SKILL.md"], ["Release notes", "about deploying"], ["deploy", "server"],
                         ["Rule: never push", "deny"]].map { BrainSearch.haystack($0) }
        let weights = [1.0, 3, 0, 0]
        XCTAssertEqual(BrainSearch.matches("DEPLOY", haystacks: haystacks, labels: labels, weights: weights), [0, 2, 1])
        XCTAssertEqual(BrainSearch.matches("deploy skill.md", haystacks: haystacks, labels: labels, weights: weights), [0])
        XCTAssertEqual(BrainSearch.matches("névér", haystacks: haystacks, labels: labels, weights: weights), [3])
        XCTAssertTrue(BrainSearch.matches("  ", haystacks: haystacks, labels: labels, weights: weights).isEmpty)
    }

    func testFitFramesTheNodesThemselvesWhereverTheyAre() {
        let points: [(x: Double, y: Double, radius: Double)] = [(900, 400, 10), (1100, 520, 10), (1000, 460, 30)]
        let size = (width: 800.0, height: 600.0)
        let camera = SurfaceCamera.fitted(points: points, size: size)
        XCTAssertEqual(camera.x, 1000, accuracy: 0.001)
        XCTAssertEqual(camera.y, 460, accuracy: 0.001)
        for point in points {
            let at = camera.onScreen((point.x, point.y), size: size)
            XCTAssertTrue((0...size.width).contains(at.x) && (0...size.height).contains(at.y))
        }
        XCTAssertEqual(SurfaceCamera.fitted(points: [], size: size), .atRest)
        let one = SurfaceCamera.fitted(points: [(5, 5, 1)], size: size)
        XCTAssertEqual(one.k, size.height * SurfaceCamera.fillDown / SurfaceCamera.leastSpan, accuracy: 0.001, "one mark is framed, not zoomed to the most")
    }
}

/// The logos a source wears and the avatar and profile a person has on the brain.
final class BrainFacesTests: XCTestCase {
    func testASourceWearsItsToolsOrItsAgentsLogoAndNothingWhereNoneIsKnown() {
        XCTAssertEqual(BrainFaces.brand(kind: .notionExport, name: "export", location: "/x"), .toolkit("notion"))
        XCTAssertEqual(BrainFaces.brand(kind: .mcp, name: "github-memory", location: nil), .toolkit("github"))
        XCTAssertEqual(BrainFaces.brand(kind: .instructions, name: "shop", location: "/Users/me/shop/CLAUDE.md"), .agent("claude"))
        XCTAssertEqual(BrainFaces.brand(kind: .instructions, name: "AGENTS.md", location: nil), .agent("codex"))
        XCTAssertNil(BrainFaces.brand(kind: .markdown, name: "notes", location: "/notes"))
    }

    func testAnAvatarTakesTheInitialsAndTheSameColourEveryTime() {
        XCTAssertEqual(BrainFaces.initials("Ada Lovelace"), "AL")
        XCTAssertEqual(BrainFaces.initials("ada lovelace byron"), "AL")
        XCTAssertEqual(BrainFaces.initials("linus"), "L")
        XCTAssertEqual(BrainFaces.initials("  "), "@")
        XCTAssertEqual(BrainFaces.colour(" Ada Lovelace ", count: 6), 2, "the console's faceInk for the same name")
        XCTAssertTrue((0..<BrainFaces.avatarColours).contains(BrainFaces.colour("Someone", count: BrainFaces.avatarColours)))
    }

    func testAProfileReadsWhatAPersonSaidOwnedAndConfirmedAndWhereItCameFrom() {
        let map = MemoryMap(nodes: [], edges: [MemoryMapEdge(from: "p", to: "d1", kind: .said), MemoryMapEdge(from: "d2", to: "p", kind: .names),
                                               MemoryMapEdge(from: "p", to: "d3", kind: .confirmed), MemoryMapEdge(from: "d1", to: "app:slack", kind: .pulledFrom),
                                               MemoryMapEdge(from: "d2", to: "app:slack", kind: .pulledFrom), MemoryMapEdge(from: "q", to: "d4", kind: .said)])
        let profile = BrainFaces.profile("p", in: map, label: "ada@shop.dev")
        XCTAssertEqual(profile.said, ["d1"])
        XCTAssertEqual(profile.named, ["d2"])
        XCTAssertEqual(profile.confirmed, ["d3"])
        XCTAssertEqual(profile.sources, ["app:slack"])
        XCTAssertEqual(profile.email, "ada@shop.dev")
        XCTAssertNil(BrainFaces.profile("p", in: map, label: "Ada").email)
    }
}

/// Where a picked node's detail card stands beside it, by the console's steps.
final class BrainCardTests: XCTestCase {
    private let card = (width: 320.0, height: 400.0)
    private let canvas = (width: 1000.0, height: 700.0)

    func testTheCardStandsOnTheNodesRightLevelWithIt() {
        let spot = BrainCard.place((200, 350), radius: 10, card: card, canvas: canvas)
        XCTAssertEqual(spot.side, .right)
        XCTAssertEqual(spot.x, 200 + 10 + BrainCard.gap)
        XCTAssertEqual(spot.y, 150)
        XCTAssertEqual(spot.pointer.x, 0)
        XCTAssertEqual(spot.pointer.y, 200, "the pointer is at the node's height")
        XCTAssertTrue(spot.visible)
    }

    func testNearTheRightEdgeItFlipsToTheLeftAndNearTheFootItStaysInside() {
        let spot = BrainCard.place((900, 680), radius: 10, card: card, canvas: canvas)
        XCTAssertEqual(spot.side, .left)
        XCTAssertEqual(spot.x + card.width, 900 - 10 - BrainCard.gap)
        XCTAssertEqual(spot.y + card.height, canvas.height - BrainCard.margin)
        XCTAssertEqual(spot.pointer.x, card.width)
        XCTAssertEqual(spot.pointer.y, card.height - BrainCard.pointerInset, "the pointer stops short of the corner")
    }

    func testOnANarrowCanvasItGoesBelowThenAboveThenIsPushedInside() {
        let narrow = (width: 400.0, height: 900.0)
        let below = BrainCard.place((200, 100), radius: 10, card: card, canvas: narrow)
        XCTAssertEqual(below.side, .below)
        XCTAssertEqual(below.y, 100 + 10 + BrainCard.gap)
        XCTAssertEqual(below.pointer.y, 0)
        XCTAssertEqual(below.pointer.x, 200 - below.x)
        XCTAssertEqual(BrainCard.place((200, 800), radius: 10, card: card, canvas: narrow).side, .above)
        let pushed = BrainCard.place((180, 250), radius: 10, card: card, canvas: (width: 400, height: 500))
        XCTAssertEqual(pushed.side, .right)
        XCTAssertEqual(pushed.x, 400 - card.width - BrainCard.margin)
        XCTAssertFalse(BrainCard.place((-5, 100), radius: 10, card: card, canvas: canvas).visible)
    }
}
