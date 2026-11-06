import MemnoxVoiceCore
import SwiftUI

/// How the brain is drawn: the size of each layer's mark, its glow, the envelopes, the spokes, the names, and how far
/// an interaction swells or dims.
enum BrainLook {
    /// A memory dot's least size and what weight adds, a core star, a rule's disc, an application's tile and a
    /// person's avatar, in world points.
    static let dot = 1.6
    static let dotGrowth = 4.4
    static let star = 4.2
    static let rule = 7.0
    static let tile = 12.0
    static let avatar = 6.5
    /// The least a mark is ever drawn, in screen points.
    static let leastDot = 1.0
    /// The halo around every dot, as times its radius and a share of its light, and how many marks a brain holds
    /// before the halos fade so a dense cluster is not one glare.
    static let glowScale = 1.8
    static let glowShare = 0.18
    static let denseFrom = 300.0
    /// A memory hub's soft light in its colour, and the white heart it is lit with.
    static let haloScale = 3.0
    static let haloShare = 0.4
    static let heartShare = 0.42
    /// A core star's inner corners, as a share of its points.
    static let starWaist = 0.26
    /// A star blooming in grows this much at the height of its pop.
    static let bloomGrowth = 0.8
    /// A hovered mark swells this much and wears a halo this many times its size.
    static let swellGrowth = 0.7
    static let swellHalo = 3.0
    /// Light is drawn in this many steps, so thousands of twinkling dots still fill in a few dozen paths.
    static let lightSteps = 5
    /// What the focus, a picked area or a search leaves out keeps this share of its light, and a picked area is lifted.
    static let unlit = 0.22
    static let unmatched = 0.1
    static let areaLift = 0.25
    /// A picked area's wash, at the height of its bloom.
    static let wedgeShare = 0.1
    static let spokeShare = 0.26
    static let skillSpokeShare = 0.14
    /// The spokes from the core to each area's hub, and from the memory index to what it lists.
    static let coreSpokeShare = 0.5
    static let coreSpokeWidth = 1.2
    static let indexSpokeShare = 0.16
    /// How far a spoke bows off the straight line, as a share of its length, so the spokes read as a web.
    static let spokeBend = 0.16
    static let litShare = 0.9
    static let lineWidth = 0.7
    static let litWidth = 1.4
    /// The envelopes: the silhouette around what is drawn, each area's ring, and the rules ring.
    static let bandCorners = 240
    static let bandDash: [CGFloat] = [1, 5]
    static let envelopePad = 0.05
    static let areaRingShare = 0.3
    static let ringShare = 0.5
    static let ringGlow = 6.0
    static let ringGlowShare = 0.12
    static let outlineShare = 0.32
    /// An area's hub at the middle of its cluster, in world points, and its ring's line.
    static let areaHub = 5.0
    /// The core's white glow, as times the core's reach.
    static let coreGlow = 1.6
    static let coreGlowShare = 0.32
    /// A heartbeat's line, its glow, and how bright it is at its strongest.
    static let heartWidth = 1.5
    static let heartGlow = 10.0
    static let heartLight = 0.32
    /// A spark's bead and its trail.
    static let sparkRadius = 3.2
    static let sparkGlow = 4.0
    /// The ring around a picked, walked to or matched mark, this far outside it.
    static let ringGap = 4.0
    static let ringWidth = 1.5
    /// The count bubble a memory hub wears, off its upper right.
    static let bubble: CGFloat = 9
    static let bubbleSize: CGFloat = 9
    static let bubbleShift = 0.9
    /// An application's number badge off its upper left and its age chip under it, shown once the tile is this big.
    static let badgeFrom = 8.0
    static let badgeSize: CGFloat = 8
    static let badge: CGFloat = 7
    static let chipGap = 3.0
    /// A person's initials, once the avatar is this big, at this share of its radius.
    static let initialsFrom = 7.0
    static let initialsShare = 0.85
    /// A band's name: its size, its spacing and how far past the band's edge it is written.
    static let bandName: CGFloat = 10
    static let bandTracking: CGFloat = 3
    static let bandLift = 0.035
    /// A name: its size, the air around it inside its backing, how far above the mark, how much of the backing shows.
    static let nameSize: CGFloat = 11
    static let namePadding: CGFloat = 4
    static let nameRadius: CGFloat = 4
    static let nameGap = 6.0
    static let nameWide: CGFloat = 180
    static let nameTall: CGFloat = 40
    static let backingShare = 0.82
    /// The most names one frame measures, the most prominent first, so a frame costs the same however big the brain.
    static let mostNames = 160
    /// From this zoom every mark on the screen may be named, where its name has room.
    static let namesAllFrom = 1.6
    /// Past this many rules their icons are left off, since they would be smaller than they read.
    static let mostRuleIcons = 160
    static let iconShare = 1.1
    /// A press counts as on a mark within this many points of it, however small it is drawn.
    static let fingertip = 6.0
    /// An application's logo inside its tile and a source's inside its hub, as a share of the mark, and the least
    /// a logo is drawn at, below which the mark keeps its glyph.
    static let logoShare = 1.4
    static let leastLogo: CGFloat = 10
    /// How long the brain waits after a hand leaves before it turns on its own again.
    static let resumeAfter: TimeInterval = 2.5
    /// The room Fit leaves around each mark for its name and badges, in world points.
    static let fitRoom = 24.0
    /// The instruction files at the heart of the core shine this many times a skill's star.
    static let heartStar = 2.0
    /// A spark with no node to stand on runs along an angle drawn from its id with this salt.
    static let sparkSalt: UInt64 = 101
    /// A fling keeps the frame clock going this many coast times, by when it has all but stopped.
    static let coastSettle = 4.0
    /// The corners of a core star, every other one drawn in.
    static let starCorners = 8
    /// The Timeline's axis and lane names, written this far left of the oldest.
    static let axisShare = 0.3
    static let laneInset = 40.0
    static var laneLabelX: Double { -BrainOutline.halfLength - laneInset }
    /// A tissue grain's largest size in world points, its line, and how much light each band of it keeps, so the
    /// silhouette reads as a shape while the memory drawn over it stays the brightest thing on the canvas.
    static let grain = 3.4
    static let grainWidth = 0.8
    static let tissueShares: [TissueBand: Double] = [.gold: 0.34, .violet: 0.34, .teal: 0.28, .pale: 0.15]
    /// The share of the silhouette the tissue fills at its densest, under which a smaller brain thins its grains.
    static let tissueFull = 0.9
    /// A memory mark this big on the screen is drawn as a wireframe tetrahedron, smaller ones stay a dot.
    static let wireFrom = 3.0
    static let wireWidth = 1.0
    /// What the pointer's lens adds to a mark's size at its middle, and from how much pull a grain turns white.
    static let lensGrowth = 1.3
    static let lensWhite = 0.08
    static let lensShare = 0.85
    /// Spreads the marks' tumbles apart by index without hashing an id every frame.
    static let goldenShare = 0.618_033_988_749_895
    /// The leader from a hovered mark to its card: its line, the dot on the mark and the square at the card.
    static let leaderWidth = 1.0
    static let leaderDot = 2.4
    static let leaderSquare = 5.5
    static let leaderShare = 0.85
    /// The tour's labels: how far out from the middle of the canvas each stands from its part, the room kept clear
    /// along the edges and above the deck, how many at most, and their type.
    static let tagReach = 120.0
    static let tagEdge = 28.0
    static let tagFoot = 210.0
    static let tagWidth = 210.0
    static let mostTags = 4
    static let tagName: CGFloat = 11
    static let tagDetail: CGFloat = 9.5
    static let tagTracking: CGFloat = 1.4
    static let tagGap = 9.0
    /// What the envelope and the tissue keep of their light while the areas slide out of them.
    static let shellOpen = 0.6
}

