import Foundation

// The brain taken apart and put back together on a loop, the way a field simulator tours a machine: **everything is
// a function of one playhead**, so the pose of every layer, the camera's push and the turntable come from one time in
// seconds and scrubbing works both ways. Each layer moves as one rigid assembly: the core spreads, each memory area
// slides out from the core as a petal, the rules ring telescopes out and unscrews, the applications fly out, then every
// mark flies apart on its own line and snaps back before the turn ends. Nothing crossfades.

/// The assembly a stretch of the tour isolates.
public enum TourPart: String, CaseIterable, Sendable {
    case assembled
    case core
    case areas
    case rules
    case applications
    case teardown
    case reassembly
}

/// One stretch of the tour: when it starts and what it isolates.
public struct TourSection: Equatable, Sendable {
    public let start: Double
    public let part: TourPart
}

/// How far open each assembly is at a moment, from 0 in place to 1 fully out, with the camera's push and the turn.
public struct TourPose: Equatable, Sendable {
    public var core: Double
    public var areas: Double
    public var rules: Double
    public var applications: Double
    public var apart: Double
    /// The camera's zoom as times the fit, and the 3D brain's extra turn in radians.
    public var zoom: Double
    public var turn: Double

    public static let assembled = TourPose(core: 0, areas: 0, rules: 0, applications: 0, apart: 0, zoom: 1, turn: 0)
}

public enum BrainTour {
    /// One loop of the tour, in seconds.
    public static let length = 25.0

    public static let sections: [TourSection] = [
        TourSection(start: 0, part: .assembled),
        TourSection(start: 2.4, part: .core),
        TourSection(start: 6, part: .areas),
        TourSection(start: 10.2, part: .rules),
        TourSection(start: 13.6, part: .applications),
        TourSection(start: 16.8, part: .teardown),
        TourSection(start: 20.6, part: .reassembly),
        TourSection(start: 22.6, part: .assembled),
    ]

    /// Each assembly's keys, seconds against how far open, eased between keys. Opened once alone, then all at once in
    /// the teardown so they come back together with it.
    private static let core: [(Double, Double)] = [(2.6, 0), (3.6, 1), (5.4, 1), (6.2, 0), (17, 0), (18.2, 1), (20.8, 1), (22.2, 0)]
    private static let areas: [(Double, Double)] = [(6.2, 0), (7.4, 1), (9.6, 1), (10.4, 0), (17, 0), (18.2, 1), (20.8, 1), (22.2, 0)]
    private static let rules: [(Double, Double)] = [(10.4, 0), (11.4, 1), (13, 1), (13.8, 0), (17, 0), (18.2, 1), (20.8, 1), (22.2, 0)]
    private static let applications: [(Double, Double)] = [(13.8, 0), (14.8, 1), (16.2, 1), (17, 0), (18.2, 1), (20.8, 1), (22.2, 0)]
    private static let apart: [(Double, Double)] = [(16.9, 0), (18.4, 1), (20.6, 1), (22.2, 0)]
    /// The camera pushes in on the core, stands back for the petals and the ring, and further back for the teardown.
    private static let zoom: [(Double, Double)] = [(0, 1), (2.6, 1), (3.6, 1.6), (5.4, 1.6), (6.4, 0.86), (9.6, 0.86), (10.4, 0.82),
                                                   (13.8, 0.8), (16.8, 0.8), (17.8, 0.7), (21, 0.7), (22.6, 1)]
    /// The turntable: one whole turn through the teardown, landing before the parts are home.
    private static let turn: [(Double, Double)] = [(16.9, 0), (21.6, 2 * Double.pi)]

    /// How far each assembly travels at full open: the core's spread and the ring's and the tiles' reach as times
    /// where they sit, an area's slide and a teardown's flight in world points, and the ring's unscrewing turn.
    public static let coreSpread = 1.4
    public static let areaSlide = 150.0
    public static let ringOut = 0.32
    public static let ringTwist = 0.7
    public static let tilesOut = 0.42
    public static let flightLeast = 60.0
    public static let flightMore = 150.0
    /// A teardown's sideways stray, as a share of its flight, so the marks do not all fly on rays from the core.
    private static let stray = 0.35

    /// The playhead a tour started a while ago stands at, wrapped onto the loop.
    public static func playhead(seconds: Double) -> Double {
        let wrapped = seconds.truncatingRemainder(dividingBy: length)
        return wrapped < 0 ? wrapped + length : wrapped
    }

