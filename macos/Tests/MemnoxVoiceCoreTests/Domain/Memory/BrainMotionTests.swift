import XCTest

@testable import MemnoxVoiceCore

/// The layered brain's motion as pure curves: the opening's order, the idle life, the sparks, the camera's spring, a
/// flung turn's coast, and the clock the speed slider sets.
final class BrainMotionTests: XCTestCase {
    func testTheOpeningIgnitesTheCoreThenSweepsTheBandsThenTheRingThenDropsTheApplications() {
        let early = BrainMotion.opening(.skills, seconds: BrainMotion.skillsLength / 2, still: false)
        XCTAssertGreaterThan(early.light, 0)
        XCTAssertGreaterThan(early.bloom, 0)
        XCTAssertEqual(BrainMotion.opening(.memory, ring: 0, seconds: BrainMotion.skillsLength / 2, still: false).light, 0)
        let inner = BrainMotion.opening(.memory, ring: 0, seconds: 0.7, still: false)
        let outer = BrainMotion.opening(.memory, ring: 6, seconds: 0.7, still: false)
        XCTAssertGreaterThan(inner.reach, outer.reach)
        let halfway = BrainMotion.rulesStart + BrainMotion.rulesLength / 2
        XCTAssertGreaterThan(BrainMotion.opening(.rules, around: 0.1, seconds: halfway, still: false).light, 0)
        XCTAssertEqual(BrainMotion.opening(.rules, around: 0.9, seconds: halfway, still: false).light, 0)
        XCTAssertEqual(BrainMotion.opening(.applications, seconds: 0, still: false).reach, BrainMotion.dropFrom, accuracy: 0.0001)
        let landing = (0...60).map { BrainMotion.opening(.applications, seconds: BrainMotion.applicationsStart + Double($0) / 60
                                                             * BrainMotion.applicationsLength, still: false).reach }
        XCTAssertLessThan(landing.min() ?? 1, 1, "it overshoots past its place")
        for layer in BrainLayer.allCases {
            XCTAssertEqual(BrainMotion.opening(layer, ring: 6, around: 1, seconds: BrainMotion.openingLength + 0.2, still: false),
                           BrainReveal.settled)
        }
        XCTAssertEqual(BrainMotion.openingLength, 2.45, accuracy: 0.1)
    }

    func testReduceMotionFadesEverythingInPlace() {
        let still = BrainMotion.opening(.applications, seconds: BrainMotion.stillFade / 2, still: true)
        XCTAssertEqual(still.reach, 1)
        XCTAssertEqual(still.light, 0.5, accuracy: 0.0001)
        XCTAssertEqual(BrainMotion.ringDrawn(seconds: 0, still: true), 1)
        XCTAssertEqual(BrainMotion.spark(age: 0.4, still: true)?.along, 0)
    }

    func testIdleLifeBreathesWithinItsDepthAndTheBandsTurnOppositeWays() {
        for step in 0..<200 {
            let light = BrainMotion.twinkle("dot", seconds: Double(step) / 10)
            XCTAssertGreaterThanOrEqual(light, 1 - BrainMotion.twinkleDepth - 0.0001)
            XCTAssertLessThanOrEqual(light, 1.0001)
        }
        XCTAssertNotEqual(BrainMotion.twinkle("one", seconds: 3), BrainMotion.twinkle("two", seconds: 3))
        XCTAssertGreaterThan(BrainMotion.spin(ring: 0, seconds: 10), 0)
        XCTAssertLessThan(BrainMotion.spin(ring: 1, seconds: 10), 0)
        XCTAssertGreaterThan(abs(BrainMotion.spin(ring: 0, seconds: 10)), abs(BrainMotion.spin(ring: 2, seconds: 10)))
        XCTAssertNotNil(BrainMotion.heartbeat(seconds: 0.5))
        XCTAssertNil(BrainMotion.heartbeat(seconds: BrainMotion.heartTravel + 0.1))
        let late = BrainMotion.heartbeat(seconds: BrainMotion.heartPeriod + BrainMotion.heartTravel * 0.9)
        XCTAssertGreaterThan(late?.share ?? 0, 1)
    }

    func testASparkRunsInFromItsTileToTheCoreAndAtMostSoManyTravel() {
        XCTAssertEqual(BrainMotion.spark(age: 0, still: false)?.along, 1)
        XCTAssertLessThan(BrainMotion.spark(age: BrainMotion.sparkLife * 0.9, still: false)?.along ?? 1, 0.1)
        XCTAssertNil(BrainMotion.spark(age: BrainMotion.sparkLife, still: false))
        var sparks = BrainSparks()
        for step in 0..<20 { sparks.offer(angle: Double(step), at: 0) }
        XCTAssertEqual(sparks.sparks.count, BrainMotion.mostSparks)
        XCTAssertEqual(sparks.sparks.last?.angle, 19)
        sparks.advance(at: BrainMotion.sparkLife)
        XCTAssertFalse(sparks.busy)
    }

    func testTheSpringRingsPastAndSettlesAndAFlingCoastsToAStop() {
        XCTAssertEqual(BrainMotion.spring(0), 0)
        XCTAssertEqual(BrainMotion.spring(BrainMotion.springLength), 1)
        let path = (1..<80).map { BrainMotion.spring(Double($0) / 100) }
        XCTAssertGreaterThan(path.max() ?? 0, 1, "it rings a little past")
        XCTAssertEqual(path.last ?? 0, 1, accuracy: 0.01)
        XCTAssertEqual(BrainMotion.coast(2, seconds: 0), 0)
        XCTAssertEqual(BrainMotion.coast(2, seconds: 60), 2 * BrainMotion.coastTime, accuracy: 0.0001)
        XCTAssertNil(BrainMotion.morph(BrainMotion.morphLength))
        XCTAssertEqual(BrainMotion.morph(BrainMotion.morphLength / 2) ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(BrainMotion.swell(BrainMotion.swellLength), 1)
        XCTAssertEqual(BrainMotion.bloom(0), 0)
    }

    func testTheClockRunsAtTheSlidersSpeedWithoutJumping() {
        var clock = BrainClock()
        let start = Date(timeIntervalSinceReferenceDate: 0)
        clock.start(at: start)
        XCTAssertEqual(clock.seconds(at: start.addingTimeInterval(2)), 2, accuracy: 0.0001)
        clock.set(speed: 2, at: start.addingTimeInterval(2))
        XCTAssertEqual(clock.seconds(at: start.addingTimeInterval(3)), 4, accuracy: 0.0001)
        clock.stop(at: start.addingTimeInterval(3))
        XCTAssertEqual(clock.seconds(at: start.addingTimeInterval(10)), 4, accuracy: 0.0001)
        clock.set(speed: 99, at: start.addingTimeInterval(10))
        XCTAssertEqual(clock.speed, BrainMotion.quickest)
    }
}