/// The brain's colours: each memory area its own from the references' warm and cool run, the core white, the rules
/// gold, the applications blue, and the avatars' run.
enum ArmsInk {
    static let areas: [Color] = [Color(hex: 0xFF8A3D), Color(hex: 0xFF5A5F), Color(hex: 0xF5C542), Color(hex: 0x4C8DFF),
                                 Color(hex: 0x2DD4BF), Color(hex: 0x4ADE80), Color(hex: 0xA78BFA)]
    static let skills = Memnox.Console.Brain.ink
    static let rules = Color(hex: 0xF5B942)
    static let applications = Color(hex: 0x5AA9FF)
    /// As many as the console's face inks, so a person's colour index means the same on both.
    static let avatars: [Color] = [Color(hex: 0x6366F1), Color(hex: 0x0EA5E9), Color(hex: 0x14B8A6), Color(hex: 0x22C55E),
                                   Color(hex: 0xF97316), Memnox.Console.primary]
    static let match = Memnox.Console.primary

    /// The slots a dot is painted from: one to each area colour, then the core, the rules and the applications.
    static var slots: Int { areas.count + BrainLayer.allCases.count - 1 }

    static func slot(_ layer: BrainLayer, area: Int) -> Int {
        switch layer {
        case .memory: area % areas.count
        case .skills: areas.count
        case .rules: areas.count + 1
        case .applications: areas.count + 2
        }
    }

    static func of(slot: Int) -> Color {
        if slot < areas.count { return areas[slot] }
        switch slot - areas.count {
        case 0: return skills
        case 1: return rules
        default: return applications
        }
    }

    static func of(_ layer: BrainLayer) -> Color { of(slot: slot(layer, area: 0)) }

    /// The tissue's bands: the gold and the violet of the reference brains along the rim, teal under them, pale inside.
    static func of(_ band: TissueBand) -> Color {
        switch band {
        case .gold: Memnox.Console.Brain.instructions
        case .violet: Memnox.Console.Brain.team
        case .teal: Memnox.Console.Brain.servers
        case .pale: Memnox.Console.Brain.ink
        }
    }
}

/// What a frame needs beyond the marks' own spots: the turn, the camera, the light of the moment and what is in focus.
struct BrainScene {
    let mode: BrainMode
    let camera: SurfaceCamera
    let size: CGSize
    let turn: SurfaceTurn
    /// How far the opening has come, in seconds, nil once it is over.
    let opening: Double?
    let still: Bool
    let idle: Double
    let focus: String?
    let selected: String?
    let keyed: String?
    let over: String?
    let swell: Double
    let area: SourceGroup?
    let areaShare: Double
    let allLabels: Bool
    let working: Set<String>
    let sparks: [BrainSpark]
    let now: Double
    /// What the canvas search matched, by index, nil while nothing is searched.
    let matches: Set<Int>?
    /// Where the pointer's lens is, nil while the pointer is away, on a card or holding the ground.
    let lens: CGPoint?
    /// How far the tour has each assembly open, and its playhead, nil while no tour runs.
    let pose: TourPose
    let playhead: Double?
}

/// Draws one frame of the brain in a handful of fills and strokes however many marks there are: the picked area's
/// wash, the envelopes around what is drawn, the heartbeat, the spokes, the marks in batches of colour and light, the
/// hubs' counts and the tiles' badges, the sparks, the rings on the picked and the matched, and the names.
struct BrainPainter {
    let prepared: BrainPrepared
    let frame: BrainFrame
    let scene: BrainScene

    private func screen(_ point: (x: Double, y: Double)) -> CGPoint {
        let at = scene.camera.onScreen(point, size: (scene.size.width, scene.size.height))
        return CGPoint(x: at.x, y: at.y)
    }

    /// A spot on the layers at an angle and a share, on the flat view or the orbiting shells.
    private func onLayers(_ angle: Double, share: Double) -> CGPoint {
        switch scene.mode {
        case .map, .timeline:
            return screen(BrainShell.point(angle, share: share))
        case .orbs:
            let spot = BrainArmSpot(layer: .memory, angle: angle, share: share, ring: 0, size: 0, latitude: 0)
            let seen = SurfaceOrbit.seen(BrainArms.orb(spot), turn: scene.turn)
            let middle = BrainOutline.middle
            return screen((seen.x + middle.x, seen.y + middle.y))
        }
    }

    private func at(_ index: Int) -> CGPoint { CGPoint(x: frame.x[index], y: frame.y[index]) }

    /// How far out what the rings ring reaches: the core and the memory clusters.
    private var inside: Double { max(prepared.reaches[.skills] ?? 0, prepared.reaches[.memory] ?? 0) }

    /// How far out anything reaches, which the heartbeat and the sparks cross.
    private var outside: Double { prepared.reaches.values.max() ?? 0 }

    /// The zoom marks and lines are drawn at, by its square root so zooming opens room rather than only growing.
    private var grow: Double { scene.camera.k.squareRoot() }

    func paint(_ context: inout GraphicsContext) {
        guard !prepared.nodes.isEmpty else { return }
        let near = neighbours()
        switch scene.mode {
        case .map:
            wedge(&context)
            tissue(&context, near: near)
            envelopes(&context)
            heartbeat(&context)
        case .orbs:
            heartbeat(&context)
        case .timeline:
            axis(&context)
        }
        lines(&context, near: near)
        marks(&context, near: near)
        avatars(&context, near: near)
        if scene.mode == .map { counts(&context) }
        badges(&context)
        sparks(&context)
        rings(&context)
        leader(&context)
        if scene.playhead == nil { names(&context) } else { tourLabels(&context) }
    }

    private func neighbours() -> Set<Int>? {
        guard let focus = scene.focus, let at = prepared.index[focus] else { return nil }
        var near: Set<Int> = [at]
        for line in prepared.lines where line.from == at || line.to == at {
            near.insert(line.from)
            near.insert(line.to)
        }
        if let hub = prepared.hubOf[at] { near.insert(hub) }
        return near
    }

