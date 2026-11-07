import Foundation

// Memory drawn inside a brain seen from the side, as star clusters: **one cluster to each hub** (a source, a project, an
// app or a workspace tool, or a person many pieces name) with every piece it holds radiating around it, and the
// clusters packed inside the brain's outline so none lies over another. Every spot is a hash of an id or a step of a
// fixed spiral, never a random number, so the same record draws the same brain on every launch and is tested headless.
// World points: x runs from the back of the brain to its front, y runs down as the screen's does, and z, a little depth
// for parallax, runs away from the eye.

/// The outline of a brain seen from the side, front to the right, as a closed polygon in world points.
public enum BrainOutline {
    /// Half the brain's length and height, in world points: about the room the settled map has always taken.
    public static let halfLength = 480.0
    public static let halfHeight = 320.0

    /// The silhouette as shares of the half length and half height, clockwise from the crown: the frontal lobe, the
    /// temporal pole, the stem, the cerebellum and the occipital lobe.
    private static let profile: [(u: Double, v: Double)] = [
        (-0.05, -0.98), (0.22, -0.96), (0.45, -0.86), (0.65, -0.7), (0.82, -0.48), (0.93, -0.22), (0.97, 0.05),
        (0.92, 0.28), (0.8, 0.44), (0.62, 0.5), (0.5, 0.62), (0.38, 0.74), (0.18, 0.8), (-0.02, 0.78), (-0.12, 0.72),
        (-0.14, 0.86), (-0.12, 1.05), (-0.22, 1.08), (-0.26, 0.88), (-0.38, 0.86), (-0.56, 0.82), (-0.7, 0.7),
        (-0.74, 0.56), (-0.84, 0.42), (-0.94, 0.18), (-0.97, -0.08), (-0.9, -0.36), (-0.76, -0.6), (-0.56, -0.8),
        (-0.32, -0.93),
    ]
    /// Where packing starts, a little above the middle where the cerebrum is widest.
    private static let heart = (u: 0.0, v: -0.1)

    /// The outline's corners in world points, at no depth.
    public static let points: [SurfacePoint] = profile.map { SurfacePoint(x: $0.u * halfLength, y: $0.v * halfHeight, z: 0) }

    public static var middle: (x: Double, y: Double) { (heart.u * halfLength, heart.v * halfHeight) }

    /// Whether a spot is inside the outline, by counting the edges a ray from it crosses.
    public static func contains(x: Double, y: Double) -> Bool {
        var inside = false
        var last = points[points.count - 1]
        for point in points {
            if (point.y > y) != (last.y > y), x < (last.x - point.x) * (y - point.y) / (last.y - point.y) + point.x {
                inside.toggle()
            }
            last = point
        }
        return inside
    }

    /// The area inside the outline, in square world points, which bounds how much the clusters may fill.
    public static var area: Double {
        var twice = 0.0
        var last = points[points.count - 1]
        for point in points {
            twice += last.x * point.y - point.x * last.y
            last = point
        }
        return abs(twice) / 2
    }
}

/// One cluster: the hub it radiates from, the group it is coloured by, the pieces it holds, and where it sits.
public struct BrainCluster: Equatable, Sendable {
    /// The hub's node id, or the group's own id for the pieces that reach no hub.
    public let id: String
    /// The hub's node, nil for a group's loose pieces, which radiate from a point no node stands on.
    public let hub: String?
    public let group: SourceGroup
    public let members: [String]
    public let x: Double
    public let y: Double
    public let radius: Double
}

/// The whole brain for one map: the clusters, every node's spot, and which cluster each node is in.
public struct BrainLayout: Equatable, Sendable {
    public let clusters: [BrainCluster]
    public let spots: [String: SurfacePoint]
    public let cluster: [String: String]
    /// From 0 for a piece nothing else links to, up to 1 for a hub, which is drawn larger and brighter.
    public let prominence: [String: Double]

    /// The groups present, in group order, which a replay flies in one after the other.
    public var groups: [SourceGroup] {
        let present = Set(clusters.map(\.group))
        return SourceGroup.allCases.filter(present.contains)
    }
}

