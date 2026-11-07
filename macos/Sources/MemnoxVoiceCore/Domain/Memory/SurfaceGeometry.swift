import Foundation

// The console's own arithmetic, from memnox-client apps/app/lib/surface-world/geometry.ts by way of the Tauri core's
// surface-geometry.ts, so the Mac's map settles as the console's and the other desktops' do.

/// One thing placed in the world, which is all the geometry needs of it. One unit means the same across and down, so a
/// force is a force rather than an ellipse and a resize never moves a node.
public struct Placed: Equatable, Sendable {
    public let id: String
    /// World points, with the origin in the middle of the drawing.
    public var x: Double
    public var y: Double
    /// 0 at the back and 1 at the front: how big it is drawn and what it stacks over. Set where the node is placed and
    /// never recomputed from where it ends up, or panning the map would resize every mark on it.
    public var depth: Double
    /// How wide the mark is before depth scales it.
    public let width: Double
    /// How tall it is where that is not its width; nil means round or square.
    public let height: Double?
    /// False where the mark writes its own name inside itself, as a card does.
    public let captioned: Bool
    /// The name under the mark, which is the widest part of a node.
    public let label: String
    /// How far in front of or behind the drawing's plane it floats, in world points: the third axis the map turns
    /// about. The forces never move it, so the settling stays flat and the depth is only how it is looked at.
    public var lift: Double

    public init(id: String, x: Double, y: Double, depth: Double, width: Double, height: Double? = nil, captioned: Bool = true,
                label: String, lift: Double = 0) {
        self.id = id
        self.x = x
        self.y = y
        self.depth = depth
        self.width = width
        self.height = height
        self.captioned = captioned
        self.label = label
        self.lift = lift
    }
}

/// Anything carrying a place on the surface, so the layout can move a node without knowing what else it holds.
public protocol SurfacePlaced {
    var place: Placed { get set }
}

extension Placed: SurfacePlaced {
    public var place: Placed {
        get { self }
        set { self = newValue }
    }
}

/// A line's visible part, from the edge of one mark to the edge of the other.
public struct SurfaceLine: Equatable, Sendable {
    public let x1: Double
    public let y1: Double
    public let x2: Double
    public let y2: Double
}

/// How much room one node needs, as half a width and half a height, name included.
public struct SurfaceRoom: Equatable, Sendable {
    public let rx: Double
    public let ry: Double
}

public enum SurfaceGeometry {
    /// How far the camera may be pushed either way.
    public static let zoomMin = 0.45
    public static let zoomMax = 12.0
    /// How big a mark may be drawn, over whatever the camera is doing.
    public static let nodeSizeMin = 0.7
    public static let nodeSizeMax = 1.8
    /// How wide a name is under a mark, and how far below it sits.
    public static let nameWide = 112.0
    public static let nameBelow = 18.0
    /// Below this a direction component counts as zero, so nothing divides by it.
    public static let epsilon = 1e-6
    /// How far a ring is squashed vertically: a screen is wider than tall and a name is written across. Only the seed.
    public static let flatten = 0.7
    /// Where the first node on a ring goes: straight up, then clockwise.
    public static let start = -Double.pi / 2
    /// What one layout fraction is worth once it lands in the world.
    public static let world = 1100.0

    /// Scale at the back of the drawing, and how much more the front adds.
    private static let backScale = 0.84
    private static let depthScaleRange = 0.32
    /// The air left between a line's end and the mark it points at.
    private static let air = 5.0
    /// The middle of a layout written in fractions of a notional card.
    static let layoutMiddle = 0.5

    /// Depth alone; what somebody set on the toolbar multiplies this.
    public static func scaleOf(_ depth: Double) -> Double {
        backScale + depth * depthScaleRange
    }

