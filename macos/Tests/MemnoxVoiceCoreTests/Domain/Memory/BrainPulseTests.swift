import XCTest

@testable import MemnoxVoiceCore

/// A pulse answers only a change on the record, and they stay rare: pinned here against made up answers.
final class BrainPulseTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let before = "2026-01-01T09:00:00Z"
    private let after = "2027-03-01T09:00:00.250Z"

    private func fact(_ id: String, _ status: MemoryStatus = .candidate, created: String? = nil) -> MemoryItemView {
        MemoryItemView(id: id, statement: "Statement \(id)", status: status, createdAt: created ?? before)
    }

    private func source(_ id: String, read: String? = nil, verified: Int = 0) -> MemorySourceView {
        MemorySourceView(id: id, kind: .markdown, name: "Notes \(id)", location: "/tmp/\(id)", lastReadAt: read,
                         counts: MemorySourceCounts(verified: verified))
    }

    func testTheFirstLookOnlyRemembers() {
        var witness = BrainWitness()
        XCTAssertEqual(witness.observe(items: [fact("a")], sources: [source("s")], at: start), [])
    }

    func testAFactConfirmedStirsItsNode() {
        var witness = BrainWitness()
        _ = witness.observe(items: [fact("a")], sources: [], at: start)
        let stirs = witness.observe(items: [fact("a", .verified)], sources: [], at: start)
        XCTAssertEqual(stirs, [BrainStir(nodes: ["a"], kind: .memory)])
    }

    func testAFactLearnedSinceTheFirstLookStirsAndAnOldOneAFilterShowsDoesNot() {
        var witness = BrainWitness()
        _ = witness.observe(items: [fact("a")], sources: [], at: start)
        XCTAssertEqual(witness.observe(items: [fact("old", .verified)], sources: [], at: start), [])
        XCTAssertEqual(witness.observe(items: [fact("new", created: after)], sources: [], at: start),
                       [BrainStir(nodes: ["new"], kind: .memory)])
    }

    func testTheSameAnswerTwiceStirsNothing() {
        var witness = BrainWitness()
        _ = witness.observe(items: [fact("a")], sources: [source("s")], at: start)
        XCTAssertEqual(witness.observe(items: [fact("a")], sources: [source("s")], at: start), [])
    }

    func testASourceReadAgainOrTeachingMoreStirsItsNode() {
        var witness = BrainWitness()
        _ = witness.observe(items: [], sources: [source("s")], at: start)
        let read = witness.observe(items: [], sources: [source("s", read: after)], at: start)
        XCTAssertEqual(read, [BrainStir(nodes: ["src:Notes s", "src:s"], kind: .source)])
        XCTAssertEqual(witness.observe(items: [], sources: [source("s", read: after, verified: 1)], at: start).count, 1)
    }

    func testASourceAddedAfterTheFirstListStirs() {
        var witness = BrainWitness()
        _ = witness.observe(items: [], sources: [source("s")], at: start)
        XCTAssertEqual(witness.observe(items: [], sources: [source("s"), source("t")], at: start).map(\.kind), [.source])
    }

    func testWavesKeepACalmGapAndABurstBecomesOneWave() {
        var queue = BrainPulseQueue()
        let origin = SurfacePoint(x: 1, y: 2, z: 3)
        let later = SurfacePoint(x: 4, y: 5, z: 6)
        queue.offer(origin, at: 10)
        queue.offer(later, at: 10.5)
        queue.offer(origin, at: 11)
        XCTAssertEqual(queue.waves.count, 1)
        XCTAssertTrue(queue.busy)
        queue.advance(at: 10 + BrainPulses.calmGap, still: false)
        XCTAssertEqual(queue.waves.count, 1)
        XCTAssertEqual(queue.waves.last?.origin, origin)
        queue.advance(at: 20 + BrainPulses.waveLife, still: false)
        XCTAssertFalse(queue.busy)
    }

    func testAWaveSpreadsAndFadesAndStillItGlowsInPlace() {
        let early = BrainPulses.wave(age: 0.5, still: false)
        let late = BrainPulses.wave(age: 2, still: false)
        XCTAssertNotNil(early)
        XCTAssertGreaterThan(late?.reach ?? 0, early?.reach ?? 0)
        XCTAssertLessThan(late?.strength ?? 1, early?.strength ?? 0)
        XCTAssertNil(BrainPulses.wave(age: BrainPulses.waveLife, still: false))
        XCTAssertEqual(BrainPulses.wave(age: 0.5, still: true)?.reach, 0)
        XCTAssertNil(BrainPulses.wave(age: BrainPulses.stillLife, still: true))
    }

    func testABeadTravelsFromTheAgentToTheCoreThenRests() {
        var seen: [Double] = []
        var rested = false
        for step in 0..<100 {
            if let bead = BrainPulses.bead("agent:codex", seconds: Double(step) * BrainPulses.beat / 100, still: false) {
                seen.append(bead.along)
                XCTAssertTrue((0...1).contains(bead.along))
            } else {
                rested = true
            }
        }
        XCTAssertTrue(rested)
        XCTAssertFalse(seen.isEmpty)
        let moving = (0..<100).map { Double($0) * BrainPulses.beat / 100 }
            .first { BrainPulses.bead("agent:codex", seconds: $0, still: false) != nil } ?? 0
        XCTAssertEqual(BrainPulses.bead("agent:codex", seconds: moving, still: false)?.along ?? -1,
                       BrainPulses.bead("agent:codex", seconds: moving + BrainPulses.beat, still: false)?.along ?? -2, accuracy: 1e-6)
    }

    func testStillABeadDoesNotTravel() {
        for step in 0..<100 {
            if let bead = BrainPulses.bead("agent:codex", seconds: Double(step) / 10, still: true) {
                XCTAssertEqual(bead.along, 0)
                XCTAssertLessThanOrEqual(bead.strength, BrainPulses.stillGlow)
            }
        }
    }
}
