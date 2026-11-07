import Foundation

// The brain built out of its own nodes, the way the second brain references draw it: the instruction files and the
// skills packed at the core, each memory area its own tight coloured cluster about a labelled hub with spokes back to
// the core, the rules that run without the person in a gold ring around them, and the applications in numbered tiles
// around the outside. **Nothing is drawn for nothing**: every ring sits just past what it rings, so an empty brain is
// empty, and every spot is a hash of an id or a step of a fixed spiral, never a random number, so the same record draws
// the same brain on every launch and is tested headless.

/// One layer of the brain, in the order they sit from the core out, which an opening flies them in by.
public enum BrainLayer: String, CaseIterable, Sendable {
    case skills
    case memory
    case rules
    case applications
}

/// The silhouette at any share of its size about the core: how far the outline is from the core along each angle,
/// read off a table so a frame of thousands of dots never casts a ray, and how far round it is by length.
public enum BrainShell {
    /// How finely the outline is sampled around the core: a third of a degree is finer than any dot.
    public static let samples = 1080
    private static let fullTurn = 2 * Double.pi
    private static let reaches: [Double] = (0..<samples).map { ray(Double($0) / Double(samples) * fullTurn) }
    /// The length of the outline at full size from angle 0 to each sample, and all the way round at the end.
    private static let lengths: [Double] = {
        var total = 0.0
        var running: [Double] = [0]
        running.reserveCapacity(samples + 1)
        var last = point(0, share: 1)
        for step in 1...samples {
            let next = point(Double(step) / Double(samples) * fullTurn, share: 1)
            total += hypot(next.x - last.x, next.y - last.y)
            running.append(total)
            last = next
        }
        return running
    }()

    /// How long the outline is all the way round at full size; at any other share it is that share of this.
    public static var perimeter: Double { lengths[samples] }

    /// How far the outline is from the core along an angle, in world points, between the two nearest samples.
    public static func reach(_ angle: Double) -> Double {
        let at = wrapped(angle) / fullTurn * Double(samples)
        let low = Int(at) % samples
        let high = (low + 1) % samples
        let share = at - Double(Int(at))
        return reaches[low] + (reaches[high] - reaches[low]) * share
    }

    /// A spot on the silhouette shrunk to a share of its size about the core: 1 is the outline itself.
    public static func point(_ angle: Double, share: Double) -> (x: Double, y: Double) {
        let middle = BrainOutline.middle
        let distance = reach(angle) * share
        return (middle.x + cos(angle) * distance, middle.y + sin(angle) * distance)
    }

    /// The angle and share a world spot stands at, the inverse of `point`.
    public static func polar(_ spot: (x: Double, y: Double)) -> (angle: Double, share: Double) {
        let middle = BrainOutline.middle
        let offset = (x: spot.x - middle.x, y: spot.y - middle.y)
        let distance = hypot(offset.x, offset.y)
        guard distance > .ulpOfOne else { return (0, 0) }
        let angle = atan2(offset.y, offset.x)
        return (angle, distance / reach(angle))
    }

    /// The silhouette at a share of its size, as this many corners, for an envelope's line.
    public static func outline(share: Double, corners: Int) -> [(x: Double, y: Double)] {
        (0..<max(corners, 3)).map { point(Double($0) / Double(max(corners, 3)) * fullTurn, share: share) }
    }

    /// The angle a share of the way round the outline by length lands on, counted from an angle, so marks spaced by
    /// it stand evenly apart on the long flat flanks and the tight poles alike.
    public static func angle(along share: Double, from: Double) -> Double {
        let base = length(at: from)
        var target = (base + share * perimeter).truncatingRemainder(dividingBy: perimeter)
        if target < 0 { target += perimeter }
        var low = 0
        var high = samples
        while high - low > 1 {
            let middle = (low + high) / 2
            if lengths[middle] <= target { low = middle } else { high = middle }
        }
        let span = lengths[high] - lengths[low]
        let within = span > .ulpOfOne ? (target - lengths[low]) / span : 0
        return (Double(low) + within) / Double(samples) * fullTurn
    }

    /// How far round the outline an angle is by length, from angle 0.
    private static func length(at angle: Double) -> Double {
        let at = wrapped(angle) / fullTurn * Double(samples)
        let low = min(Int(at), samples - 1)
        return lengths[low] + (lengths[low + 1] - lengths[low]) * (at - Double(low))
    }

