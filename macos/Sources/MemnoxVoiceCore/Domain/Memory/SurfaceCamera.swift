import Foundation

// The console's own arithmetic, from memnox-client apps/app/lib/surface-world/camera.ts by way of the Tauri core's
// surface-camera.ts, so the Mac's map is looked at as the console's is.

/// What the drawing is looked at from: a world point, and how close. Screen is world less camera, times zoom, plus the
/// frame's middle; every gesture is arithmetic on this one value, so panning never touches the layout.
public struct SurfaceCamera: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var k: Double

    public init(x: Double, y: Double, k: Double) {
        self.x = x
        self.y = y
        self.k = k
    }

    public static let atRest = SurfaceCamera(x: 0, y: 0, k: 1)

    /// How far the drawing is held off the edge of the frame when it is fitted.
    private static let margin = 28.0
    /// Fit never draws closer than life size: marks are sized to be read as drawn.
    private static let maxFitZoom = 1.0
    /// The smallest box side fitting divides by, so a single node cannot divide by zero.
    private static let minBoxSide = 1.0

    /// A world point on the screen it is drawn at.
    public func onScreen(_ point: (x: Double, y: Double), size: (width: Double, height: Double)) -> (x: Double, y: Double) {
        ((point.x - x) * k + size.width / 2, (point.y - y) * k + size.height / 2)
    }

    /// A point on the screen back in the world it came from.
    public func inWorld(_ point: (x: Double, y: Double), size: (width: Double, height: Double)) -> (x: Double, y: Double) {
        ((point.x - size.width / 2) / k + x, (point.y - size.height / 2) / k + y)
    }

    /// The camera, zoomed about a point that stays under the pointer.
    public func zoomed(by factor: Double, at pointer: (x: Double, y: Double), size: (width: Double, height: Double)) -> SurfaceCamera {
        let next = min(max(k * factor, SurfaceGeometry.zoomMin), SurfaceGeometry.zoomMax)
        if next == k { return self }
        let held = inWorld(pointer, size: size)
        return SurfaceCamera(x: held.x - (pointer.x - size.width / 2) / next, y: held.y - (pointer.y - size.height / 2) / next, k: next)
    }

    /// How much room the whole drawing takes in the world, marks and names.
    public static func extent(_ nodes: [Placed], sized: Double) -> (x: Double, y: Double, width: Double, height: Double)? {
        if nodes.isEmpty { return nil }
        var left = Double.infinity
        var right = -Double.infinity
        var top = Double.infinity
        var bottom = -Double.infinity
        for node in nodes {
            let room = SurfaceGeometry.roomFor(node, sized: sized)
            left = min(left, node.x - room.rx)
            right = max(right, node.x + room.rx)
            top = min(top, node.y - room.ry)
            bottom = max(bottom, node.y + room.ry)
        }
        return (left, top, right - left, bottom - top)
    }

    /// The camera that holds the whole drawing, which is what Fit means: fitted beside the controls' column rather than
    /// under it, because a node under the toolbar is the one node nobody can click.
    public static func fitted(_ nodes: [Placed], size: (width: Double, height: Double), sized: Double, inset: Double = 0) -> SurfaceCamera {
        guard let box = extent(nodes, sized: sized), size.width != 0, size.height != 0 else { return atRest }
        // The frame less the column, and never less than half of it: on a narrow frame the column is most of the width.
        let roomWidth = max(size.width - inset, size.width / 2) - margin * 2
        let roomHeight = size.height - margin * 2
        let fit = min(roomWidth / max(box.width, minBoxSide), roomHeight / max(box.height, minBoxSide))
        let k = min(maxFitZoom, max(SurfaceGeometry.zoomMin, fit))
        // Centred in the room it was fitted into, so the column covers margin.
        let middle = size.width - roomWidth / 2 - margin
        return SurfaceCamera(x: box.x + box.width / 2 - (middle - size.width / 2) / k, y: box.y + box.height / 2, k: k)
    }

    /// The share of the frame Fit lets the brain's marks fill across and down, the console's own, so a tile at the
    /// edge keeps its name on screen.
    public static let fillAcross = 0.84
    public static let fillDown = 0.76
    /// A brain whose marks stand on one spot is framed at least this wide, in world points, rather than at the most zoom.
    public static let leastSpan = 240.0

    /// The camera that holds these marks, each a world point with the room it takes, which is what Fit means on the
    /// brain: centred on the bounds of what is drawn and zoomed until it fills the frame, never an outline around nothing.
    public static func fitted(points: [(x: Double, y: Double, radius: Double)], size: (width: Double, height: Double)) -> SurfaceCamera {
        guard !points.isEmpty, size.width > 0, size.height > 0 else { return atRest }
        let left = points.map { $0.x - $0.radius }.min() ?? 0
        let right = points.map { $0.x + $0.radius }.max() ?? 0
        let top = points.map { $0.y - $0.radius }.min() ?? 0
        let bottom = points.map { $0.y + $0.radius }.max() ?? 0
        let across = max(leastSpan, right - left)
        let down = max(leastSpan, bottom - top)
        let k = min(size.width * fillAcross / across, size.height * fillDown / down)
        return SurfaceCamera(x: (left + right) / 2, y: (top + bottom) / 2, k: min(SurfaceGeometry.zoomMax, max(SurfaceGeometry.zoomMin, k)))
    }
}
