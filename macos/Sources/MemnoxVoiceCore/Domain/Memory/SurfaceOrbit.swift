import Foundation

// The map looked at in three dimensions: the settled drawing is the plane, each node floats its lift off it, and the
// whole cloud turns about the vertical axis through the middle. **Only the looking turns**: the forces still settle the
// plane, so turning never stirs the layout, and every step here is arithmetic, so it is tested headless.

/// Which way the cloud is turned: about the vertical axis, then tipped toward the viewer.
public struct SurfaceTurn: Equatable, Sendable {
    public var yaw: Double
    public var pitch: Double

    public init(yaw: Double, pitch: Double) {
        self.yaw = yaw
        self.pitch = pitch
    }
}

/// One node as it is seen: where it lands on the plane the camera looks at, how big perspective draws it, and how near.
public struct SurfaceSeen: Equatable, Sendable {
    public let x: Double
    public let y: Double
    /// Perspective's scale: over 1 in front of the middle, under 1 behind it.
    public let scale: Double
    /// 0 at the back of the cloud and 1 at the front, for stacking and dimming.
    public let depth: Double
}

/// A point in the cloud, in world points.
public struct SurfacePoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public enum SurfaceOrbit {
    /// How far the eye stands from the middle of the cloud, in world points: far enough that the front is not huge.
    public static let focal = 1700.0
    /// How deep the cloud is taken to be when depth is said from 0 to 1.
    public static let reach = 520.0
    /// Looking a little down on the cloud, so its top and its bottom read as near and far.
    public static let restingPitch = -0.18
    /// How far a drag may tip it either way, short of looking straight down.
    public static let pitchLimit = 0.9
    /// A full turn every two minutes: slow enough to read the names, quick enough to see it is a cloud.
    public static let spin = 2 * Double.pi / 120
    /// How far a node bobs while idle, in world points, and how long one bob takes at the slowest and the quickest.
    public static let driftReach = 7.0
    private static let driftSlowest = 9.0
    private static let driftQuickest = 5.0
    /// Nothing is ever drawn nearer than this share of the eye's distance, so a node never passes behind the eye.
    public static let nearest = 0.35
    /// FNV 1a, so a node's height is the same on every launch, which `Hasher` is not.
    private static let fnvBasis: UInt64 = 0xcbf2_9ce4_8422_2325
    private static let fnvPrime: UInt64 = 0x0000_0100_0000_01b3
    /// How finely a hash is cut into a fraction.
    private static let fraction: UInt64 = 1 << 20
    private static let fullTurn = 2 * Double.pi
    private static let driftSalt: UInt64 = 3
    private static let paceSalt: UInt64 = 4

    public static let atRest = SurfaceTurn(yaw: 0, pitch: restingPitch)

