import Foundation

// How the layered brain moves, as pure curves of time, so the renderer only asks and every curve is tested headless.
// **Nothing here moves on its own**: each answers what a moment looks like, given how long ago something began, and with
// Reduce Motion every journey becomes a calm fade in place.

/// How far a layer has come in on an opening: how far out from the core it reaches, how much of its light it has,
/// and the extra glow of its bloom while it pops in.
public struct BrainReveal: Equatable, Sendable {
    public let reach: Double
    public let light: Double
    public let bloom: Double

    public static let settled = BrainReveal(reach: 1, light: 1, bloom: 0)
}

public enum BrainMotion {
    // The opening, about two and a half seconds: the core ignites, the memory bands sweep out one after another, the
    // rules ring draws itself round, and the applications drop in with a small overshoot.
    public static let skillsStart: TimeInterval = 0
    public static let skillsLength: TimeInterval = 0.6
    public static let memoryStart: TimeInterval = 0.45
    public static let ringStagger: TimeInterval = 0.12
    public static let ringLength: TimeInterval = 0.5
    public static let rulesStart: TimeInterval = 1.35
    public static let rulesLength: TimeInterval = 0.6
    public static let applicationsStart: TimeInterval = 1.85
    public static let applicationsLength: TimeInterval = 0.6
    /// The applications fall in from this share further out than where they land.
    public static let dropFrom = 1.25
    /// How far past its place the back ease swings before it settles.
    public static let overshoot = 1.70158
    /// A rule lights over this share of the ring's sweep once the sweep reaches it.
    public static let ruleEdge = 0.12
    /// With Reduce Motion everything fades in place over this long.
    public static let stillFade: TimeInterval = 0.6

    // Idle life.
    /// A dot breathes this much of its light over a period between these two, each on its own phase.
    public static let twinkleDepth = 0.28
    public static let twinkleSlowest: TimeInterval = 5.5
    public static let twinkleQuickest: TimeInterval = 2.5
    /// The core's stars shimmer deeper and quicker than the rest.
    public static let shimmerDepth = 0.5
    public static let shimmerPeriod: TimeInterval = 1.6
    /// The memory bands turn this many radians a second at the inner edge, each further band slower, every other one
    /// the other way.
    public static let bandSpin = 0.012
    public static let bandSlowing = 0.18
    /// A heartbeat of light leaves the core this often, crosses out past the outline over this long, and how far.
    public static let heartPeriod: TimeInterval = 4.5
    public static let heartTravel: TimeInterval = 1.8
    public static let heartReach = 1.2

    // Activity.
    /// A spark runs from an application's tile to the core over this long, at most this many at once, leaving a trail
    /// this share of its journey long drawn as this many fading beads.
    public static let sparkLife: TimeInterval = 1.6
    public static let mostSparks = 8
    public static let trailShare = 0.16
    public static let trailBeads = 6

    // Interaction.
    /// How long a hovered dot takes to swell, a picked area to bloom, and the dots to morph between views.
    public static let swellLength: TimeInterval = 0.25
    public static let bloomLength: TimeInterval = 0.5
    public static let morphLength: TimeInterval = 0.9
    /// The camera's spring: how fast it rings and how quickly the ringing dies, and when it counts as settled.
    public static let springPace = 11.0
    public static let springDamping = 0.78
    public static let springLength: TimeInterval = 0.8
    /// A flung 3D brain coasts on, its speed falling to a third over this long.
    public static let coastTime: TimeInterval = 0.9
    /// The 3D brain turns on its own this many radians a second.
    public static let orbSpin = 0.12
    /// The speed slider's range, and where it rests.
    public static let slowest = 0.25
    public static let quickest = 3.0
    public static let normalSpeed = 1.0

    private static let fullTurn = 2 * Double.pi
    private static let twinkleSalt: UInt64 = 91
    private static let paceSalt: UInt64 = 92

    /// How long the whole opening takes, so the clock can rest once it is over.
    public static var openingLength: TimeInterval { applicationsStart + applicationsLength }

    /// A share from 0 to 1 eased at both ends.
    public static func smooth(_ share: Double) -> Double {
        let t = clamp(share)
        return t * t * (3 - 2 * t)
    }

    /// A share eased out, quick then gentle.
    public static func easeOut(_ share: Double) -> Double {
        let t = clamp(share)
        return 1 - (1 - t) * (1 - t) * (1 - t)
    }

    /// A share eased out past its end and back, the small overshoot a drop lands with.
    public static func backOut(_ share: Double) -> Double {
        let t = clamp(share) - 1
        return 1 + (overshoot + 1) * t * t * t + overshoot * t * t
    }

    /// Where a layer stands on an opening this many seconds in; a memory band by its ring and a rule by how far round
    /// the ring it is, from 0 at the crown to 1.
    public static func opening(_ layer: BrainLayer, ring: Int = 0, around: Double = 0, seconds: Double, still: Bool) -> BrainReveal {
        if still { return BrainReveal(reach: 1, light: clamp(seconds / stillFade), bloom: 0) }
        switch layer {
        case .skills:
            let share = (seconds - skillsStart) / skillsLength
            return BrainReveal(reach: easeOut(share), light: clamp(share), bloom: share > 0 && share < 1 ? sin(Double.pi * share) : 0)
        case .memory:
            let share = (seconds - memoryStart - Double(ring) * ringStagger) / ringLength
            return BrainReveal(reach: easeOut(share), light: smooth(share), bloom: 0)
        case .rules:
            let sweep = (seconds - rulesStart) / rulesLength
            return BrainReveal(reach: 1, light: clamp((sweep - around) / ruleEdge), bloom: 0)
        case .applications:
            let share = (seconds - applicationsStart) / applicationsLength
            return BrainReveal(reach: dropFrom - (dropFrom - 1) * backOut(share), light: clamp(share * 2), bloom: 0)
        }
    }