public enum BrainClusters {
    /// A person counts as a hub once this many lines touch them; fewer, and they are a piece of someone else's cluster.
    public static let personHub = 3
    /// A cluster's radius: the least, and how it grows with the square root of what it holds, in world points.
    public static let clusterLeast = 34.0
    public static let clusterPer = 16.0
    /// Pieces sit from this share of the radius out, so the spokes read and the hub stands clear.
    public static let memberInner = 0.3
    /// How far a piece floats in front of or behind its hub, in world points, so a tilt gives a little parallax.
    public static let depthSpread = 60.0
    /// The air between two clusters, in world points.
    public static let gap = 18.0
    /// The share of the brain the clusters may fill before they are drawn smaller, so the packing always has room.
    public static let fillShare = 0.5
    /// The packing walks a golden angle spiral out from the middle, this far further out each step's square root.
    public static let spiralStep = 9.0
    public static let mostTries = 1600
    /// When a packing cannot fit everything, every cluster is drawn this much smaller and it starts again.
    public static let shrink = 0.86
    public static let mostShrinks = 6
    /// How many points of a cluster's rim are checked against the outline.
    public static let rimSamples = 12
    /// The degree at which a piece stands out as much as a piece can; a hub always stands out fully.
    public static let pieceDegree = 8
    public static let pieceMost = 0.45
    /// The idle sway: how far the brain turns either way, in radians, and how long one sway takes.
    public static let swayReach = 0.22
    public static let swayPeriod: TimeInterval = 24
    /// How far a drag may turn the brain, short of seeing it edge on, and tip it.
    public static let yawLimit = 0.7
    public static let pitchLimit = 0.45

    private static let fullTurn = 2 * Double.pi
    private static let golden = Double.pi * (3 - 5.0.squareRoot())
    private static let looseIds = "loose:"
    private static let angleSalt: UInt64 = 51
    private static let reachSalt: UInt64 = 52
    private static let depthSalt: UInt64 = 53

    /// The cluster id the pieces of a group that reach no hub share.
    public static func looseId(_ group: SourceGroup) -> String { looseIds + group.rawValue }

    /// Whether a node is a hub: a source, a project and an app always, and a person whom many lines name.
    public static func isHub(_ node: MemoryMapNode, degree: Int) -> Bool {
        switch node.kind {
        case .source, .workspace, .app: true
        case .person: degree >= personHub
        case .memory, .document, .rule, .conversation, .decision, .skill, .standing: false
        }
    }

    /// A cluster's radius before any shrinking, from what it holds.
    public static func radius(holding members: Int) -> Double {
        clusterLeast + clusterPer * Double(max(members, 0)).squareRoot()
    }

    /// The idle sway at a moment, so the brain turns gently back and forth rather than round.
    public static func sway(_ seconds: Double) -> Double {
        swayReach * sin(seconds / swayPeriod * fullTurn)
    }

