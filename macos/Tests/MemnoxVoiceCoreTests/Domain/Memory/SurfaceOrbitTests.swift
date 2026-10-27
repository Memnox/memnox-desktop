import XCTest

@testable import MemnoxVoiceCore

/// The cloud's turn, perspective and drift are arithmetic, so each is pinned here without drawing anything.
final class SurfaceOrbitTests: XCTestCase {
    private let tolerance = 1e-9

    func testFacingTheEyeAPointOnThePlaneIsSeenWhereItIsAtLifeSize() {
        let seen = SurfaceOrbit.seen(SurfacePoint(x: 120, y: -40, z: 0), turn: SurfaceTurn(yaw: 0, pitch: 0))
        XCTAssertEqual(seen.x, 120, accuracy: tolerance)
        XCTAssertEqual(seen.y, -40, accuracy: tolerance)
        XCTAssertEqual(seen.scale, 1, accuracy: tolerance)
        XCTAssertEqual(seen.depth, 0.5, accuracy: tolerance)
    }

    func testNearerIsLargerAndInFrontAndFurtherIsSmallerAndBehind() {
        let level = SurfaceTurn(yaw: 0, pitch: 0)
        let near = SurfaceOrbit.seen(SurfacePoint(x: 0, y: 0, z: -200), turn: level)
        let far = SurfaceOrbit.seen(SurfacePoint(x: 0, y: 0, z: 200), turn: level)
        XCTAssertGreaterThan(near.scale, 1)
        XCTAssertLessThan(far.scale, 1)
        XCTAssertGreaterThan(near.depth, far.depth)
    }

    func testAQuarterTurnSwingsTheSideOfTheCloudToItsFront() {
        let seen = SurfaceOrbit.seen(SurfacePoint(x: 300, y: 0, z: 0), turn: SurfaceTurn(yaw: Double.pi / 2, pitch: 0))
        XCTAssertEqual(seen.x, 0, accuracy: 1e-6)
        XCTAssertLessThan(seen.scale, 1)
    }

    func testAPointDraggedAcrossTheTurnedCloudLandsUnderThePointer() {
        let turn = SurfaceTurn(yaw: 0.8, pitch: -0.3)
        let start = SurfacePoint(x: 90, y: -30, z: 140)
        let before = SurfaceOrbit.seen(start, turn: turn)
        let moved = SurfaceOrbit.moved(start, by: (x: 25, y: -12), turn: turn)
        let after = SurfaceOrbit.seen(moved, turn: turn)
        XCTAssertEqual(after.x - before.x, 25, accuracy: 1e-6)
        XCTAssertEqual(after.y - before.y, -12, accuracy: 1e-6)
        XCTAssertEqual(after.depth, before.depth, accuracy: 1e-9)
    }

    func testAnIdsDrawIsTheSameEveryTimeAndItsBobStaysSmall() {
        XCTAssertEqual(SurfaceOrbit.unit("agent:codex", salt: 1), SurfaceOrbit.unit("agent:codex", salt: 1))
        XCTAssertNotEqual(SurfaceOrbit.unit("agent:codex", salt: 1), SurfaceOrbit.unit("agent:codex", salt: 2))
        for second in stride(from: 0.0, to: 20, by: 0.7) {
            let bob = SurfaceOrbit.drift("m1", seconds: second)
            XCTAssertLessThanOrEqual(hypot(bob.y, bob.z), SurfaceOrbit.driftReach + tolerance)
            XCTAssertEqual(bob.x, 0)
        }
    }

    func testTheEnvelopeHoldsTheCloudAtEveryTurn() {
        let place = Placed(id: "n", x: 200, y: 50, depth: 0.5, width: 40, label: "n", lift: -150)
        let envelope = SurfaceOrbit.envelope([place], pitch: SurfaceOrbit.restingPitch)
        let reach = envelope.map { abs($0.x) }.max() ?? 0
        for step in 0..<24 {
            let turn = SurfaceTurn(yaw: Double(step) / 24 * 2 * Double.pi, pitch: SurfaceOrbit.restingPitch)
            let seen = SurfaceOrbit.seen(SurfacePoint(x: place.x, y: place.y, z: place.lift), turn: turn)
            XCTAssertLessThanOrEqual(abs(seen.x), reach + 1e-6)
        }
    }

    func testALineIsTrimmedToEachMarksOwnRadiusAndDroppedWhereTheyOverlap() {
        let line = SurfaceOrbit.between((0, 0, 10), (100, 0, 20))
        XCTAssertEqual(line, SurfaceLine(x1: 10, y1: 0, x2: 80, y2: 0))
        XCTAssertNil(SurfaceOrbit.between((0, 0, 30), (40, 0, 20)))
    }

    func testThePauseFreezesTheTurnAndGoingAgainCarriesOnWithoutAJump() {
        var clock = OrbitClock()
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        XCTAssertEqual(clock.yaw(at: start), 0)
        clock.start(at: start)
        let paused = start.addingTimeInterval(10)
        clock.stop(at: paused)
        let frozen = clock.yaw(at: paused)
        XCTAssertEqual(frozen, 10 * SurfaceOrbit.spin, accuracy: tolerance)
        XCTAssertEqual(clock.yaw(at: paused.addingTimeInterval(60)), frozen, accuracy: tolerance)
        let again = paused.addingTimeInterval(60)
        clock.start(at: again)
        XCTAssertEqual(clock.yaw(at: again), frozen, accuracy: tolerance)
        XCTAssertEqual(clock.seconds(at: again.addingTimeInterval(5)), 15, accuracy: tolerance)
        clock.turn(to: 1)
        XCTAssertEqual(clock.yaw(at: again), frozen + 1, accuracy: tolerance)
    }

    func testAClockNeverStartedNeverMoves() {
        let clock = OrbitClock()
        XCTAssertFalse(clock.running)
        XCTAssertEqual(clock.seconds(at: Date()), 0)
    }

    func testFacingTurnsAPointToTheFrontByTheShortestWay() {
        let point = SurfacePoint(x: 120, y: -40, z: 300)
        let from = SurfaceTurn(yaw: 5 * Double.pi, pitch: -0.18)
        let turn = SurfaceOrbit.facing(point, from: from)
        XCTAssertEqual(turn.pitch, from.pitch)
        XCTAssertLessThanOrEqual(abs(turn.yaw - from.yaw), Double.pi + 1e-9, "never the long way round")
        let front = SurfaceOrbit.seen(point, turn: turn)
        XCTAssertEqual(front.x, 0, accuracy: 1e-6, "square to the eye")
        for step in 0..<36 {
            let other = SurfaceOrbit.seen(point, turn: SurfaceTurn(yaw: Double(step) / 36 * 2 * Double.pi, pitch: from.pitch))
            XCTAssertGreaterThanOrEqual(front.depth + 1e-9, other.depth, "nearest the eye")
        }
        XCTAssertEqual(SurfaceOrbit.facing(SurfacePoint(x: 0, y: 9, z: 0), from: from), from)
    }
}