    public static func section(at seconds: Double) -> TourSection {
        let at = playhead(seconds: seconds)
        return sections.last { $0.start <= at } ?? sections[0]
    }

    /// Which stretch it is, counted from one, for the deck's count.
    public static func number(at seconds: Double) -> Int {
        let at = playhead(seconds: seconds)
        return sections.lastIndex { $0.start <= at }.map { $0 + 1 } ?? 1
    }

    public static func pose(at seconds: Double) -> TourPose {
        let at = playhead(seconds: seconds)
        return TourPose(core: sample(core, at), areas: sample(areas, at), rules: sample(rules, at),
                        applications: sample(applications, at), apart: sample(apart, at), zoom: sample(zoom, at),
                        turn: sample(turn, at))
    }

    /// A track at a moment: its first value before its first key, its last after its last, eased between.
    public static func sample(_ keys: [(Double, Double)], _ at: Double) -> Double {
        guard let first = keys.first else { return 0 }
        if at <= first.0 { return first.1 }
        for (before, after) in zip(keys, keys.dropFirst()) where at <= after.0 {
            guard after.0 > before.0 else { return after.1 }
            let share = (at - before.0) / (after.0 - before.0)
            return before.1 + (after.1 - before.1) * share * share * (3 - 2 * share)
        }
        return keys[keys.count - 1].1
    }

    /// Where a mark stands with its assembly opened: the core's marks spread from the middle, an area's marks slid out
    /// with their hub, the ring pushed out and turned, the tiles pushed out, then the teardown's flight on top.
    /// `seed` is the mark's own fraction from 0 to 1, which sets how far and which way it strays.
    public static func opened(_ spot: (x: Double, y: Double), layer: BrainLayer, area: (x: Double, y: Double)?, seed: Double,
                              pose: TourPose) -> (x: Double, y: Double) {
        let middle = BrainOutline.middle
        var at = spot
        switch layer {
        case .skills:
            at = scaled(at, about: middle, by: 1 + coreSpread * pose.core)
        case .memory:
            if let area {
                let out = unit(from: middle, to: area)
                at = (at.x + out.x * areaSlide * pose.areas, at.y + out.y * areaSlide * pose.areas)
            }
        case .rules:
            at = turned(scaled(at, about: middle, by: 1 + ringOut * pose.rules), about: middle, by: ringTwist * pose.rules)
        case .applications:
            at = scaled(at, about: middle, by: 1 + tilesOut * pose.applications)
        }
        return scattered(at, seed: seed, apart: pose.apart)
    }

    /// A spot flown out on its own line in the teardown: away from the middle, a little to one side, and further for
    /// some marks than others, so the brain comes apart as pieces rather than swelling.
    public static func scattered(_ spot: (x: Double, y: Double), seed: Double, apart: Double) -> (x: Double, y: Double) {
        guard apart > 0 else { return spot }
        let out = unit(from: BrainOutline.middle, to: spot, fallback: seed * 2 * Double.pi)
        let flight = (flightLeast + flightMore * seed) * apart
        let side = (seed - 0.5) * 2 * stray * flight
        return (spot.x + out.x * flight - out.y * side, spot.y + out.y * flight + out.x * side)
    }

    private static func scaled(_ spot: (x: Double, y: Double), about middle: (x: Double, y: Double), by factor: Double) -> (x: Double, y: Double) {
        (middle.x + (spot.x - middle.x) * factor, middle.y + (spot.y - middle.y) * factor)
    }

    private static func turned(_ spot: (x: Double, y: Double), about middle: (x: Double, y: Double), by angle: Double) -> (x: Double, y: Double) {
        let x = spot.x - middle.x
        let y = spot.y - middle.y
        return (middle.x + x * cos(angle) - y * sin(angle), middle.y + x * sin(angle) + y * cos(angle))
    }

    /// The way from one spot to another as a unit, or along an angle where they stand on one another.
    private static func unit(from: (x: Double, y: Double), to: (x: Double, y: Double), fallback: Double = 0) -> (x: Double, y: Double) {
        let x = to.x - from.x
        let y = to.y - from.y
        let length = hypot(x, y)
        guard length > .ulpOfOne else { return (cos(fallback), sin(fallback)) }
        return (x / length, y / length)
    }
}
