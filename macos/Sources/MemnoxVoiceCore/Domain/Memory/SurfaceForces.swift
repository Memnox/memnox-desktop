import Foundation

// The console's own arithmetic, from memnox-client apps/app/lib/surface-world/forces.ts by way of the Tauri core's
// surface-forces.ts, so the Mac's map settles into the picture the console's does.

/// What the forces are set to, named for what they do to the picture. **Nothing here is random**: the same record seeds
/// the same places and every step is arithmetic on the last, so a map settles the same way each time it is opened.
public struct SurfaceForces: Equatable, Sendable {
    /// How hard two marks push each other away.
    public var repel: Double
    /// How long a line wants to be.
    public var link: Double
    /// How strongly the whole drawing is held together.
    public var gather: Double

    public init(repel: Double = 1, link: Double = 1, gather: Double = 1) {
        self.repel = repel
        self.link = link
        self.gather = gather
    }

    public static let standard = SurfaceForces()
}

/// One body the simulation moves: a node and how fast it is going.
public struct SurfaceBody: Equatable, Sendable {
    public let id: String
    public var x: Double
    public var y: Double
    public var vx: Double
    public var vy: Double

    public init(id: String, x: Double, y: Double, vx: Double = 0, vy: Double = 0) {
        self.id = id
        self.x = x
        self.y = y
        self.vx = vx
        self.vy = vy
    }
}

/// A line the forces pull along, by the ids of its two ends.
public struct SurfaceLink: Equatable, Sendable {
    public let from: String
    public let to: String

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

public enum SurfaceSettling {
    /// How much of its settling a drawing has left, from 1 to nothing. **This is what stops the marks shivering**: every
    /// force is scaled by it, so the arrangement converges and stops dead, wound back up only when something changes.
    public static let heatFull = 1.0
    public static let heatFade = 0.035
    public static let heatSpent = 0.005
    public static let heatStirred = 0.35
    /// Below this, nothing is moving enough to be worth another frame.
    public static let still = 0.05

    /// The room assumed for a body whose node is not on the map.
    private static let fallbackRoom = SurfaceRoom(rx: 20, ry: 20)
    /// How far apart two marks sit once nothing is pushing, over their own room.
    private static let breath = 1.25
    /// How hard two marks shove when they are actually touching.
    private static let contact = 1.0
    /// How far a mark is felt by one it is not touching.
    private static let reach = 900.0
    /// How hard it pushes at that distance, which is what opens the drawing out.
    private static let afar = 26000.0
    /// What a line settles to before the knob moves it.
    private static let linkLength = 128.0
    /// How hard a line pulls, as a share of the gap it closes each step.
    private static let linkPull = 0.05
    /// How hard the middle pulls, so a drawing with no lines is still one drawing.
    private static let gatherPull = 0.0023
    /// How tall the gathered drawing is against how wide: it settles as a wide ellipse, the shape of the frame.
    private static let oval = 0.82
    /// How much speed survives a step, which is what makes it settle rather than ring.
    private static let damping = 0.72
    /// The furthest anything may travel in one step, so nothing is flung off.
    private static let fastest = 34.0
    /// Each of a touching pair takes half the shove.
    private static let shoveShare = 0.5
    /// Where exactly overlapping marks are pushed apart: the earlier one goes left.
    private static let overlapPush = (x: -1.0, y: 0.0)

    /// One step of the simulation, in place; answers how fast the fastest body is going, which tells the loop it can stop.
    @discardableResult
    public static func step(_ bodies: inout [SurfaceBody], nodes: [String: Placed], links: [SurfaceLink], sized: Double,
                            forces: SurfaceForces, pinned: String? = nil, heat: Double = 1) -> Double {
        let rooms = bodies.map { body in nodes[body.id].map { SurfaceGeometry.roomFor($0, sized: sized) } ?? fallbackRoom }
        repelAll(&bodies, rooms: rooms, repel: forces.repel, heat: heat)
        pullLinks(&bodies, links: links, scale: forces.link, heat: heat)
        return integrate(&bodies, gatherScale: forces.gather, heat: heat, pinned: pinned)
    }