    private static func wrapped(_ angle: Double) -> Double {
        var turn = angle.truncatingRemainder(dividingBy: fullTurn)
        if turn < 0 { turn += fullTurn }
        return turn
    }

    /// The nearest crossing of the outline by a ray from the core, the largest reach where a ray grazes a corner.
    private static func ray(_ angle: Double) -> Double {
        let middle = BrainOutline.middle
        let direction = (x: cos(angle), y: sin(angle))
        var nearest = Double.infinity
        let points = BrainOutline.points
        var last = points[points.count - 1]
        for point in points {
            let edge = (x: point.x - last.x, y: point.y - last.y)
            let cross = direction.x * edge.y - direction.y * edge.x
            if abs(cross) > .ulpOfOne {
                let offset = (x: last.x - middle.x, y: last.y - middle.y)
                let along = (offset.x * edge.y - offset.y * edge.x) / cross
                let onEdge = (offset.x * direction.y - offset.y * direction.x) / cross
                if along > 0, onEdge >= 0, onEdge <= 1 { nearest = min(nearest, along) }
            }
            last = point
        }
        return nearest.isFinite ? nearest : BrainOutline.halfHeight
    }
}

/// One angular sector of the brain an area's cluster sits inside: the area it holds and the angles it spans.
public struct BrainSector: Equatable, Sendable {
    public let group: SourceGroup
    public let start: Double
    public let end: Double
    public let count: Int

    public var middle: Double { (start + end) / 2 }

    public func holds(_ angle: Double) -> Bool {
        let turn = 2 * Double.pi
        var a = (angle - start).truncatingRemainder(dividingBy: turn)
        if a < 0 { a += turn }
        return a <= end - start
    }
}

/// One memory area's cluster: its labelled hub in world points, the disc that holds every piece, and how many it holds.
public struct BrainArea: Equatable, Sendable {
    public let group: SourceGroup
    public let x: Double
    public let y: Double
    public let radius: Double
    public let count: Int
}

/// Where one node sits in the layers: its layer, its angle about the core, its share of the silhouette's size, which
/// cluster order it opens in, how large it is drawn, and its latitude on the shells the 3D view draws.
public struct BrainArmSpot: Equatable, Sendable {
    public let layer: BrainLayer
    public let angle: Double
    public let share: Double
    /// When in the opening it grows in: a memory area's place in the order, 0 for every other layer.
    public let ring: Int
    /// From 0 for a light piece to 1 for a hub, which is drawn larger and brighter.
    public let size: Double
    /// From -1 to 1, how far above or below the side view's plane it sits once the brain is drawn as nested shells.
    public let latitude: Double

    public init(layer: BrainLayer, angle: Double, share: Double, ring: Int, size: Double, latitude: Double) {
        self.layer = layer
        self.angle = angle
        self.share = share
        self.ring = ring
        self.size = size
        self.latitude = latitude
    }
}

/// The whole brain for one map: each node's spot, the area clusters and their sectors, each memory hub's count, the
/// ring numbers, how far out each layer reaches, and the words at the core.
public struct BrainArmsLayout: Equatable, Sendable {
    public let spots: [String: BrainArmSpot]
    public let sectors: [BrainSector]
    public let areas: [BrainArea]
    /// The memory hub each memory piece radiates from, by id, which its spoke runs to.
    public let hub: [String: String]
    /// How many pieces each memory hub holds, worn in its count bubble.
    public let counts: [String: Int]
    /// Where each memory node grows out of on the opening: its area's hub, in world points.
    public let anchors: [String: SurfacePoint]
    /// Each application's number on the outer ring, from 1 clockwise from the crown.
    public let numbers: [String: Int]
    /// How far out each present layer reaches, as a share of the silhouette, which its envelope is drawn at.
    public let reaches: [BrainLayer: Double]
    /// The index every memory it lists links to, MEMORY.md, nil where no agent keeps one.
    public let index: String?
    /// The instruction files the core is named for, nil where no agent reads one.
    public let coreLabel: String?
}