    /// A fraction from 0 to under 1 drawn from an id, the same every time.
    public static func unit(_ id: String, salt: UInt64) -> Double {
        var hash = fnvBasis ^ salt
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* fnvPrime
        }
        return Double(hash % fraction) / Double(fraction)
    }

    /// The point turned to face the eye: about the vertical axis, then tipped.
    private static func turned(_ point: SurfacePoint, _ turn: SurfaceTurn) -> SurfacePoint {
        let x = point.x * cos(turn.yaw) - point.z * sin(turn.yaw)
        let z = point.x * sin(turn.yaw) + point.z * cos(turn.yaw)
        let y = point.y * cos(turn.pitch) - z * sin(turn.pitch)
        return SurfacePoint(x: x, y: y, z: point.y * sin(turn.pitch) + z * cos(turn.pitch))
    }

    /// The turn undone, so a point moved in what the eye sees lands back in the cloud.
    private static func unturned(_ point: SurfacePoint, _ turn: SurfaceTurn) -> SurfacePoint {
        let y = point.y * cos(turn.pitch) + point.z * sin(turn.pitch)
        let z = -point.y * sin(turn.pitch) + point.z * cos(turn.pitch)
        return SurfacePoint(x: point.x * cos(turn.yaw) + z * sin(turn.yaw), y: y, z: -point.x * sin(turn.yaw) + z * cos(turn.yaw))
    }

    private static func perspective(_ z: Double) -> Double {
        focal / max(focal + z, focal * nearest)
    }

    /// Where a point in the cloud is seen, turned and in perspective.
    public static func seen(_ point: SurfacePoint, turn: SurfaceTurn) -> SurfaceSeen {
        let facing = turned(point, turn)
        let scale = perspective(facing.z)
        let depth = min(max(0.5 - facing.z / (2 * reach), 0), 1)
        return SurfaceSeen(x: facing.x * scale, y: facing.y * scale, scale: scale, depth: depth)
    }

    /// The turn that brings a point round to the front of the cloud, square to the eye, by the shortest way from the
    /// turn it is at now, so flying to a node never spins the cloud the long way round; the tip is kept.
    public static func facing(_ point: SurfacePoint, from turn: SurfaceTurn) -> SurfaceTurn {
        guard hypot(point.x, point.z) > .ulpOfOne else { return turn }
        let wanted = -Double.pi / 2 - atan2(point.z, point.x)
        var step = (wanted - turn.yaw).truncatingRemainder(dividingBy: fullTurn)
        if step > Double.pi { step -= fullTurn }
        if step <= -Double.pi { step += fullTurn }
        return SurfaceTurn(yaw: turn.yaw + step, pitch: turn.pitch)
    }

    /// A point dragged across what the eye sees, by world points on the seen plane: it slides at its own depth, so it
    /// stays under the pointer whichever way the cloud is turned.
    public static func moved(_ point: SurfacePoint, by delta: (x: Double, y: Double), turn: SurfaceTurn) -> SurfacePoint {
        var facing = turned(point, turn)
        let scale = perspective(facing.z)
        facing.x += delta.x / scale
        facing.y += delta.y / scale
        return unturned(facing, turn)
    }

    /// The soft bob a node makes while idle, each on its own pace and phase so the cloud breathes rather than marches.
    public static func drift(_ id: String, seconds: Double) -> SurfacePoint {
        let pace = driftQuickest + (driftSlowest - driftQuickest) * unit(id, salt: paceSalt)
        let phase = unit(id, salt: driftSalt) * fullTurn
        let angle = seconds / pace * fullTurn + phase
        return SurfacePoint(x: 0, y: sin(angle) * driftReach, z: cos(angle) * driftReach)
    }

    /// Everything the cloud could cover at any yaw, as places the camera can fit: each node at the furthest it swings
    /// either side, at the front's perspective, and tipped by the pitch. Fitting this never zooms as the cloud turns.
    public static func envelope(_ places: [Placed], pitch: Double) -> [Placed] {
        places.flatMap { place -> [Placed] in
            let swing = hypot(place.x, place.lift)
            // The tilt brings a node's height toward the eye as well, so the nearest it can come counts that too.
            let scale = perspective(-(swing + abs(place.y * sin(pitch))))
            let tip = swing * abs(sin(pitch))
            let level = place.y * cos(pitch)
            return [(swing, level - tip), (-swing, level + tip)].map { spot in
                Placed(id: place.id, x: spot.0 * scale, y: spot.1 * scale, depth: place.depth, width: place.width * scale,
                       height: place.height.map { $0 * scale }, captioned: place.captioned, label: place.label, lift: place.lift)
            }
        }
    }

    /// The visible part of a line between two seen marks, each trimmed by its own radius; nil where they overlap.
    public static func between(_ from: (x: Double, y: Double, radius: Double), _ to: (x: Double, y: Double, radius: Double))
        -> SurfaceLine? {
        let span = hypot(to.x - from.x, to.y - from.y)
        guard span > from.radius + to.radius else { return nil }
        let unitX = (to.x - from.x) / span
        let unitY = (to.y - from.y) / span
        return SurfaceLine(x1: from.x + unitX * from.radius, y1: from.y + unitY * from.radius,
                           x2: to.x - unitX * to.radius, y2: to.y - unitY * to.radius)
    }
}

/// The slow turn's clock: how long the cloud has been let turn, banked across every pause, and how far a hand turned
/// it. A pause freezes the turn and the drift where they are, and going again carries on from there without a jump.
public struct OrbitClock: Equatable, Sendable {
    /// Seconds turned before the stretch now running.
    private var banked: Double = 0
    private var since: Date?
    /// Turned by hand, in radians, on top of the slow turn.
    public private(set) var offset: Double = 0

    public init() {}

    public var running: Bool { since != nil }

    /// Seconds the cloud has been let move, which the drift reads too.
    public func seconds(at now: Date) -> Double {
        banked + (since.map { max(now.timeIntervalSince($0), 0) } ?? 0)
    }

    public func yaw(at now: Date) -> Double {
        offset + seconds(at: now) * SurfaceOrbit.spin
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

    /// A drag turning the cloud by hand, which keeps the slow turn's own count untouched.
    public mutating func turn(to offset: Double) {
        self.offset = offset
    }
}