    /// Moves a pair apart by the same impulse in opposite directions.
    private static func pushApart(_ bodies: inout [SurfaceBody], _ first: Int, _ second: Int, _ impulseX: Double, _ impulseY: Double) {
        bodies[first].vx -= impulseX
        bodies[first].vy -= impulseY
        bodies[second].vx += impulseX
        bodies[second].vy += impulseY
    }

    /// One pair's push. Touching and merely near are two forces: touching is measured in the pair's own room, so a wide
    /// card clears across and a tall one down, while the far field is plain distance.
    private static func repelPair(_ bodies: inout [SurfaceBody], _ one: Int, _ two: Int, rooms: [SurfaceRoom], repel: Double, heat: Double) {
        let dx = bodies[two].x - bodies[one].x
        let dy = bodies[two].y - bodies[one].y
        let needX = (rooms[one].rx + rooms[two].rx) * breath
        let needY = (rooms[one].ry + rooms[two].ry) * breath
        let offX = dx / needX
        let offY = dy / needY
        let apart = hypot(offX, offY)
        if apart < 1 {
            let push = apart < SurfaceGeometry.epsilon ? overlapPush : (x: offX / apart, y: offY / apart)
            let shove = (1 - apart) * contact * repel * heat
            pushApart(&bodies, one, two, push.x * shove * needX * shoveShare, push.y * shove * needY * shoveShare)
            return
        }
        let span = hypot(dx, dy)
        if span > reach || span < SurfaceGeometry.epsilon { return }
        let far = ((afar / (span * span)) * repel * heat) / span
        pushApart(&bodies, one, two, dx * far, dy * far)
    }

    /// Every pair, which is fine at tens of nodes: a quadtree would be a second thing to get right for no visible gain.
    private static func repelAll(_ bodies: inout [SurfaceBody], rooms: [SurfaceRoom], repel: Double, heat: Double) {
        for one in bodies.indices {
            for two in bodies.indices where two > one {
                repelPair(&bodies, one, two, rooms: rooms, repel: repel, heat: heat)
            }
        }
    }

    private static func pullLinks(_ bodies: inout [SurfaceBody], links: [SurfaceLink], scale: Double, heat: Double) {
        var index: [String: Int] = [:]
        for (at, body) in bodies.enumerated() { index[body.id] = at }
        let want = linkLength * scale
        for link in links {
            guard let from = index[link.from], let to = index[link.to] else { continue }
            let dx = bodies[to].x - bodies[from].x
            let dy = bodies[to].y - bodies[from].y
            let span = hypot(dx, dy)
            if span < SurfaceGeometry.epsilon { continue }
            let pull = ((span - want) / span) * linkPull * heat
            pushApart(&bodies, from, to, -dx * pull, -dy * pull)
        }
    }

    /// Gathers, damps, caps and moves every body; answers the fastest speed.
    private static func integrate(_ bodies: inout [SurfaceBody], gatherScale: Double, heat: Double, pinned: String?) -> Double {
        let gather = gatherPull * gatherScale * heat
        var quickest = 0.0
        for at in bodies.indices {
            if bodies[at].id == pinned {
                bodies[at].vx = 0
                bodies[at].vy = 0
                continue
            }
            var body = bodies[at]
            body.vx = (body.vx - body.x * gather) * damping
            body.vy = (body.vy - (body.y / (oval * oval)) * gather) * damping
            let speed = hypot(body.vx, body.vy)
            if speed > fastest {
                body.vx = (body.vx / speed) * fastest
                body.vy = (body.vy / speed) * fastest
            }
            body.x += body.vx
            body.y += body.vy
            bodies[at] = body
            quickest = max(quickest, min(speed, fastest))
        }
        return quickest
    }
}