public enum BrainArms {
    /// The room a piece, a hub and a core star take in a cluster, and the air left between two, in world points.
    public static let pieceRoom = 5.5
    public static let hubRoom = 11.0
    public static let starRoom = 6.5
    public static let heartRoom = 12.0
    public static let pieceGap = 3.0
    /// The air between two hubs' discs inside an area, between two areas, and between the core and an area.
    public static let clusterGap = 10.0
    public static let areaGap = 26.0
    /// Every other area's hub sits this share of its radius further out, so the hubs are not all on one circle.
    public static let areaStagger = 0.35
    /// How far an area is pushed out each step while it would lie over another, and the most steps.
    public static let pushStep = 8.0
    public static let mostPushes = 400
    /// The least the core reaches, so a brain with no skills still has a heart for the spokes to leave.
    public static let coreLeast = 24.0
    /// The share of the silhouette left between what a ring rings and the ring, the rules ring and the tiles.
    public static let ringPad = 0.06
    public static let tilePad = 0.12
    /// The room a rule and a tile take around their ring, and the air between two, in world points.
    public static let ruleRoom = 9.0
    public static let tileRoom = 17.0
    public static let ringGap = 6.0
    /// Past this many applications the ring is two rows, every other one a row further out.
    public static let applicationsOneRow = 28
    public static let applicationsRow = 0.1
    /// The air between two memory sectors, in radians, and the least share of the turn a sector takes however small.
    public static let sectorGap = 0.06
    public static let leastSector = 0.05
    /// The most order steps the opening staggers the areas by, the same count the opening curve knows.
    public static let memoryRings = 7
    /// How far above and below the plane the shells reach, in radians of latitude, so the 3D view reads as a body.
    public static let mostLatitude = 1.2
    /// A piece's size: the least, and the most its links add.
    public static let pieceLeast = 0.3
    public static let pieceMost = 0.45
    /// The few instruction files the core is named for, at the most.
    public static let coreNames = 3
    /// The index file a hub with a spoke to every memory it lists is named.
    public static let indexName = "memory.md"
    private static let coreSeparator = " · "
    /// Sectors are laid clockwise from the crown.
    public static let start = -Double.pi / 2

    private static let fullTurn = 2 * Double.pi
    private static let latitudeSalt: UInt64 = 73
    /// Past a right angle a sector is wide enough that its width no longer bounds how near its hub may come.
    private static let rightAngle = Double.pi / 2

    /// The layer a node is drawn in: a skill and the instruction files at the core, a rule in the ring, an app or a
    /// server in a tile, and everything learned in memory.
    public static func layer(_ node: MemoryMapNode, group: SourceGroup) -> BrainLayer {
        switch node.kind {
        case .skill: return .skills
        case .source, .document: return group == .instructions || isIndex(node) ? .skills : .memory
        case .rule, .standing: return .rules
        case .app: return .applications
        case .memory, .conversation, .workspace, .decision, .person: return .memory
        }
    }

    /// Whether a node is the memory index, MEMORY.md, which stands at the core as a hub of what it lists.
    public static func isIndex(_ node: MemoryMapNode) -> Bool {
        guard node.kind == .document || node.kind == .source else { return false }
        let name = node.label.split(separator: "/").last.map(String.init) ?? node.label
        return name.lowercased() == indexName
    }