    /// The brain for a map: each piece in the cluster of the hub it reaches first, along the lines a group is inherited
    /// along, the clusters packed inside the outline, and each piece at a spot drawn from its id.
    public static func layout(_ map: MemoryMap, groups: [String: SourceGroup]) -> BrainLayout {
        let degree = MemoryGroups.degrees(map)
        var seeds: [String: String] = [:]
        for node in map.nodes where isHub(node, degree: degree[node.id] ?? 0) { seeds[node.id] = node.id }
        let owners = MemoryGroups.inherit(map, from: seeds)
        var held: [String: [String]] = [:]
        var order: [String] = []
        for node in map.nodes.sorted(by: { $0.id < $1.id }) {
            let owner = owners[node.id] ?? looseId(groups[node.id] ?? .unsourced)
            if held[owner] == nil { order.append(owner) }
            held[owner, default: []].append(node.id)
        }
        let groupOf = { (owner: String) -> SourceGroup in
            groups[owner] ?? SourceGroup.allCases.first { looseId($0) == owner } ?? .unsourced
        }
        let rank = Dictionary(SourceGroup.allCases.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        // Largest first, so the big clusters take the middle and the small ones fill around them.
        let sized = order.map { owner -> (id: String, members: [String], radius: Double) in
            let members = (held[owner] ?? []).filter { $0 != owner }
            return (owner, members, radius(holding: members.count))
        }.sorted { left, right in
            if left.radius != right.radius { return left.radius > right.radius }
            let a = rank[groupOf(left.id)] ?? 0
            let b = rank[groupOf(right.id)] ?? 0
            return a == b ? left.id < right.id : a < b
        }
        let centres = pack(sized.map(\.radius))
        var clusters: [BrainCluster] = []
        var spots: [String: SurfacePoint] = [:]
        var cluster: [String: String] = [:]
        var prominence: [String: Double] = [:]
        for (index, each) in sized.enumerated() {
            let centre = centres.spots[index]
            let radius = each.radius * centres.scale
            let hub = seeds[each.id] == nil ? nil : each.id
            clusters.append(BrainCluster(id: each.id, hub: hub, group: groupOf(each.id), members: each.members, x: centre.x,
                                         y: centre.y, radius: radius))
            if let hub {
                spots[hub] = SurfacePoint(x: centre.x, y: centre.y, z: 0)
                cluster[hub] = each.id
                prominence[hub] = 1
            }
            for member in each.members {
                spots[member] = spot(member, around: centre, radius: radius)
                cluster[member] = each.id
                prominence[member] = pieceMost * (Double(min(degree[member] ?? 0, pieceDegree)) / Double(pieceDegree)).squareRoot()
            }
        }
        return BrainLayout(clusters: clusters, spots: spots, cluster: cluster, prominence: prominence)
    }

    /// One piece's spot around its hub: at an angle and a reach drawn from its id, evenly over the disc since the reach
    /// is a square root, and a little in front of or behind it.
    public static func spot(_ id: String, around centre: (x: Double, y: Double), radius: Double) -> SurfacePoint {
        let angle = SurfaceOrbit.unit(id, salt: angleSalt) * fullTurn
        let reach = radius * (memberInner + (1 - memberInner) * SurfaceOrbit.unit(id, salt: reachSalt).squareRoot())
        let depth = (SurfaceOrbit.unit(id, salt: depthSalt) * 2 - 1) * depthSpread
        return SurfacePoint(x: centre.x + cos(angle) * reach, y: centre.y + sin(angle) * reach, z: depth)
    }

    /// Centres for discs of these radii inside the outline, none over another, each taking the first free step of a
    /// spiral out from the middle, stretched to the brain's own proportions. Drawn smaller and packed again when they do
    /// not all fit; the last try lets a disc lie over another rather than leave it off the brain.
    public static func pack(_ radii: [Double]) -> (spots: [(x: Double, y: Double)], scale: Double) {
        let wanted = radii.reduce(0) { $0 + Double.pi * pow($1 + gap / 2, 2) }
        var scale = wanted > 0 ? min(1, (fillShare * BrainOutline.area / wanted).squareRoot()) : 1
        for attempt in 0...mostShrinks {
            if let spots = packed(radii.map { $0 * scale }, overlapping: attempt == mostShrinks) { return (spots, scale) }
            scale *= shrink
        }
        return (radii.map { _ in BrainOutline.middle }, scale)
    }

    private static func packed(_ radii: [Double], overlapping: Bool) -> [(x: Double, y: Double)]? {
        let stretch = BrainOutline.halfLength / BrainOutline.halfHeight
        let middle = BrainOutline.middle
        var placed: [(x: Double, y: Double, radius: Double)] = []
        for radius in radii {
            var found: (x: Double, y: Double)?
            var fallback: (x: Double, y: Double)?
            for step in 0..<mostTries {
                let angle = Double(step) * golden
                let reach = spiralStep * Double(step).squareRoot()
                let spot = (x: middle.x + cos(angle) * reach * stretch.squareRoot(), y: middle.y + sin(angle) * reach / stretch.squareRoot())
                // The cheap test first: most steps near the middle are already taken.
                let free = placed.allSatisfy { hypot($0.x - spot.x, $0.y - spot.y) >= $0.radius + radius + gap }
                guard free || (overlapping && fallback == nil) else { continue }
                guard inside(spot, radius) else { continue }
                if fallback == nil { fallback = spot }
                if free {
                    found = spot
                    break
                }
            }
            guard let spot = found ?? (overlapping ? fallback ?? middle : nil) else { return nil }
            placed.append((spot.x, spot.y, radius))
        }
        return placed.map { ($0.x, $0.y) }
    }

    /// Whether a disc lies wholly inside the outline: its middle and every sampled point of its rim.
    private static func inside(_ centre: (x: Double, y: Double), _ radius: Double) -> Bool {
        guard BrainOutline.contains(x: centre.x, y: centre.y) else { return false }
        return (0..<rimSamples).allSatisfy { index in
            let angle = Double(index) / Double(rimSamples) * fullTurn
            return BrainOutline.contains(x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius)
        }
    }
}