    /// How much of its light a mark keeps under the focus, a picked area and a search.
    private func kept(_ index: Int, near: Set<Int>?) -> Double {
        var share = 1.0
        if let matches = scene.matches, !matches.contains(index) { share *= BrainLook.unmatched }
        if let near, !near.contains(index) { share *= BrainLook.unlit }
        if let area = scene.area {
            let inside = prepared.areaOf[index] == area
            share *= inside ? 1 + BrainLook.areaLift * scene.areaShare : 1 - (1 - BrainLook.unlit) * scene.areaShare
        }
        return share
    }

    /// How much light a memory area's envelope and hub have on the opening.
    private func areaLight(_ order: Int) -> Double {
        guard let opening = scene.opening else { return 1 }
        return BrainMotion.opening(.memory, ring: order % BrainArms.memoryRings, seconds: opening, still: scene.still).light
    }

    /// The picked area's disc washed in its colour, as far as it has bloomed.
    private func wedge(_ context: inout GraphicsContext) {
        guard let area = scene.area, scene.areaShare > 0, let order = prepared.areas.firstIndex(where: { $0.group == area }) else { return }
        let centre = frame.areas[order]
        let radius = prepared.areas[order].radius * scene.camera.k
        let ink = ArmsInk.of(slot: prepared.areaSlots[area] ?? 0)
        context.fill(Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)),
                     with: .color(ink.opacity(BrainLook.wedgeShare * scene.areaShare)))
    }

    /// How far the pointer's lens pulls a spot on the screen, none while there is no lens.
    private func pull(_ at: CGPoint) -> Double {
        guard let lens = scene.lens else { return 0 }
        return BrainLens.pull(distance: hypot(at.x - lens.x, at.y - lens.y))
    }

    /// A tetrahedron's six edges about a spot, its corners this far out, tumbled to this phase.
    private static func wire(_ path: inout Path, _ centre: CGPoint, _ radius: Double, spin: Double, seconds: Double) {
        let corners = BrainTissue.corners(spin: spin, seconds: seconds).map { CGPoint(x: centre.x + $0.x * radius, y: centre.y + $0.y * radius) }
        for (from, to) in BrainTissue.edges {
            path.move(to: corners[from])
            path.addLine(to: corners[to])
        }
    }

    /// The silhouette filled with tumbling wireframe grains as far as the envelope reaches, thinned for a small brain
    /// so it never reads denser than a full one, and whitened and swollen under the pointer's lens.
    private func tissue(_ context: inout GraphicsContext, near: Set<Int>?) {
        let arrived = scene.opening.map { BrainMotion.opening(.memory, seconds: $0, still: scene.still).light } ?? 1
        guard inside > 0, arrived > 0 else { return }
        let reach = inside + BrainLook.envelopePad
        // The grains a brain keeps go with its area, which is the square of its reach.
        let kept = min(1, (reach / BrainLook.tissueFull) * (reach / BrainLook.tissueFull))
        let quiet = near == nil && scene.area == nil && scene.matches == nil ? 1 : BrainLook.unlit
        let steps = BrainLook.lightSteps
        let base = BrainLook.grain * max(grow, BrainLook.leastDot)
        let seconds = scene.still ? 0 : scene.idle
        let seen = CGRect(origin: .zero, size: scene.size).insetBy(dx: -base * 2, dy: -base * 2)
        var bands = [TissueBand: Path]()
        var white = Array(repeating: Path(), count: steps)
        let opened = 1 - BrainLook.shellOpen * max(scene.pose.areas, scene.pose.apart)
        for grain in BrainTissue.grains where grain.rank < kept {
            let spot = BrainTour.scattered(BrainShell.point(grain.angle, share: grain.share * reach), seed: grain.rank, apart: scene.pose.apart)
            let centre = screen(spot)
            guard seen.contains(centre) else { continue }
            let pulled = pull(centre)
            let radius = base * grain.size * (1 + BrainLook.lensGrowth * pulled)
            if pulled > BrainLook.lensWhite {
                Self.wire(&white[min(Int(pulled * Double(steps)), steps - 1)], centre, radius, spin: grain.spin, seconds: seconds)
            } else {
                Self.wire(&bands[grain.band, default: Path()], centre, radius, spin: grain.spin, seconds: seconds)
            }
        }
        for (band, path) in bands {
            context.stroke(path, with: .color(ArmsInk.of(band).opacity((BrainLook.tissueShares[band] ?? 0) * arrived * quiet * opened)),
                           lineWidth: BrainLook.grainWidth)
        }
        for step in 0..<steps {
            let light = (Double(step) + 1) / Double(steps)
            context.stroke(white[step], with: .color(Memnox.Console.Brain.ink.opacity(BrainLook.lensShare * light * arrived)),
                           lineWidth: BrainLook.grainWidth)
        }
    }

    /// The envelopes drawn only around what exists, lit as it arrives: the silhouette just past the core and the
    /// clusters, each area's dotted ring, the core's glow, and the rules ring drawing itself round.
    private func envelopes(_ context: inout GraphicsContext) {
        let quiet = Memnox.Console.Brain.outline
        let arrived = scene.opening.map { BrainMotion.opening(.memory, seconds: $0, still: scene.still).light } ?? 1
        if inside > 0, arrived > 0 {
            var outline = Path()
            outline.addLines(BrainShell.outline(share: inside + BrainLook.envelopePad, corners: BrainLook.bandCorners).map(screen))
            outline.closeSubpath()
            let opened = 1 - BrainLook.shellOpen * max(scene.pose.areas, scene.pose.apart)
            context.stroke(outline, with: .color(quiet.opacity(BrainLook.outlineShare * arrived * opened)), lineWidth: Memnox.Stroke.hairline)
        }
        for (order, area) in prepared.areas.enumerated() {
            let light = areaLight(order)
            guard light > 0 else { continue }
            let centre = frame.areas[order]
            let radius = area.radius * scene.camera.k
            let ink = ArmsInk.of(slot: prepared.areaSlots[area.group] ?? 0)
            context.stroke(Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)),
                           with: .color(ink.opacity(BrainLook.areaRingShare * light)),
                           style: StrokeStyle(lineWidth: Memnox.Stroke.hairline, dash: BrainLook.bandDash))
        }
        let middle = screen(BrainOutline.middle)
        let core = scene.opening.map { BrainMotion.opening(.skills, seconds: $0, still: scene.still) } ?? .settled
        let glow = BrainShell.reach(0) * (prepared.reaches[.skills] ?? 0) * BrainLook.coreGlow * scene.camera.k * core.reach
        if glow > 0 {
            context.fill(Path(ellipseIn: CGRect(x: middle.x - glow, y: middle.y - glow, width: glow * 2, height: glow * 2)),
                         with: .radialGradient(Gradient(colors: [ArmsInk.skills.opacity(BrainLook.coreGlowShare * (core.light + core.bloom)), .clear]),
                                               center: middle, startRadius: 0, endRadius: glow))
        }
        guard let rules = prepared.reaches[.rules] else { return }
        let drawn = BrainMotion.ringDrawn(seconds: scene.opening ?? BrainMotion.openingLength, still: scene.still)
        guard drawn > 0 else { return }
        var ring = Path()
        // From the crown round, so the ring draws itself the way the rules light.
        let corners = BrainLook.bandCorners
        let out = rules * (1 + BrainTour.ringOut * scene.pose.rules)
        ring.addLines((0...corners).map { onLayers(BrainArms.start + Double($0) / Double(corners) * 2 * Double.pi, share: out) })
        let trimmed = ring.trimmedPath(from: 0, to: drawn)
        let whole = 1 - scene.pose.apart
        context.stroke(trimmed, with: .color(ArmsInk.rules.opacity(BrainLook.ringGlowShare * whole)), lineWidth: BrainLook.ringGlow)
        context.stroke(trimmed, with: .color(ArmsInk.rules.opacity(BrainLook.ringShare * whole)), lineWidth: Memnox.Stroke.hairline)
    }

    /// A soft line of light leaving the core every few heartbeats, out past everything drawn.
    private func heartbeat(_ context: inout GraphicsContext) {
        guard !scene.still, scene.opening == nil, outside > 0, let beat = BrainMotion.heartbeat(seconds: scene.idle) else { return }
        var path = Path()
        let corners = BrainLook.bandCorners
        path.addLines((0..<corners).map { onLayers(Double($0) / Double(corners) * 2 * Double.pi, share: beat.share * outside) })
        path.closeSubpath()
        let ink = ArmsInk.skills.opacity(BrainLook.heartLight * beat.strength)
        context.stroke(path, with: .color(ink.opacity(BrainLook.ringGlowShare)), lineWidth: BrainLook.heartGlow)
        context.stroke(path, with: .color(ink), lineWidth: BrainLook.heartWidth)
    }

    /// The Timeline's lanes named at their left, what says no time named over its column, and the moments along the foot.
    private func axis(_ context: inout GraphicsContext) {
        guard let last = prepared.lanes.last else { return }
        let foot = last.y + BrainTimeline.laneHeight / 2 + BrainTimeline.laneGap * BrainLook.axisShare
        var line = Path()
        line.move(to: screen((-BrainOutline.halfLength, foot)))
        line.addLine(to: screen((BrainOutline.halfLength, foot)))
        context.stroke(line, with: .color(Memnox.Console.Brain.outline.opacity(BrainLook.outlineShare)), lineWidth: Memnox.Stroke.hairline)
        for lane in prepared.lanes {
            draw(&context, BrainWords.layerName(lane.layer), at: screen((BrainLook.laneLabelX, lane.y)), anchor: .trailing, ink: ArmsInk.of(lane.layer))
        }
        for tick in prepared.ticks {
            draw(&context, BrainWords.day(tick.at), at: screen((tick.x, foot)), anchor: .top, ink: Memnox.Console.Brain.quiet)
        }
        for row in prepared.undated {
            var point = screen((BrainLook.laneLabelX, row.y))
            // A lane with nothing dated has its row on the lane's middle, so the row's name goes under the lane's.
            if let lane = prepared.lanes.first(where: { $0.layer == row.layer }), abs(screen((0, lane.y)).y - point.y) < BrainLook.nameTall / 2 {
                point.y += BrainLook.nameTall / 2
            }
            draw(&context, BrainWords.undated, at: point, anchor: .trailing, ink: Memnox.Console.Brain.faint)
        }
    }

    /// A spoke bowed a little off the straight line, so many spokes read as a web rather than a fan of rays.
    static func spoke(_ path: inout Path, from: CGPoint, to: CGPoint) {
        let across = CGPoint(x: to.x - from.x, y: to.y - from.y)
        let bend = BrainLook.spokeBend
        let control = CGPoint(x: (from.x + to.x) / 2 - across.y * bend, y: (from.y + to.y) / 2 + across.x * bend)
        path.move(to: from)
        path.addQuadCurve(to: to, control: control)
    }

    /// The core's spoke to each area's hub in the area's colour, each piece's to its hub and each hub's to its area,
    /// the memory index's to what it lists, and what the focus or the picked area touches drawn bright over them.
    private func lines(_ context: inout GraphicsContext, near: Set<Int>?) {
        guard scene.mode != .timeline || scene.focus != nil else { return }
        var spokes = Array(repeating: Path(), count: ArmsInk.slots)
        var lit = Path()
        let middle = onLayers(0, share: 0)
        let focusAt = scene.focus.flatMap { prepared.index[$0] }
        let quiet = near == nil && scene.area == nil && scene.matches == nil ? 1 : BrainLook.unlit
        let width = BrainLook.lineWidth * max(grow, BrainLook.leastDot)
        if scene.mode != .timeline {
            for (order, area) in prepared.areas.enumerated() {
                let light = areaLight(order)
                guard light > 0 else { continue }
                var core = Path()
                Self.spoke(&core, from: middle, to: frame.areas[order])
                let ink = ArmsInk.of(slot: prepared.areaSlots[area.group] ?? 0)
                context.stroke(core, with: .color(ink.opacity(BrainLook.coreSpokeShare * light * quiet)),
                               lineWidth: BrainLook.coreSpokeWidth * max(grow, BrainLook.leastDot))
            }
            for index in prepared.nodes.indices where frame.light[index] > 0 {
                let layer = prepared.spots[index].layer
                guard layer == .memory || layer == .skills, index != prepared.indexAt else { continue }
                let from = prepared.hubOf[index].map(at) ?? prepared.areaAt[index].map { frame.areas[$0] } ?? middle
                spokes[prepared.ink[index]].move(to: from)
                spokes[prepared.ink[index]].addLine(to: at(index))
                let picked = scene.area != nil && prepared.areaOf[index] == scene.area
                if picked || focusAt == index || (focusAt != nil && prepared.hubOf[index] == focusAt) {
                    Self.spoke(&lit, from: from, to: at(index))
                }
            }
            if !prepared.indexLines.isEmpty {
                var listed = Path()
                for line in prepared.indexLines where frame.light[line.from] > 0 && frame.light[line.to] > 0 {
                    Self.spoke(&listed, from: at(line.from), to: at(line.to))
                }
                context.stroke(listed, with: .color(ArmsInk.skills.opacity(BrainLook.indexSpokeShare * quiet)), lineWidth: width)
            }
        }
        if let focusAt {
            for line in prepared.lines where line.from == focusAt || line.to == focusAt {
                Self.spoke(&lit, from: at(line.from), to: at(line.to))
            }
        }
        for slot in 0..<ArmsInk.slots {
            let share = slot == ArmsInk.slot(.skills, area: 0) ? BrainLook.skillSpokeShare : BrainLook.spokeShare
            context.stroke(spokes[slot], with: .color(ArmsInk.of(slot: slot).opacity(share * quiet)), lineWidth: width)
        }
        let ink = focusAt.map { ArmsInk.of(slot: prepared.ink[$0]) } ?? scene.area.flatMap { prepared.areaSlots[$0] }.map(ArmsInk.of(slot:))
        if let ink {
            let share = scene.focus == nil ? BrainLook.litShare * scene.areaShare : BrainLook.litShare
            context.stroke(lit, with: .color(ink.opacity(share)), lineWidth: BrainLook.litWidth)
        }
    }

    /// Every mark in one core and one halo path to each colour and step of light: memory as dots, the core as four
    /// point stars, the rules as gold discs and the applications as round tiles; then each hub's light and each area's.
    private func marks(_ context: inout GraphicsContext, near: Set<Int>?) {
        let steps = BrainLook.lightSteps
        let buckets = ArmsInk.slots * steps
        var cores = Array(repeating: Path(), count: buckets)
        var wires = Array(repeating: Path(), count: buckets)
        var halos = Array(repeating: Path(), count: buckets)
        var lensed = Array(repeating: Path(), count: steps)
        var lensedWires = Array(repeating: Path(), count: steps)
        var tiles = Path()
        let seconds = scene.still ? 0 : scene.idle
        let overAt = scene.over.flatMap { prepared.index[$0] }
        // A dense brain's halos fade, so a thousand dots read as a cluster rather than one glare.
        let glowShare = BrainLook.glowShare * min(1, (BrainLook.denseFrom / Double(max(prepared.nodes.count, 1))).squareRoot())
        for index in prepared.nodes.indices where !prepared.personSet.contains(index) {
            let light = min(frame.light[index] * kept(index, near: near), 1)
            guard light > 0 else { continue }
            let step = min(Int(light * Double(steps)), steps - 1)
            let bucket = prepared.ink[index] * steps + step
            var radius = frame.radius[index]
            if index == overAt { radius *= 1 + BrainLook.swellGrowth * scene.swell }
            let centre = at(index)
            let pulled = pull(centre)
            radius *= 1 + BrainLook.lensGrowth * pulled
            let lensStep = min(Int(pulled * Double(steps)), steps - 1)
            let disc = CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
            switch prepared.spots[index].layer {
            case .skills:
                cores[bucket].addPath(Self.star(centre, radius))
            case .memory where radius >= BrainLook.wireFrom:
                let spin = (Double(index) * BrainLook.goldenShare).truncatingRemainder(dividingBy: 1)
                Self.wire(&wires[bucket], centre, radius, spin: spin, seconds: seconds)
                if pulled > BrainLook.lensWhite { Self.wire(&lensedWires[lensStep], centre, radius, spin: spin, seconds: seconds) }
            case .memory:
                cores[bucket].addEllipse(in: disc)
                if pulled > BrainLook.lensWhite { lensed[lensStep].addEllipse(in: disc) }
            case .rules:
                tiles.addEllipse(in: disc)
                cores[bucket].addEllipse(in: disc.insetBy(dx: radius * BrainLook.starWaist, dy: radius * BrainLook.starWaist))
            case .applications:
                tiles.addEllipse(in: disc)
                cores[bucket].addEllipse(in: disc)
            }
            let glow = radius * BrainLook.glowScale
            halos[bucket].addEllipse(in: CGRect(x: centre.x - glow, y: centre.y - glow, width: glow * 2, height: glow * 2))
        }
        context.blendMode = .plusLighter
        for slot in 0..<ArmsInk.slots {
            let ink = ArmsInk.of(slot: slot)
            let outlined = slot == ArmsInk.slot(.applications, area: 0) || slot == ArmsInk.slot(.rules, area: 0)
            for step in 0..<steps {
                let bucket = slot * steps + step
                let light = (Double(step) + 1) / Double(steps)
                context.fill(halos[bucket], with: .color(ink.opacity(glowShare * light)))
                // A tile and a disc are outlined in their glow and left dark inside, so a logo or an icon reads on them.
                if outlined {
                    context.stroke(cores[bucket], with: .color(ink.opacity(light)), lineWidth: Memnox.Stroke.hairline * 2)
                } else {
                    context.fill(cores[bucket], with: .color(ink.opacity(light)))
                }
                context.stroke(wires[bucket], with: .color(ink.opacity(light)), lineWidth: BrainLook.wireWidth)
            }
        }
        // What the pointer's lens passes over is lit white over its colour, the more the nearer the pointer.
        for step in 0..<steps {
            let white = Memnox.Console.Brain.ink.opacity(BrainLook.lensShare * (Double(step) + 1) / Double(steps))
            context.fill(lensed[step], with: .color(white))
            context.stroke(lensedWires[step], with: .color(white), lineWidth: BrainLook.wireWidth)
        }
        context.blendMode = .normal
        context.fill(tiles, with: .color(Memnox.Console.Brain.card.opacity(BrainPanel.fill)))
        tileFaces(&context)
        context.blendMode = .plusLighter
        for index in prepared.hubs {
            let centre = at(index)
            let radius = frame.radius[index]
            let share = min(frame.light[index] * kept(index, near: near), 1)
            let halo = radius * BrainLook.haloScale
            let ink = ArmsInk.of(slot: prepared.ink[index])
            context.fill(Path(ellipseIn: CGRect(x: centre.x - halo, y: centre.y - halo, width: halo * 2, height: halo * 2)),
                         with: .radialGradient(Gradient(colors: [ink.opacity(BrainLook.haloShare * share), .clear]),
                                               center: centre, startRadius: 0, endRadius: halo))
            let heart = radius * BrainLook.heartShare
            context.fill(Path(ellipseIn: CGRect(x: centre.x - heart, y: centre.y - heart, width: heart * 2, height: heart * 2)),
                         with: .color(Memnox.Console.Brain.ink.opacity(share)))
        }
        if scene.mode != .timeline {
            for (order, area) in prepared.areas.enumerated() {
                let light = areaLight(order)
                guard light > 0 else { continue }
                let centre = frame.areas[order]
                let radius = BrainLook.areaHub * max(grow, BrainLook.leastDot)
                let ink = ArmsInk.of(slot: prepared.areaSlots[area.group] ?? 0)
                let disc = CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: disc.insetBy(dx: -radius * BrainLook.haloScale, dy: -radius * BrainLook.haloScale)),
                             with: .radialGradient(Gradient(colors: [ink.opacity(BrainLook.haloShare * light), .clear]),
                                                   center: centre, startRadius: 0, endRadius: radius * (1 + BrainLook.haloScale)))
                context.stroke(Path(ellipseIn: disc), with: .color(ink.opacity(light)), lineWidth: BrainLook.ringWidth)
            }
        }
        if let overAt, scene.swell > 0 {
            let centre = at(overAt)
            let halo = frame.radius[overAt] * BrainLook.swellHalo
            let ink = ArmsInk.of(slot: prepared.ink[overAt])
            context.fill(Path(ellipseIn: CGRect(x: centre.x - halo, y: centre.y - halo, width: halo * 2, height: halo * 2)),
                         with: .radialGradient(Gradient(colors: [ink.opacity(BrainLook.haloShare * scene.swell), .clear]),
                                               center: centre, startRadius: 0, endRadius: halo))
        }
        context.blendMode = .normal
    }

    /// Each person as an avatar: a disc in the colour drawn from their name, their initials on it once it is big enough.
    private func avatars(_ context: inout GraphicsContext, near: Set<Int>?) {
        for person in prepared.people {
            let light = min(frame.light[person.index] * kept(person.index, near: near), 1)
            guard light > 0 else { continue }
            let radius = frame.radius[person.index]
            let centre = at(person.index)
            let ink = ArmsInk.avatars[person.colour % ArmsInk.avatars.count]
            let disc = CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: disc), with: .color(ink.opacity(light)))
            context.stroke(Path(ellipseIn: disc), with: .color(Memnox.Console.Brain.ink.opacity(light * BrainLook.outlineShare)),
                           lineWidth: Memnox.Stroke.hairline)
            guard radius >= BrainLook.initialsFrom else { continue }
            let text = context.resolve(Text(person.initials)
                .font(Memnox.Console.sans(radius * BrainLook.initialsShare, .semibold))
                .foregroundColor(Memnox.Console.Brain.ink.opacity(light)))
            context.draw(text, at: centre, anchor: .center)
        }
    }

    /// The icon on each rule's disc and on each server's tile that has no logo of its own.
    private func tileFaces(_ context: inout GraphicsContext) {
        let ruleIcons = prepared.ruleSymbols.count <= BrainLook.mostRuleIcons
        for face in prepared.faces where frame.light[face.index] > 0 {
            if prepared.spots[face.index].layer == .rules, !ruleIcons { continue }
            let side = frame.radius[face.index] * BrainLook.iconShare
            let ink = prepared.spots[face.index].layer == .rules ? ArmsInk.rules : ArmsInk.applications
            let image = context.resolve(Image(systemName: face.symbol))
            var shaded = context
            shaded.opacity = frame.light[face.index]
            shaded.addFilter(.colorMultiply(ink))
            shaded.draw(image, in: CGRect(x: frame.x[face.index] - side / 2, y: frame.y[face.index] - side / 2, width: side, height: side))
        }
    }

    /// Each memory hub's count bubble, off its upper right.
    private func counts(_ context: inout GraphicsContext) {
        for each in prepared.counts where each.count > 0 && frame.light[each.index] > 0 {
            let radius = frame.radius[each.index]
            let centre = CGPoint(x: frame.x[each.index] + radius * BrainLook.bubbleShift, y: frame.y[each.index] - radius * BrainLook.bubbleShift)
            bubble(&context, "\(each.count)", at: centre, size: BrainLook.bubbleSize, height: BrainLook.bubble,
                   fill: ArmsInk.of(slot: prepared.ink[each.index]).opacity(frame.light[each.index]))
        }
    }

    /// Each application's number off its upper left and how long ago it was last used under it, once the tile is big
    /// enough that both read.
    private func badges(_ context: inout GraphicsContext) {
        guard scene.mode != .timeline || scene.camera.k >= MapMetrics.namesFrom else { return }
        for index in prepared.nodes.indices where prepared.numbers[index] != nil && frame.light[index] > 0 {
            let radius = frame.radius[index]
            guard radius >= BrainLook.badgeFrom, let number = prepared.numbers[index] else { continue }
            let light = frame.light[index]
            let corner = CGPoint(x: frame.x[index] - radius * BrainLook.bubbleShift, y: frame.y[index] - radius * BrainLook.bubbleShift)
            bubble(&context, "\(number)", at: corner, size: BrainLook.badgeSize, height: BrainLook.badge,
                   fill: ArmsInk.applications.opacity(light))
            if let age = prepared.ages[index] {
                let foot = CGPoint(x: frame.x[index], y: frame.y[index] + radius + BrainLook.chipGap + BrainLook.badge)
                bubble(&context, age, at: foot, size: BrainLook.badgeSize, height: BrainLook.badge,
                       fill: Memnox.Console.Brain.card.opacity(light), ink: Memnox.Console.Brain.quiet.opacity(light))
            }
        }
    }

    /// A short word on a capsule of its own, for a count, a number or an age.
    private func bubble(_ context: inout GraphicsContext, _ words: String, at centre: CGPoint, size: CGFloat, height: CGFloat,
                        fill: Color, ink: Color = Memnox.Console.Brain.ink) {
        let text = context.resolve(Text(words).font(Memnox.Console.sans(size, .semibold).monospacedDigit()).foregroundColor(ink))
        let measured = text.measure(in: CGSize(width: BrainLook.nameWide, height: BrainLook.nameTall))
        let side = max(height * 2, measured.width + BrainLook.namePadding * 2)
        let shape = CGRect(x: centre.x - side / 2, y: centre.y - height, width: side, height: height * 2)
        context.fill(Capsule().path(in: shape), with: .color(fill))
        context.draw(text, at: centre, anchor: .center)
    }

    /// Each spark running in from the outside along its angle to the core with a fading trail, and each working
    /// conversation's bead on its way in.
    private func sparks(_ context: inout GraphicsContext) {
        var beads: [(angle: Double, along: Double, from: Double, strength: Double)] = []
        for spark in scene.sparks {
            guard let shape = BrainMotion.spark(age: scene.now - spark.started, still: scene.still) else { continue }
            beads.append((spark.angle, shape.along, outside, shape.strength))
        }
        if scene.mode != .timeline {
            for index in prepared.nodes.indices where scene.working.contains(prepared.nodes[index].id) {
                guard let bead = BrainPulses.bead(prepared.nodes[index].id, seconds: scene.now, still: scene.still) else { continue }
                let spot = prepared.spots[index]
                beads.append((spot.angle, 1 - bead.along, spot.share, bead.strength))
            }
        }
        guard !beads.isEmpty, scene.mode != .timeline else { return }
        context.blendMode = .plusLighter
        let radius = BrainLook.sparkRadius * max(grow, BrainLook.leastDot)
        for bead in beads {
            for step in 0...BrainMotion.trailBeads {
                let behind = Double(step) / Double(BrainMotion.trailBeads)
                let along = min(bead.along + behind * BrainMotion.trailShare, 1)
                let centre = onLayers(bead.angle, share: bead.from * along)
                let fade = bead.strength * (1 - behind)
                let size = radius * (1 - behind / 2)
                let glow = size * BrainLook.sparkGlow
                context.fill(Path(ellipseIn: CGRect(x: centre.x - glow, y: centre.y - glow, width: glow * 2, height: glow * 2)),
                             with: .radialGradient(Gradient(colors: [Memnox.Console.warm.opacity(fade), .clear]),
                                                   center: centre, startRadius: 0, endRadius: glow))
                if step == 0 {
                    context.fill(Path(ellipseIn: CGRect(x: centre.x - size, y: centre.y - size, width: size * 2, height: size * 2)),
                                 with: .color(Memnox.Console.Brain.ink.opacity(fade)))
                }
            }
        }
        context.blendMode = .normal
    }

    /// The ring on the picked mark, on the one the arrows walked to, and on every match of the canvas search.
    private func rings(_ context: inout GraphicsContext) {
        for index in scene.matches ?? [] where frame.light[index] > 0 {
            let radius = frame.radius[index] + BrainLook.ringGap
            let centre = at(index)
            context.stroke(Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)),
                           with: .color(ArmsInk.match), lineWidth: BrainLook.ringWidth)
        }
        for id in Set([scene.selected, scene.keyed].compactMap { $0 }) {
            guard let index = prepared.index[id] else { continue }
            let radius = frame.radius[index] + BrainLook.ringGap
            let centre = at(index)
            context.stroke(Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)),
                           with: .color(id == scene.selected ? Memnox.Console.Brain.ink : Memnox.Console.primary), lineWidth: BrainLook.ringWidth)
        }
    }

    /// The leader from the mark under the pointer out to its card, the way an instrument labels a part: a dot on the
    /// mark, a hairline in its colour and a square where it meets the card.
    private func leader(_ context: inout GraphicsContext) {
        guard scene.lens != nil, let over = scene.over, let index = prepared.index[over], frame.light[index] > 0 else { return }
        let mark = at(index)
        let card = BrainTip.origin(x: mark.x, y: mark.y, radius: frame.radius[index], size: scene.size)
        let end = CGPoint(x: card.x < mark.x ? card.x + MapMetrics.tipWidth : card.x, y: card.y + MapMetrics.tipLift)
        let ink = ArmsInk.of(slot: prepared.ink[index]).opacity(BrainLook.leaderShare * scene.swell)
        var line = Path()
        line.move(to: mark)
        line.addLine(to: end)
        context.stroke(line, with: .color(ink), lineWidth: BrainLook.leaderWidth)
        let dot = BrainLook.leaderDot
        context.fill(Path(ellipseIn: CGRect(x: mark.x - dot, y: mark.y - dot, width: dot * 2, height: dot * 2)), with: .color(ink))
        let square = BrainLook.leaderSquare
        context.fill(Path(CGRect(x: end.x - square / 2, y: end.y - square / 2, width: square, height: square)), with: .color(ink))
    }

    /// One part the tour names: where it is on the screen, what it is called, the line under that, and how open it is.
    private struct Tag {
        let at: CGPoint
        let name: String
        let detail: String
        let open: Double
    }

    /// What the stretch the tour is in names: the part it opened, or in the teardown one of each.
    private func tags() -> [Tag] {
        guard let playhead = scene.playhead else { return [] }
        let pose = scene.pose
        let layers = Dictionary(prepared.layerRows.map { ($0.layer, $0.count) }, uniquingKeysWith: { first, _ in first })
        let first = { (layer: BrainLayer) in prepared.spots.indices.first { prepared.spots[$0].layer == layer && frame.light[$0] > 0 } }
        let largest = prepared.areas.indices.sorted { prepared.areas[$0].count > prepared.areas[$1].count }
        let core = Tag(at: onLayers(0, share: 0), name: "CORE", detail: BrainWords.counted(layers[.skills] ?? 0, "FILE", "FILES"), open: pose.core)
        let areaTag = { (order: Int, open: Double) in
            Tag(at: frame.areas[order], name: BrainWords.label(prepared.areas[order].group).uppercased(),
                detail: BrainWords.counted(prepared.areas[order].count, "PIECE", "PIECES"), open: open)
        }
        let rules = first(.rules).map { Tag(at: at($0), name: "RULES", detail: BrainWords.counted(layers[.rules] ?? 0, "RULE", "RULES"), open: pose.rules) }
        let tiles = first(.applications).map {
            Tag(at: at($0), name: "APPLICATIONS", detail: BrainWords.counted(layers[.applications] ?? 0, "TILE", "TILES"), open: pose.applications)
        }
        switch BrainTour.section(at: playhead).part {
        case .assembled: return []
        case .core: return (layers[.skills] ?? 0) > 0 ? [core] : []
        case .areas: return largest.prefix(BrainLook.mostTags).map { areaTag($0, pose.areas) }
        case .rules: return [rules].compactMap { $0 }
        case .applications: return [tiles].compactMap { $0 }
        case .teardown, .reassembly:
            let apart = { (tag: Tag) in Tag(at: tag.at, name: tag.name, detail: "\(tag.detail) · APART", open: pose.apart) }
            return ([core] + largest.prefix(1).map { areaTag($0, pose.areas) } + [rules, tiles].compactMap { $0 })
                .prefix(BrainLook.mostTags).map(apart)
        }
    }

    /// The tour's labels, the way an instrument names a part: a dot on the part, a hairline out away from the middle
    /// of the canvas to a square, and the part's name in spaced capitals with its count under it, fading in as it opens.
    private func tourLabels(_ context: inout GraphicsContext) {
        let size = scene.size
        let middle = CGPoint(x: size.width / 2, y: size.height / 2)
        for tag in tags() where tag.open > 0 {
            let away = CGPoint(x: tag.at.x - middle.x, y: tag.at.y - middle.y)
            let length = max(hypot(away.x, away.y), 1)
            let right = away.x >= 0
            let end = CGPoint(x: min(max(tag.at.x + away.x / length * BrainLook.tagReach, BrainLook.tagEdge), size.width - BrainLook.tagEdge),
                              y: min(max(tag.at.y + away.y / length * BrainLook.tagReach, BrainLook.tagEdge), size.height - BrainLook.tagFoot))
            let ink = Memnox.Console.primary.opacity(BrainLook.leaderShare * tag.open)
            var line = Path()
            line.move(to: tag.at)
            line.addLine(to: end)
            context.stroke(line, with: .color(ink), lineWidth: BrainLook.leaderWidth)
            let dot = BrainLook.leaderDot
            context.fill(Path(ellipseIn: CGRect(x: tag.at.x - dot, y: tag.at.y - dot, width: dot * 2, height: dot * 2)), with: .color(ink))
            let square = BrainLook.leaderSquare
            context.fill(Path(CGRect(x: end.x - square / 2, y: end.y - square / 2, width: square, height: square)), with: .color(ink))
            let name = context.resolve(Text(tag.name).font(Memnox.Console.code(BrainLook.tagName, .semibold)).tracking(BrainLook.tagTracking)
                .foregroundColor(Memnox.Console.Brain.ink.opacity(tag.open)))
            let detail = context.resolve(Text(tag.detail).font(Memnox.Console.code(BrainLook.tagDetail)).tracking(BrainLook.tagTracking)
                .foregroundColor(Memnox.Console.Brain.quiet.opacity(tag.open)))
            let x = right ? end.x + BrainLook.tagGap : end.x - BrainLook.tagGap
            let anchor: UnitPoint = right ? .bottomLeading : .bottomTrailing
            context.draw(name, at: CGPoint(x: x, y: end.y + square), anchor: anchor)
            context.draw(detail, at: CGPoint(x: x, y: end.y + square + BrainLook.tagGap + BrainLook.tagDetail), anchor: anchor)
        }
    }

    /// One name ready to be placed: its text resolved once, where it would go and its box on the screen.
    private struct Name {
        let text: GraphicsContext.ResolvedText
        let origin: CGPoint
        let size: CGSize
        let ink: Color
        let backed: Bool
    }

    /// Every name this frame, placed so none covers another: the layers' and the areas' names and the core's first,
    /// then the hovered and the picked, then the heaviest marks' names wherever they have room.
    private func names(_ context: inout GraphicsContext) {
        var names: [Name] = []
        var always: Set<Int> = []
        func add(_ name: Name, must: Bool) {
            if must { always.insert(names.count) }
            names.append(name)
        }
        if scene.mode == .map {
            for layer in [BrainLayer.skills, .rules, .applications] {
                guard let share = prepared.reaches[layer] else { continue }
                let point = onLayers(-Double.pi / 2, share: share + BrainLook.bandLift)
                add(heading(&context, BrainWords.layerName(layer), at: point, ink: ArmsInk.of(layer)), must: true)
            }
            for (order, area) in prepared.areas.enumerated() where areaLight(order) > 0 {
                let top = CGPoint(x: frame.areas[order].x, y: frame.areas[order].y - area.radius * scene.camera.k)
                let ink = ArmsInk.of(slot: prepared.areaSlots[area.group] ?? 0)
                add(heading(&context, "\(BrainWords.label(area.group).uppercased())  \(area.count)", at: top, ink: ink), must: true)
            }
            if let core = prepared.coreLabel {
                add(name(&context, core, at: onLayers(0, share: 0), anchor: .center, ink: Memnox.Console.Brain.ink), must: true)
            }
        }
        let pinned = [scene.over, scene.selected].compactMap { $0.flatMap { prepared.index[$0] } }
        for index in pinned { add(markName(&context, index), must: true) }
        for index in candidates() where !pinned.contains(index) { add(markName(&context, index), must: false) }
        let boxes = names.enumerated().map { at, name in
            LabelCandidate(id: at, x: name.origin.x, y: name.origin.y, width: name.size.width, height: name.size.height,
                           weight: Double(names.count - at))
        }
        for at in BrainLabels.place(boxes, always: always) {
            let name = names[at]
            if name.backed {
                let backing = CGRect(x: name.origin.x - BrainLook.namePadding, y: name.origin.y - BrainLook.namePadding / 2,
                                     width: name.size.width + BrainLook.namePadding * 2, height: name.size.height + BrainLook.namePadding)
                context.fill(RoundedRectangle(cornerRadius: BrainLook.nameRadius, style: .continuous).path(in: backing),
                             with: .color(Memnox.Console.Brain.labelBacking.opacity(BrainLook.backingShare)))
            }
            context.draw(name.text, in: CGRect(origin: name.origin, size: name.size))
        }
    }

    /// The marks whose names are asked for, heaviest first: every lit one with every name on, the heavy ones once
    /// zoomed in, every one on the screen once zoomed in close, and every match of the search.
    private func candidates() -> [Int] {
        let k = scene.camera.k
        let bounds = CGRect(origin: .zero, size: scene.size)
        let onScreen = { (index: Int) in frame.light[index] > BrainLook.unlit && bounds.contains(at(index)) }
        var wanted: [Int]
        if scene.allLabels || k >= BrainLook.namesAllFrom {
            wanted = prepared.nodes.indices.filter(onScreen)
        } else {
            let zoomedIn = k >= MapMetrics.namesFrom
            wanted = prepared.nodes.indices.filter { zoomedIn && prepared.named.contains(prepared.nodes[$0].id) && onScreen($0) }
        }
        if let matches = scene.matches { wanted = Array(Set(wanted).intersection(matches).union(matches.filter(onScreen))) }
        wanted.sort { prepared.weights[$0] == prepared.weights[$1] ? $0 < $1 : prepared.weights[$0] > prepared.weights[$1] }
        return Array(wanted.prefix(BrainLook.mostNames))
    }

    /// A mark's short name, above it.
    private func markName(_ context: inout GraphicsContext, _ index: Int) -> Name {
        let point = CGPoint(x: frame.x[index], y: frame.y[index] - frame.radius[index] - BrainLook.nameGap)
        return name(&context, MapNames.short(prepared.nodes[index].label), at: point, anchor: .bottom, ink: Memnox.Console.Brain.ink)
    }

    /// A layer's or an area's name in spaced capitals, standing on its point.
    private func heading(_ context: inout GraphicsContext, _ words: String, at point: CGPoint, ink: Color) -> Name {
        let text = context.resolve(Text(words)
            .font(Memnox.Console.code(BrainLook.bandName, .medium))
            .tracking(BrainLook.bandTracking)
            .foregroundColor(ink.opacity(BrainLook.outlineShare + BrainLook.unlit * 2)))
        let size = text.measure(in: CGSize(width: BrainLook.nameWide * 2, height: BrainLook.nameTall))
        return Name(text: text, origin: CGPoint(x: point.x - size.width / 2, y: point.y - size.height), size: size, ink: ink, backed: false)
    }

    /// One short name on its dark backing, anchored where it is put.
    private func name(_ context: inout GraphicsContext, _ words: String, at point: CGPoint, anchor: UnitPoint, ink: Color) -> Name {
        let text = context.resolve(Text(words).font(Memnox.Console.sans(BrainLook.nameSize, .medium)).foregroundColor(ink))
        let size = text.measure(in: CGSize(width: BrainLook.nameWide, height: BrainLook.nameTall))
        return Name(text: text, origin: CGPoint(x: point.x - size.width * anchor.x, y: point.y - size.height * anchor.y), size: size,
                    ink: ink, backed: true)
    }

    /// One short name drawn at once, for the Timeline's axis, which nothing else is placed against.
    private func draw(_ context: inout GraphicsContext, _ words: String, at point: CGPoint, anchor: UnitPoint, ink: Color) {
        let each = name(&context, words, at: point, anchor: anchor, ink: ink)
        let backing = CGRect(x: each.origin.x - BrainLook.namePadding, y: each.origin.y - BrainLook.namePadding / 2,
                             width: each.size.width + BrainLook.namePadding * 2, height: each.size.height + BrainLook.namePadding)
        context.fill(RoundedRectangle(cornerRadius: BrainLook.nameRadius, style: .continuous).path(in: backing),
                     with: .color(Memnox.Console.Brain.labelBacking.opacity(BrainLook.backingShare)))
        context.draw(each.text, in: CGRect(origin: each.origin, size: each.size))
    }

    /// A four point star, its waist drawn in so it reads as a glint.
    static func star(_ centre: CGPoint, _ radius: Double) -> Path {
        var path = Path()
        let waist = radius * BrainLook.starWaist
        let corners = BrainLook.starCorners
        let points = (0..<corners).map { step -> CGPoint in
            let angle = Double(step) * 2 * Double.pi / Double(corners) - Double.pi / 2
            let reach = step % 2 == 0 ? radius : waist
            return CGPoint(x: centre.x + cos(angle) * reach, y: centre.y + sin(angle) * reach)
        }
        path.addLines(points)
        path.closeSubpath()
        return path
    }
}