    /// The brain for a map: the core packed about the middle, each memory area packed into its own disc out along its
    /// sector, its hubs packed inside it with their pieces about them, and the rings just past all of it.
    public static func layout(_ map: MemoryMap, groups: [String: SourceGroup]) -> BrainArmsLayout {
        let sorted = map.nodes.sorted { $0.id < $1.id }
        let layers = Dictionary(sorted.map { ($0.id, layer($0, group: groups[$0.id] ?? .unsourced)) }, uniquingKeysWith: { first, _ in first })
        let degree = MemoryGroups.degrees(map)
        var spots: [String: BrainArmSpot] = [:]
        let core = sorted.filter { layers[$0.id] == .skills }
        let index = core.first(where: isIndex)?.id
        let coreReach = placeCore(core, index: index, into: &spots)
        let memory = sorted.filter { layers[$0.id] == .memory }
        let placed = placeMemory(memory, map: map, groups: groups, degree: degree, core: coreReach, into: &spots)
        var reaches: [BrainLayer: Double] = [:]
        if !core.isEmpty { reaches[.skills] = outerShare(of: core.map(\.id), spots, room: heartRoom) }
        if !memory.isEmpty { reaches[.memory] = outerShare(of: memory.map(\.id), spots, room: pieceRoom) }
        let inside = max(reaches[.skills] ?? 0, reaches[.memory] ?? 0)
        let rules = sorted.filter { layers[$0.id] == .rules }
        let applications = sorted.filter { layers[$0.id] == .applications }
        var outer = inside
        if !rules.isEmpty {
            let share = max(outer + ringPad, ringShare(holding: rules.count, room: ruleRoom, rows: 1))
            placeRing(rules, layer: .rules, share: share, into: &spots)
            reaches[.rules] = share
            outer = share
        }
        var numbers: [String: Int] = [:]
        if !applications.isEmpty {
            let rows = applications.count > applicationsOneRow ? 2 : 1
            let share = max(outer + tilePad, ringShare(holding: applications.count, room: tileRoom, rows: rows))
            placeRing(applications, layer: .applications, share: share, into: &spots)
            for (at, node) in applications.enumerated() { numbers[node.id] = at + 1 }
            reaches[.applications] = share + (rows > 1 ? applicationsRow : 0)
        }
        // The files themselves name the core, CLAUDE.md or AGENTS.md, and the source only where no file was cited.
        let named = core.filter { $0.id != index }
        let files = named.filter { $0.kind == .document }.map(\.label)
        let names = files.isEmpty ? named.filter { $0.kind == .source }.map(\.label) : files
        var seen: Set<String> = []
        let unique = names.filter { seen.insert($0).inserted }.prefix(coreNames)
        return BrainArmsLayout(spots: spots, sectors: placed.sectors, areas: placed.areas, hub: placed.hub, counts: placed.counts,
                               anchors: placed.anchors, numbers: numbers, reaches: reaches, index: index,
                               coreLabel: unique.isEmpty ? nil : unique.joined(separator: coreSeparator))
    }

    /// The least share a ring of this many marks may be drawn at so none touches the next, by the outline's length.
    public static func ringShare(holding count: Int, room: Double, rows: Int) -> Double {
        let perRow = (Double(count) / Double(max(rows, 1))).rounded(.up)
        return perRow * (2 * room + ringGap) / BrainShell.perimeter
    }

    /// The instruction sources at the heart, the memory index beside them, then every skill, packed about the middle
    /// so no star lies over another. Answers how far the core reaches, in world points.
    private static func placeCore(_ nodes: [MemoryMapNode], index: String?, into spots: inout [String: BrainArmSpot]) -> Double {
        let hearts = nodes.filter { $0.kind == .source && $0.id != index }
        let indexes = nodes.filter { $0.id == index }
        let rest = nodes.filter { $0.kind != .source && $0.id != index }
        let ordered = hearts + indexes + rest
        let circles = ordered.map { PackCircle(id: $0.id, radius: $0.kind == .source || $0.id == index ? heartRoom : starRoom) }
        let packed = BrainPacking.pack(circles, gap: pieceGap)
        let middle = BrainOutline.middle
        for (at, node) in ordered.enumerated() {
            let spot = packed.spots[at]
            let polar = BrainShell.polar((middle.x + spot.x, middle.y + spot.y))
            let hub = node.kind == .source || node.id == index
            spots[node.id] = BrainArmSpot(layer: .skills, angle: polar.angle, share: polar.share, ring: 0, size: hub ? 1 : pieceMost,
                                          latitude: hub ? 0 : latitude(node.id))
        }
        return max(packed.radius, coreLeast)
    }

    /// Marks spaced evenly by length round the silhouette at a share, the applications half a step round from the
    /// rules and on two rows where there are too many for one.
    private static func placeRing(_ nodes: [MemoryMapNode], layer: BrainLayer, share: Double, into spots: inout [String: BrainArmSpot]) {
        let twoRows = layer == .applications && nodes.count > applicationsOneRow
        let offset = layer == .applications ? 0.5 : 0
        for (index, node) in nodes.enumerated() {
            let angle = BrainShell.angle(along: (Double(index) + offset) / Double(max(nodes.count, 1)), from: start)
            let row = twoRows && index % 2 == 1 ? applicationsRow : 0
            spots[node.id] = BrainArmSpot(layer: layer, angle: angle, share: share + row, ring: 0, size: 1, latitude: latitude(node.id))
        }
    }

    /// The largest share any of these nodes reaches, its room included.
    private static func outerShare(of ids: [String], _ spots: [String: BrainArmSpot], room: Double) -> Double {
        ids.compactMap { spots[$0] }.map { spot in spot.share + room / BrainShell.reach(spot.angle) }.max() ?? 0
    }