    /// Kept inside 0 to 1, for a depth read off a place before anything moved.
    public static func depthAt(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    /// Half a node's mark plus a little air, at the size it is drawn.
    public static func edgeOf(_ node: Placed, sized: Double) -> Double {
        (node.width / 2) * scaleOf(node.depth) * sized + air
    }

    /// Half of an extent over the share of it a unit ray spends on that axis.
    private static func reachAlong(_ halfExtent: Double, _ component: Double) -> Double {
        abs(component) < epsilon ? .infinity : halfExtent / abs(component)
    }

    /// How far the mark reaches along one direction from its middle: a card is measured as the box it is, so a line
    /// arrives at its edge rather than a card's width short of it on one axis and inside it on the other.
    private static func reachOf(_ node: Placed, sized: Double, unitX: Double, unitY: Double) -> Double {
        guard let height = node.height else { return edgeOf(node, sized: sized) }
        let scale = scaleOf(node.depth) * sized
        let across = reachAlong((node.width / 2) * scale, unitX)
        let down = reachAlong((height / 2) * scale, unitY)
        return min(across, down) + air
    }

    /// The visible part of a line: centre to centre, less both marks; nil where trimming would turn it inside out, as a
    /// node dragged on top of another does.
    public static func between(_ from: Placed, _ to: Placed, sized: Double) -> SurfaceLine? {
        let span = hypot(to.x - from.x, to.y - from.y)
        if span == 0 { return nil }
        let unitX = (to.x - from.x) / span
        let unitY = (to.y - from.y) / span
        let start = reachOf(from, sized: sized, unitX: unitX, unitY: unitY)
        let end = reachOf(to, sized: sized, unitX: unitX, unitY: unitY)
        if span <= start + end { return nil }
        return SurfaceLine(x1: from.x + unitX * start, y1: from.y + unitY * start, x2: to.x - unitX * end, y2: to.y - unitY * end)
    }

    /// How much room one node needs, name included: the name is the part that collides, so two marks a comfortable
    /// distance apart can still write their names across each other.
    public static func roomFor(_ node: Placed, sized: Double) -> SurfaceRoom {
        let scale = scaleOf(node.depth) * sized
        let wide = node.captioned ? max(node.width, nameWide) : node.width
        let tall = node.height ?? node.width
        let below = node.captioned ? nameBelow : 0
        return SurfaceRoom(rx: (wide / 2) * scale, ry: (tall / 2) * scale + below)
    }

    /// `count` angles spread over `width`, centred on `middle`. One child sits exactly on its parent's angle, so a hub
    /// with one thing under it reads as a line out from the centre instead of a lean.
    public static func fan(_ middle: Double, _ width: Double, _ count: Int, whole: Bool = false) -> [Double] {
        if count == 0 { return [] }
        if count == 1 { return [middle] }
        // A full circle leaves no gap at the end, or the last node lands on the first.
        let step = whole ? width / Double(count) : width / Double(count - 1)
        let from = whole ? middle : middle - width / 2
        return (0..<count).map { from + Double($0) * step }
    }

    /// One point on a squashed ring around a centre, with the depth it lands at.
    public static func at(_ angle: Double, _ radius: Double, centre: (x: Double, y: Double) = (0.5, 0.5))
        -> (x: Double, y: Double, depth: Double) {
        let y = centre.y + sin(angle) * radius * flatten
        return (centre.x + cos(angle) * radius, y, depthAt(y))
    }

    /// How far a set of values sits off the layout middle, by its bounding middle.
    private static func offsetToMiddle(_ values: [Double]) -> Double {
        guard let low = values.min(), let high = values.max() else { return 0 }
        return layoutMiddle - (low + high) / 2
    }

    /// The whole drawing shifted into the middle of the box, whatever shape the data gave it. Only a shift, never a
    /// squeeze: the distance between two nodes is the one thing this drawing is saying.
    public static func centred<T: SurfacePlaced>(_ nodes: [T]) -> [T] {
        if nodes.isEmpty { return [] }
        let shiftX = offsetToMiddle(nodes.map(\.place.x))
        let shiftY = offsetToMiddle(nodes.map(\.place.y))
        if shiftX == 0, shiftY == 0 { return nodes }
        return nodes.map { node in
            var moved = node
            moved.place.x += shiftX
            moved.place.y += shiftY
            moved.place.depth = depthAt(node.place.y + shiftY)
            return moved
        }
    }

    /// A layout written in fractions, as bodies in the world.
    public static func seeded<T: SurfacePlaced>(_ nodes: [T]) -> [T] {
        nodes.map { node in
            var moved = node
            moved.place.x = (node.place.x - layoutMiddle) * world
            moved.place.y = (node.place.y - layoutMiddle) * world * flatten
            return moved
        }
    }
}