    /// How far round the rules ring has drawn itself, 0 to 1.
    public static func ringDrawn(seconds: Double, still: Bool) -> Double {
        still ? 1 : clamp((seconds - rulesStart) / rulesLength)
    }

    /// A dot's light while idle, between one less the twinkle's depth and one, on its own pace and phase.
    public static func twinkle(_ id: String, seconds: Double) -> Double {
        let pace = twinkleQuickest + (twinkleSlowest - twinkleQuickest) * SurfaceOrbit.unit(id, salt: paceSalt)
        let phase = SurfaceOrbit.unit(id, salt: twinkleSalt)
        return 1 - twinkleDepth * (1 + sin((seconds / pace + phase) * fullTurn)) / 2
    }

    /// A core star's light, the same curve deeper and quicker.
    public static func shimmer(_ id: String, seconds: Double) -> Double {
        let phase = SurfaceOrbit.unit(id, salt: twinkleSalt)
        return 1 - shimmerDepth * (1 + sin((seconds / shimmerPeriod + phase) * fullTurn)) / 2
    }

    /// How far a memory band has turned, in radians: every other band the other way, and each further one slower.
    public static func spin(ring: Int, seconds: Double) -> Double {
        let way = ring % 2 == 0 ? 1.0 : -1.0
        return way * bandSpin * seconds / (1 + bandSlowing * Double(ring))
    }

    /// The heartbeat at a moment: how far out it has spread as a share of the silhouette, and how bright, nil between beats.
    public static func heartbeat(seconds: Double) -> (share: Double, strength: Double)? {
        let into = seconds.truncatingRemainder(dividingBy: heartPeriod)
        guard into >= 0, into < heartTravel else { return nil }
        let share = into / heartTravel
        return (easeOut(share) * heartReach, (1 - share) * (1 - share))
    }

    /// Where a spark is on its way from the outside to the core, 1 at its tile and 0 at the core, and how bright; nil
    /// once it has arrived. Still, it only glows at the core.
    public static func spark(age: Double, still: Bool) -> (along: Double, strength: Double)? {
        guard age >= 0, age < sparkLife else { return nil }
        let share = age / sparkLife
        if still { return (0, sin(Double.pi * share)) }
        return (1 - smooth(share), min(1, (1 - share) * 2))
    }

    /// How swollen a hovered dot is, 0 to 1, this long after the pointer came onto it.
    public static func swell(_ seconds: Double) -> Double { easeOut(seconds / swellLength) }

    /// How far a picked area has bloomed, 0 to 1.
    public static func bloom(_ seconds: Double) -> Double { smooth(seconds / bloomLength) }

    /// How far the dots have morphed from one view to the next, nil once they are there.
    public static func morph(_ seconds: Double) -> Double? {
        seconds < morphLength ? smooth(seconds / morphLength) : nil
    }

    /// The camera's spring from 0 to 1, ringing a little past and settling.
    public static func spring(_ seconds: Double) -> Double {
        guard seconds > 0 else { return 0 }
        guard seconds < springLength else { return 1 }
        let ringing = springPace * (1 - springDamping * springDamping).squareRoot()
        let decay = exp(-springDamping * springPace * seconds)
        return 1 - decay * (cos(ringing * seconds) + springDamping * springPace / ringing * sin(ringing * seconds))
    }

    /// How far a flung turn has coasted, in radians, a moment after the hand let go at this speed in radians a second.
    public static func coast(_ speed: Double, seconds: Double) -> Double {
        speed * coastTime * (1 - exp(-max(seconds, 0) / coastTime))
    }

    /// A speed from the slider, kept inside its range.
    public static func speed(_ wanted: Double) -> Double { min(max(wanted, slowest), quickest) }

    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
}

/// The idle clock, which runs at the speed the slider says and holds still while Motion is off.
public struct BrainClock: Equatable, Sendable {
    private var banked: Double = 0
    private var since: Date?
    public private(set) var speed = BrainMotion.normalSpeed

    public init() {}

    public var running: Bool { since != nil }

    public func seconds(at now: Date) -> Double {
        banked + (since.map { max(now.timeIntervalSince($0), 0) * speed } ?? 0)
    }

    public mutating func start(at now: Date) {
        guard since == nil else { return }
        since = now
    }

    public mutating func stop(at now: Date) {
        guard since != nil else { return }
        banked = seconds(at: now)
        since = nil
    }

    /// A new speed from now on, so what has already turned does not jump.
    public mutating func set(speed wanted: Double, at now: Date) {
        banked = seconds(at: now)
        if since != nil { since = now }
        speed = BrainMotion.speed(wanted)
    }
}

/// One spark on its way to the core: the angle it runs along and when it set off.
public struct BrainSpark: Equatable, Sendable {
    public let angle: Double
    public let started: Double
}

/// The sparks under way, the oldest let go once there are too many.
public struct BrainSparks: Equatable, Sendable {
    public private(set) var sparks: [BrainSpark] = []

    public init() {}

    public var busy: Bool { !sparks.isEmpty }

    public mutating func offer(angle: Double, at now: Double) {
        sparks.append(BrainSpark(angle: angle, started: now))
        if sparks.count > BrainMotion.mostSparks { sparks.removeFirst(sparks.count - BrainMotion.mostSparks) }
    }

    public mutating func advance(at now: Double) {
        sparks.removeAll { now - $0.started >= BrainMotion.sparkLife }
    }
}
