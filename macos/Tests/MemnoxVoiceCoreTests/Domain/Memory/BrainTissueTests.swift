import XCTest

@testable import MemnoxVoiceCore

/// The tissue the brain is drawn in: grains inside the silhouette, banded from the rim in, tumbling within their size,
/// and the pointer's lens fading smoothly to nothing at its edge.
final class BrainTissueTests: XCTestCase {
    func testTheGrainsFillTheSilhouetteAndStayInsideIt() {
        let grains = BrainTissue.grains
        XCTAssertGreaterThan(grains.count, 600)
        XCTAssertLessThan(grains.count, 3000)
        for grain in grains {
            XCTAssertLessThanOrEqual(grain.share, 1)
            XCTAssertGreaterThanOrEqual(grain.size, 0)
            XCTAssertLessThanOrEqual(grain.size, 1)
        }
        XCTAssertEqual(grains, BrainTissue.grains, "the same tissue on every launch")
    }

    func testTheRimIsGoldAndVioletAndTheCoreMostlyPale() {
        XCTAssertEqual(BrainTissue.band(share: 0.9, pick: 0.1), .gold)
        XCTAssertEqual(BrainTissue.band(share: 0.9, pick: 0.9), .violet)
        XCTAssertEqual(BrainTissue.band(share: 0.3, pick: 0.5), .pale)
        let rim = BrainTissue.grains.filter { $0.share >= BrainTissue.rimFrom }
        XCTAssertFalse(rim.isEmpty)
        XCTAssertTrue(rim.allSatisfy { $0.band == .gold || $0.band == .violet })
    }

    func testATetrahedronTumblesWithinItsSize() {
        for second in stride(from: 0.0, through: 30, by: 1.5) {
            let corners = BrainTissue.corners(spin: 0.37, seconds: second)
            XCTAssertEqual(corners.count, 4)
            for corner in corners { XCTAssertLessThanOrEqual(hypot(corner.x, corner.y), 1.0001) }
        }
        XCTAssertNotEqual(BrainTissue.corners(spin: 0.37, seconds: 0), BrainTissue.corners(spin: 0.37, seconds: 3))
        XCTAssertEqual(BrainTissue.edges.count, 6)
    }

    func testTheLensIsFullUnderThePointerAndNothingAtItsEdge() {
        XCTAssertEqual(BrainLens.pull(distance: 0), 1)
        XCTAssertEqual(BrainLens.pull(distance: BrainLens.radius), 0)
        XCTAssertEqual(BrainLens.pull(distance: BrainLens.radius * 2), 0)
        XCTAssertGreaterThan(BrainLens.pull(distance: BrainLens.radius * 0.25), BrainLens.pull(distance: BrainLens.radius * 0.75))
    }
}
