import Foundation

// The tissue the brain is drawn in, the way the reference brains are: the silhouette filled with small wireframe
// tetrahedra, each tumbling on its own slow axis, a warm and a violet band along the rim and pale grains inside, and a
// lens under the pointer that swells and whitens what it passes over. Every grain is a step of a fixed grid jittered
// by a hash, never a random number, so the same brain draws the same tissue on every launch and is tested headless.

/// Which part of the tissue a grain is in, which colours it: the gold and the violet rim, the teal under it, the pale core.
public enum TissueBand: Int, CaseIterable, Sendable {
    case gold
    case violet
    case teal
    case pale
}

/// One grain: where it stands as an angle and a share of the silhouette's reach, so it fills whatever share the
/// envelope is drawn at, its band, its size as a share of the largest, the phase it tumbles from, and its rank.
public struct TissueGrain: Equatable, Sendable {
    public let angle: Double
    public let share: Double
    public let band: TissueBand
    public let size: Double
    public let spin: Double
    /// Where the grain stands in the thinning order: a smaller brain keeps only the grains ranked under its area.
    public let rank: Double
}

/// A point of a tetrahedron as seen face on, in units of its size.
public struct TissueCorner: Equatable, Sendable {
    public let x: Double
    public let y: Double
}

public enum BrainTissue {
    /// The grid the grains stand on, in world points at full size: fine enough that the silhouette reads as a shape.
    public static let step = 17.0
    /// How far a grain may stray from its grid spot, as a share of the step, so the grid never shows as rows.
    private static let jitter = 0.42
    /// Past this share of the reach a grain is on the rim, and past this one it is in the teal under it.
    public static let rimFrom = 0.8
    public static let tealFrom = 0.62
    /// The least a grain is, as a share of the largest.
    private static let leastSize = 0.45
    /// How long one slow tumble takes at the quickest and the slowest, in idle seconds.
    private static let quickestTurn = 9.0
    private static let slowestTurn = 22.0
    private static let fullTurn = 2 * Double.pi
    /// How far past its half height the outline reaches, at its stem.
    private static let stemRoom = 1.1
    /// How many times faster a grain rolls than it pitches, so no two axes line up.
    private static let rollRatio = 7.0
    private static let jitterSalt: UInt64 = 211
    private static let bandSalt: UInt64 = 223
    private static let sizeSalt: UInt64 = 227
    private static let spinSalt: UInt64 = 229
    private static let rankSalt: UInt64 = 233

    /// Every grain inside the silhouette, built once, ordered by grid row so a frame walks it in one pass.
    public static let grains: [TissueGrain] = {
        var grains: [TissueGrain] = []
        // The outline's stem reaches a little below its half height, so the rows run that much further down.
        let columns = Int((BrainOutline.halfLength * 2 / step).rounded(.up))
        let rows = Int((BrainOutline.halfHeight * 2 * stemRoom / step).rounded(.up))
        for row in 0...rows {
            for column in 0...columns {
                let key = "\(column):\(row)"
                // Every other row shifted half a step, so the grains lie as a honeycomb rather than a chessboard.
                let shift: Double = row % 2 == 0 ? 0 : step / 2
                let strayX: Double = (SurfaceOrbit.unit(key, salt: jitterSalt) - 0.5) * step * jitter
                let strayY: Double = (SurfaceOrbit.unit(key, salt: jitterSalt + 1) - 0.5) * step * jitter
                let x: Double = -BrainOutline.halfLength + Double(column) * step + shift + strayX
                let y: Double = -BrainOutline.halfHeight * stemRoom + Double(row) * step + strayY
                guard BrainOutline.contains(x: x, y: y) else { continue }
                let polar = BrainShell.polar((x, y))
                guard polar.share <= 1 else { continue }
                let ring = band(share: polar.share, pick: SurfaceOrbit.unit(key, salt: bandSalt))
                let size = leastSize + (1 - leastSize) * SurfaceOrbit.unit(key, salt: sizeSalt)
                grains.append(TissueGrain(angle: polar.angle, share: polar.share, band: ring, size: size,
                                          spin: SurfaceOrbit.unit(key, salt: spinSalt),
                                          rank: SurfaceOrbit.unit(key, salt: rankSalt)))
            }
        }
        return grains
    }()

    /// The band a grain at a share of the reach is in: the rim split between gold and violet, a teal ring under it,
    /// and pale inside, with a few teal grains scattered through the core.
    public static func band(share: Double, pick: Double) -> TissueBand {
        if share >= rimFrom { return pick < rimGold ? .gold : .violet }
        if share >= tealFrom { return pick < underTeal ? .teal : pick < underViolet ? .violet : .pale }
        return pick < coreTeal ? .teal : .pale
    }

    /// The share of the rim that is gold, of the ring under it that is teal and then violet, and of the core that is teal.
    private static let rimGold = 0.62
    private static let underTeal = 0.35
    private static let underViolet = 0.55
    private static let coreTeal = 0.12

    /// The four corners of a tetrahedron a grain draws, turned about its own tilted axis by the idle seconds and seen
    /// face on, each within one unit of its middle.
    public static func corners(spin: Double, seconds: Double) -> [TissueCorner] {
        let pace = quickestTurn + (slowestTurn - quickestTurn) * spin
        let yaw = (seconds / pace + spin) * fullTurn
        let pitch = spin * fullTurn
        let roll = (spin * rollRatio).truncatingRemainder(dividingBy: 1) * fullTurn
        return tetrahedron.map { corner in
            // About z, then about x, then about y, and the depth dropped.
            let x1 = corner.x * cos(roll) - corner.y * sin(roll)
            let y1 = corner.x * sin(roll) + corner.y * cos(roll)
            let y2 = y1 * cos(pitch) - corner.z * sin(pitch)
            let z2 = y1 * sin(pitch) + corner.z * cos(pitch)
            return TissueCorner(x: x1 * cos(yaw) + z2 * sin(yaw), y: y2)
        }
    }

    /// The six edges of a tetrahedron, by corner.
    public static let edges: [(Int, Int)] = [(0, 1), (1, 2), (2, 0), (0, 3), (1, 3), (2, 3)]

    /// A regular tetrahedron with its corners one unit from its middle.
    private static let tetrahedron: [(x: Double, y: Double, z: Double)] = {
        let side = 1 / 3.0.squareRoot()
        return [(side, side, side), (side, -side, -side), (-side, side, -side), (-side, -side, side)]
    }()
}

/// The pointer's lens: how much a mark a distance from the pointer is pulled toward it, one under the pointer and none
/// at the lens's edge, on a smooth curve so the edge never shows.
public enum BrainLens {
    /// How far the lens reaches, in screen points.
    public static let radius = 110.0

    public static func pull(distance: Double) -> Double {
        guard distance < radius else { return 0 }
        let near = 1 - max(distance, 0) / radius
        return near * near * (3 - 2 * near)
    }
}