    private struct Placement {
        var sectors: [BrainSector] = []
        var areas: [BrainArea] = []
        var hub: [String: String] = [:]
        var counts: [String: Int] = [:]
        var anchors: [String: SurfacePoint] = [:]
    }

    /// One area packed about its own middle: each hub's disc of pieces, then the discs packed together.
    private struct Packed {
        let group: SourceGroup
        let members: [MemoryMapNode]
        /// Each node's spot about the area's middle, in world points.
        let offsets: [String: (x: Double, y: Double)]
        let radius: Double
        let hub: [String: String]
        let counts: [String: Int]
    }

    /// Memory in areas: each packed into its own disc, the sectors of the turn shared by how wide each disc is, and
    /// each disc set out along its sector's middle as near the core as it fits without touching another.
    private static func placeMemory(_ nodes: [MemoryMapNode], map: MemoryMap, groups: [String: SourceGroup], degree: [String: Int],
                                    core: Double, into spots: inout [String: BrainArmSpot]) -> Placement {
        var placement = Placement()
        guard !nodes.isEmpty else { return placement }
        var seeds: [String: String] = [:]
        for node in nodes where BrainClusters.isHub(node, degree: degree[node.id] ?? 0) { seeds[node.id] = node.id }
        let owners = MemoryGroups.inherit(map, from: seeds)
        var byArea: [SourceGroup: [MemoryMapNode]] = [:]
        for node in nodes { byArea[groups[node.id] ?? .unsourced, default: []].append(node) }
        let areas = SourceGroup.allCases.filter { byArea[$0] != nil }
        let packs = areas.map { pack($0, byArea[$0] ?? [], owners: owners, degree: degree) }
        let weights = packs.map(\.radius)
        let total = max(weights.reduce(0, +), .ulpOfOne)
        let room = fullTurn - sectorGap * Double(areas.count)
        let shares = weights.map { max($0 / total, leastSector) }
        let scale = room / shares.reduce(0, +)
        var cursor = start + sectorGap / 2
        let middle = BrainOutline.middle
        var discs: [(x: Double, y: Double, radius: Double)] = []
        for (order, packed) in packs.enumerated() {
            let span = shares[order] * scale
            let sector = BrainSector(group: packed.group, start: cursor, end: cursor + span, count: packed.members.count)
            placement.sectors.append(sector)
            cursor += span + sectorGap
            // Near enough the core to read as one brain, far enough that the disc stays inside its own sector.
            let half = min(span / 2, rightAngle)
            let wedge = packed.radius / max(sin(half), .ulpOfOne)
            var distance = max(core + areaGap + packed.radius, wedge)
            if order % 2 == 1 { distance += packed.radius * areaStagger }
            let direction = (x: cos(sector.middle), y: sin(sector.middle))
            var centre = (x: middle.x + direction.x * distance, y: middle.y + direction.y * distance)
            var pushes = 0
            while pushes < mostPushes, discs.contains(where: { hypot($0.x - centre.x, $0.y - centre.y) < $0.radius + packed.radius + areaGap }) {
                distance += pushStep
                centre = (middle.x + direction.x * distance, middle.y + direction.y * distance)
                pushes += 1
            }
            discs.append((centre.x, centre.y, packed.radius))
            placement.areas.append(BrainArea(group: packed.group, x: centre.x, y: centre.y, radius: packed.radius, count: packed.members.count))
            let anchor = SurfacePoint(x: centre.x, y: centre.y, z: 0)
            for node in packed.members {
                let offset = packed.offsets[node.id] ?? (0, 0)
                let polar = BrainShell.polar((centre.x + offset.x, centre.y + offset.y))
                let hub = packed.counts[node.id] != nil
                let heavy = Double(min(degree[node.id] ?? 0, BrainClusters.pieceDegree)) / Double(BrainClusters.pieceDegree)
                spots[node.id] = BrainArmSpot(layer: .memory, angle: polar.angle, share: polar.share, ring: order % memoryRings,
                                              size: hub ? 1 : min(1, pieceLeast + pieceMost * heavy.squareRoot()),
                                              latitude: latitude(node.id))
                placement.anchors[node.id] = anchor
            }
            placement.hub.merge(packed.hub) { first, _ in first }
            placement.counts.merge(packed.counts) { first, _ in first }
        }
        return placement
    }

