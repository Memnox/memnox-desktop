import XCTest

@testable import MemnoxVoiceCore

/// The tour as a function of one playhead: each assembly opens in its own stretch, the teardown opens them all and
/// turns once, and every pose is home again by the end of the loop, so the loop never jumps.
final class BrainTourTests: XCTestCase {
    func testTheLoopStartsAndEndsAssembledSoItNeverJumps() {
        XCTAssertEqual(BrainTour.pose(at: 0), TourPose.assembled)
        let end = BrainTour.pose(at: BrainTour.length - 0.001)
        XCTAssertEqual(end.core + end.areas + end.rules + end.applications + end.apart, 0, accuracy: 0.0001)
        XCTAssertEqual(end.zoom, 1, accuracy: 0.0001)
        XCTAssertEqual(BrainTour.playhead(seconds: BrainTour.length + 3), 3, accuracy: 0.0001)
        XCTAssertEqual(BrainTour.playhead(seconds: -1), BrainTour.length - 1, accuracy: 0.0001)
    }

    func testEachAssemblyOpensAloneInItsOwnStretch() {
        for (part, open) in [(TourPart.core, \TourPose.core), (.areas, \.areas), (.rules, \.rules), (.applications, \.applications)] {
            let starts = BrainTour.sections.map(\.start)
            guard let at = BrainTour.sections.firstIndex(where: { $0.part == part }) else { return XCTFail("\(part) has no stretch") }
            let middle = (starts[at] + starts[at + 1]) / 2
            XCTAssertEqual(BrainTour.section(at: middle).part, part)
            let pose = BrainTour.pose(at: middle)
            XCTAssertEqual(pose[keyPath: open], 1, accuracy: 0.0001, "\(part) is open in its stretch")
            let others = pose.core + pose.areas + pose.rules + pose.applications - pose[keyPath: open]
            XCTAssertEqual(others, 0, accuracy: 0.0001, "nothing else is open while \(part) is")
        }
    }

    func testTheTeardownOpensEverythingAndTurnsOnce() {
        let pose = BrainTour.pose(at: 19.5)
        XCTAssertEqual(BrainTour.section(at: 19.5).part, .teardown)
        XCTAssertEqual(pose.apart, 1, accuracy: 0.0001)
        XCTAssertEqual(pose.areas, 1, accuracy: 0.0001)
        XCTAssertEqual(BrainTour.pose(at: 23).turn, 2 * Double.pi, accuracy: 0.0001)
    }

    func testAssembledLeavesEverySpotWhereItIs() {
        for layer in BrainLayer.allCases {
            let at = BrainTour.opened((120, -40), layer: layer, area: (80, -20), seed: 0.4, pose: .assembled)
            XCTAssertEqual(at.x, 120, accuracy: 0.0001)
            XCTAssertEqual(at.y, -40, accuracy: 0.0001)
        }
    }

    func testAnOpenAssemblyMovesAwayFromTheMiddle() {
        let middle = BrainOutline.middle
        let spot = (middle.x + 100, middle.y)
        var pose = TourPose.assembled
        pose.areas = 1
        let slid = BrainTour.opened(spot, layer: .memory, area: (middle.x + 60, middle.y), seed: 0.5, pose: pose)
        XCTAssertEqual(slid.x, spot.0 + BrainTour.areaSlide, accuracy: 0.0001)
        pose = .assembled
        pose.apart = 1
        let flown = BrainTour.opened(spot, layer: .applications, area: nil, seed: 0.5, pose: pose)
        XCTAssertGreaterThan(hypot(flown.x - middle.x, flown.y - middle.y), 100 + BrainTour.flightLeast - 0.001)
    }

    func testATrackEasesBetweenItsKeys() {
        let keys: [(Double, Double)] = [(0, 0), (2, 1)]
        XCTAssertEqual(BrainTour.sample(keys, -1), 0)
        XCTAssertEqual(BrainTour.sample(keys, 1), 0.5, accuracy: 0.0001)
        XCTAssertLessThan(BrainTour.sample(keys, 0.2), 0.1)
        XCTAssertEqual(BrainTour.sample(keys, 3), 1)
    }
}
