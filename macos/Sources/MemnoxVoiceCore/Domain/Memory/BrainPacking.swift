import Foundation

// Circles packed about a middle so none lies over another, the way the second brain references draw each area as one
// tight cluster. **Every spot is a step of one fixed spiral**, the first step where the circle is clear of all before
// it, never a random number, so the same record packs the same way on every launch and the cloud's port of this
// arithmetic packs it alike. A grid of buckets keeps the clear test cheap, so thousands of circles still pack at once.

/// One circle to pack: the id it stands for and how much room it needs, in world points.
public struct PackCircle: Equatable, Sendable {
    public let id: String
    public let radius: Double

    public init(id: String, radius: Double) {
        self.id = id
        self.radius = radius
    }
}

/// Where each circle landed about the middle, in the order given, and the radius of the disc that holds them all.
public struct PackedCircles: Equatable, Sendable {
    public let spots: [(x: Double, y: Double)]
    public let radius: Double

    public static func == (left: PackedCircles, right: PackedCircles) -> Bool {
        left.radius == right.radius && left.spots.elementsEqual(right.spots) { $0.x == $1.x && $0.y == $1.y }
    }
}

public enum BrainPacking {
    /// The spiral steps this share of the smallest circle's radius further out each square root of a step, fine
    /// enough that a small circle finds the gaps the large ones left.
    public static let stepShare = 0.9
    /// How many steps a circle walks before it is set just past everything already packed, which is always clear.
    public static let mostSteps = 40_000
    private static let golden = Double.pi * (3 - 5.0.squareRoot())

    /// Packs the circles in the order given, largest first reading best, each at the first clear step of the spiral
    /// with `gap` of air to every other; the first sits on the middle.
    public static func pack(_ circles: [PackCircle], gap: Double) -> PackedCircles {
        guard let least = circles.map(\.radius).min(), let most = circles.map(\.radius).max() else {
            return PackedCircles(spots: [], radius: 0)
        }
        let step = max(least, .ulpOfOne) * stepShare
        var grid = Grid(cell: max(2 * most + gap, .ulpOfOne))
        var spots: [(x: Double, y: Double)] = []
        spots.reserveCapacity(circles.count)
        var bound = 0.0
        var cursor = 0
        var lastRadius = circles[0].radius
        for circle in circles {
            // A circle as large as the one before starts where that one landed, since every step inside it was taken
            // for its size, which keeps a big area quick; a circle of another size walks from the middle again.
            if circle.radius != lastRadius { cursor = 0 }
            lastRadius = circle.radius
            var found: (x: Double, y: Double)?
            while cursor < mostSteps {
                let angle = Double(cursor) * golden
                let reach = step * Double(cursor).squareRoot()
                let spot = (x: cos(angle) * reach, y: sin(angle) * reach)
                if grid.clear(spot, radius: circle.radius, gap: gap) {
                    found = spot
                    break
                }
                cursor += 1
            }
            let spot = found ?? beyond(bound, circle.radius, gap: gap, turn: Double(spots.count) * golden)
            grid.insert(spot, radius: circle.radius)
            spots.append(spot)
            bound = max(bound, hypot(spot.x, spot.y) + circle.radius)
        }
        return PackedCircles(spots: spots, radius: bound)
    }

    /// Whether any two packed circles lie over each other or closer than the gap, for the tests and a debug check.
    public static func overlaps(_ circles: [PackCircle], _ packed: PackedCircles, gap: Double) -> Bool {
        let tolerance = 1e-9
        for left in circles.indices {
            for right in circles.indices where right > left {
                let apart = hypot(packed.spots[left].x - packed.spots[right].x, packed.spots[left].y - packed.spots[right].y)
                if apart + tolerance < circles[left].radius + circles[right].radius + gap { return true }
            }
        }
        return false
    }

    /// A spot just past everything packed so far, which nothing can lie over.
    private static func beyond(_ bound: Double, _ radius: Double, gap: Double, turn: Double) -> (x: Double, y: Double) {
        let reach = bound + radius + gap
        return (cos(turn) * reach, sin(turn) * reach)
    }

    /// Buckets of packed circles by where they sit, so a clear test asks only the few near it.
    private struct Grid {
        let cell: Double
        var buckets: [Int64: [(x: Double, y: Double, radius: Double)]] = [:]

        init(cell: Double) { self.cell = cell }

        private func key(_ column: Int64, _ row: Int64) -> Int64 { column &* 1_000_003 &+ row }

        private func index(_ value: Double) -> Int64 { Int64((value / cell).rounded(.down)) }

        mutating func insert(_ spot: (x: Double, y: Double), radius: Double) {
            buckets[key(index(spot.x), index(spot.y)), default: []].append((spot.x, spot.y, radius))
        }

        func clear(_ spot: (x: Double, y: Double), radius: Double, gap: Double) -> Bool {
            let column = index(spot.x)
            let row = index(spot.y)
            for across in (column - 1)...(column + 1) {
                for down in (row - 1)...(row + 1) {
                    for other in buckets[key(across, down)] ?? [] where hypot(other.x - spot.x, other.y - spot.y) < other.radius + radius + gap {
                        return false
                    }
                }
            }
            return true
        }
    }
}