    /// One area packed tight: each hub with the pieces it owns packed about it, heaviest nearest, the pieces no hub owns
    /// in a disc of their own, and then those discs packed together, largest first.
    private static func pack(_ group: SourceGroup, _ members: [MemoryMapNode], owners: [String: String],
                             degree: [String: Int]) -> Packed {
        let loose = "\u{1F}loose"
        let here = Set(members.map(\.id))
        var held: [String: [MemoryMapNode]] = [:]
        var hubs: [String] = []
        for node in members {
            let owner = owners[node.id].flatMap { here.contains($0) ? $0 : nil } ?? loose
            if owner == node.id { hubs.append(node.id) } else { held[owner, default: []].append(node) }
        }
        let order = hubs + (held[loose] == nil ? [] : [loose])
        var hub: [String: String] = [:]
        var counts: [String: Int] = [:]
        var discs: [(owner: String, ids: [String], spots: [(x: Double, y: Double)], radius: Double)] = []
        for owner in order {
            let pieces = (held[owner] ?? []).sorted { left, right in
                let a = degree[left.id] ?? 0
                let b = degree[right.id] ?? 0
                return a == b ? left.id < right.id : a > b
            }
            var circles = pieces.map { PackCircle(id: $0.id, radius: pieceRoom) }
            if owner != loose {
                circles.insert(PackCircle(id: owner, radius: hubRoom), at: 0)
                counts[owner] = pieces.count
                for piece in pieces { hub[piece.id] = owner }
            }
            let packed = BrainPacking.pack(circles, gap: pieceGap)
            discs.append((owner, circles.map(\.id), packed.spots, packed.radius))
        }
        discs.sort { $0.radius == $1.radius ? $0.owner < $1.owner : $0.radius > $1.radius }
        let outer = BrainPacking.pack(discs.map { PackCircle(id: $0.owner, radius: $0.radius) }, gap: clusterGap)
        var offsets: [String: (x: Double, y: Double)] = [:]
        for (at, disc) in discs.enumerated() {
            let centre = outer.spots[at]
            for (index, id) in disc.ids.enumerated() { offsets[id] = (centre.x + disc.spots[index].x, centre.y + disc.spots[index].y) }
        }
        return Packed(group: group, members: members, offsets: offsets, radius: max(outer.radius, pieceRoom), hub: hub, counts: counts)
    }

    private static func latitude(_ id: String) -> Double {
        SurfaceOrbit.unit(id, salt: latitudeSalt) * 2 - 1
    }

    /// Where a spot is on the flat side view, its share of the silhouette scaled by `reach` as it flies in.
    public static func flat(_ spot: BrainArmSpot, spin: Double = 0, reach: Double = 1) -> (x: Double, y: Double) {
        BrainShell.point(spot.angle + spin, share: spot.share * reach)
    }

    /// Where a spot is once the layers are drawn as nested shells turned about the brain's long axis: its latitude
    /// lifts it off the plane without pulling it in, so a cluster keeps its shape from any side.
    public static func orb(_ spot: BrainArmSpot, reach: Double = 1) -> SurfacePoint {
        orb(at: BrainShell.point(spot.angle, share: spot.share * reach), latitude: spot.latitude)
    }

    /// The same for a flat spot in world points, so a cluster growing out of its hub is lifted as it grows.
    public static func orb(at flat: (x: Double, y: Double), latitude: Double) -> SurfacePoint {
        let middle = BrainOutline.middle
        let offset = (x: flat.x - middle.x, y: flat.y - middle.y)
        let lift = latitude * mostLatitude
        return SurfacePoint(x: offset.x, y: offset.y, z: hypot(offset.x, offset.y) * sin(lift) * BrainOutline.halfHeight / BrainOutline.halfLength)
    }

    /// The chip an application's tile wears for how long ago it was last used, in whole days with a day the least and
    /// a month the most it says, nil where the runtime said no time.
    public static func ageChip(_ at: Date?, now: Date) -> String? {
        guard let at else { return nil }
        let days = max(1, Int((now.timeIntervalSince(at) / day).rounded(.up)))
        return days >= ageMost ? "\(ageMost)D+" : "\(days)D"
    }

    /// A day in seconds, and the most days an age chip counts before it says a month and more.
    public static let day: TimeInterval = 86_400
    public static let ageMost = 30
}
