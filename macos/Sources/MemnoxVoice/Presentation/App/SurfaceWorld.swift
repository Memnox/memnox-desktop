import MemnoxVoiceCore
import SwiftUI

/// The marks arranging themselves and settling, the console's flat surface on the Mac. Deterministic, since the seed is
/// the ring layout and nothing in a step is random, and it comes to a dead stop: every force is scaled by the heat
/// left, which is wound back up only when a node arrives, the marks change size, or one is picked up.
@MainActor
final class SurfaceWorld: ObservableObject {
    @Published private(set) var bodies: [SurfaceBody] = []
    /// The node held by a drag, which the forces leave where the pointer puts it.
    var pinned: String?

    private var heat = SurfaceSettling.heatFull
    private var nodes: [String: Placed] = [:]
    private var links: [SurfaceLink] = []
    private var sized = 1.0
    private var seeds: [Placed] = []
    private var ticking: Task<Void, Never>?

    /// How many steps one frame takes: the settling is worth watching, not sitting through.
    private static let perFrame = 2
    private static let frame: Duration = .milliseconds(16)

    /// Takes the drawing as it now is, keeping where every known node already stands and seeding the new ones.
    func sync(_ places: [Placed], links: [SurfaceLink], sized: Double) {
        let changed = places.map(\.id) != seeds.map(\.id) || links != self.links || sized != self.sized
        guard changed else { return }
        seeds = SurfaceGeometry.seeded(places)
        nodes = Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.links = links
        self.sized = sized
        var known: [String: SurfaceBody] = [:]
        for body in bodies { known[body.id] = body }
        bodies = seeds.map { known[$0.id] ?? SurfaceBody(id: $0.id, x: $0.x, y: $0.y) }
        stir(SurfaceSettling.heatFull)
    }

    /// Where a node stands now, in the world.
    func spot(_ id: String) -> (x: Double, y: Double)? {
        bodies.first { $0.id == id }.map { ($0.x, $0.y) }
    }

    /// A node put down by a drag: enough heat for its neighbours to make room, not enough to rearrange everything.
    func put(_ id: String, x: Double, y: Double) {
        guard let at = bodies.firstIndex(where: { $0.id == id }) else { return }
        bodies[at].x = x
        bodies[at].y = y
        bodies[at].vx = 0
        bodies[at].vy = 0
        stir(SurfaceSettling.heatStirred)
    }

    /// Arrange again: every node back to its seed, settling from the start.
    func reseed() {
        var places: [String: Placed] = [:]
        for seed in seeds { places[seed.id] = seed }
        bodies = bodies.map { body in
            guard let seed = places[body.id] else { return body }
            return SurfaceBody(id: body.id, x: seed.x, y: seed.y)
        }
        stir(SurfaceSettling.heatFull)
    }

    func stir(_ to: Double) {
        heat = max(heat, to)
        guard ticking == nil else { return }
        ticking = Task { [weak self] in
            while let self, !Task.isCancelled, self.advance() {
                try? await Task.sleep(for: Self.frame)
            }
        }
    }

    func stop() {
        ticking?.cancel()
        ticking = nil
    }

    /// One frame of settling; answers whether another is worth drawing.
    private func advance() -> Bool {
        var next = bodies
        for _ in 0..<Self.perFrame {
            SurfaceSettling.step(&next, nodes: nodes, links: links, sized: sized, forces: .standard, pinned: pinned, heat: heat)
            // No cooling while a node is held, or the rest of the map freezes around the drag.
            if pinned == nil { heat -= heat * SurfaceSettling.heatFade }
        }
        if heat < SurfaceSettling.heatSpent, pinned == nil {
            bodies = next.map { SurfaceBody(id: $0.id, x: $0.x, y: $0.y) }
            heat = 0
            ticking = nil
            return false
        }
        bodies = next
        return true
    }
}
