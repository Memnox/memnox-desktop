import AppKit
import MemnoxVoiceCore
import SwiftUI

/// How the layered brain is drawn: flat from the side, as nested shells to orbit, or laid along time.
enum BrainMode: String, CaseIterable {
    case map
    case orbs
    case timeline

    var title: String {
        switch self {
        case .map: "Brain map"
        case .orbs: "3D orbs"
        case .timeline: "Timeline"
        }
    }

    var symbol: String {
        switch self {
        case .map: "brain"
        case .orbs: "circle.hexagongrid"
        case .timeline: "calendar.day.timeline.left"
        }
    }
}

/// What the brain remembers between visits: the view, whether it moves and how fast.
private enum BrainStore {
    static let modeKey = "memnox.memory.brainMode"
    static let motionKey = "memnox.memory.motion"
    static let speedKey = "memnox.memory.speed"
}

/// Memory on this Mac drawn as a brain built from its own nodes: the instruction files and the skills packed at the
/// core, each memory area its own coloured cluster about a labelled hub with a spoke back to the core, the rules that
/// run without the person in a gold ring, and the applications in numbered round tiles around the outside. Agents are never drawn; who used a piece is said in its details. A drag pans the map
/// and the Timeline and orbits the 3D view, the scroll wheel and a pinch zoom about the pointer, and a double click fits.
struct MemoryMapView<Bar: View, Foot: View, Card: View>: View {
    let graph: LocalGraphInputs
    /// Whose memory is drawn: everything, this Mac's alone, or the workspace's alone.
    var shown = MemoryHomeFilter.everything
    /// The conversations working right now, by node id, each sending a bead into the core.
    let working: Set<String>
    /// The node whose details are open: a fact's id, or another node's id.
    let selected: String?
    /// Said on the canvas once the list has come back with nothing, nil while it is still being read.
    let empty: String?
    /// A node picked, or nil for the ground, with the map it was picked on so its details can list what it is linked to.
    let select: (MemoryMapNode?, MemoryMap) -> Void
    /// The page's own controls, the search, the switch and the filters, along the top of the canvas.
    @ViewBuilder let bar: Bar
    /// What the heading says under its counts: a cut list's line, the workspace's state and the way to the sources.
    @ViewBuilder let foot: Foot
    /// The picked node's details, drawn in a card beside it that follows it across the map.
    @ViewBuilder let card: Card

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(BrainStore.modeKey) private var mode = BrainMode.map
    @AppStorage(BrainStore.motionKey) private var motionOn = true
    @AppStorage(BrainStore.speedKey) private var speed = BrainMotion.normalSpeed
    @State private var memo = BrainMemo()
    @State private var pulse = BrainPulse()
    /// What the runtime said last, so only a real change to the record sends a spark.
    @State private var witness = BrainWitness()
    /// Where the camera is going; a glide springs it there from where it was.
    @State private var camera = SurfaceCamera.atRest
    @State private var glide: BrainGlide?
    @State private var nodeSize = 1.0
    @State private var over: String?
    @State private var overAt = Date.distantPast
    /// Somebody has taken the camera, so it stops following the fit.
    @State private var own = false
    @State private var hand: Hand?
    @State private var pinch: SurfaceCamera?
    @State private var stage = CGSize.zero
    /// Where the pointer is over the canvas, nil once it leaves, which the scroll wheel zooms about.
    @State private var pointer: CGPoint?
    /// The scroll wheel and the right button, which SwiftUI does not hand a view, watched while the canvas is up.
    @State private var monitor: EventMonitor?
    @State private var panning: Hand?
    /// Kinds of node and of line taken off under Display, areas and layers taken off in the legend.
    @State private var hiddenKinds: Set<MemoryMapNodeKind> = []
    @State private var hiddenLinks: Set<MemoryLinkKind> = []
    @State private var hiddenGroups: Set<SourceGroup> = []
    @State private var hiddenLayers: Set<BrainLayer> = []
    /// The area lit in the legend or by its hub, and when it was, so its sector blooms in.
    @State private var area: SourceGroup?
    @State private var areaAt = Date.distantPast
    /// The area last put out, which fades back while the rest of the brain lights up again.
    @State private var fading: SourceGroup?
    @State private var attentionOnly = false
    @State private var allLabels = false
    /// Every overlay away and the brain moving on its own until Escape.
    @State private var cinema = false
    /// When the opening began, which a replay starts again.
    @State private var openedAt = Date()
    /// The idle life's clock, at the slider's speed, and the 3D view's own turn, which holds while a hand is on it.
    @State private var idle = BrainClock()
    @State private var orbit = BrainClock()
    @State private var yaw = 0.0
    @State private var pitch = SurfaceOrbit.restingPitch
    /// A 3D brain let go mid turn, coasting on.
    @State private var fling: BrainFling?
    /// The turn the 3D brain is springing from toward `yaw` while it flies a node round to the front.
    @State private var turnFrom: BrainTurnGlide?
    /// The view the dots are morphing from, and when the morph began.
    @State private var morphFrom: BrainMode?
    @State private var morphAt = Date.distantPast
    @State private var holding = false
    @State private var resume: Task<Void, Never>?
    @State private var settle: Task<Void, Never>?
    /// Bumped when something timed ends, so whether the frame clock runs is asked again.
    @State private var beat = 0
    /// When the latest timed change ends, which the one waiting rest is set for.
    @State private var restUntil = Date.distantPast
    /// Until when an eased change still needs frames with the idle life held.
    @State private var easing = Date.distantPast
    @FocusState private var focused: Bool
    /// The canvas search: whether its capsule is open, what it holds, and whether its field has the cursor.
    @State private var seeking = false
    @State private var seek = ""
    /// The picked node's card as last measured, which places it, and whether the pointer is over it, which holds the
    /// map's hover off what lies under the card.
    @State private var cardHeight = MapMetrics.detailLeast
    @State private var overCard = false
    @FocusState private var seekFocused: Bool

    /// The ground held by a drag: it pans, or turns the 3D brain, or pans with Option held or the right button.
    private struct Hand {
        let camera: SurfaceCamera
        let yaw: Double
        let pitch: Double
        let pans: Bool
        var moved: Bool
        var start = CGPoint.zero
    }

    var body: some View {
        let prepared = prepared()
        let _ = beat
        let found = matches(prepared)
        let matched = found.map(Set.init)
        let live = moving(prepared)
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ground(geometry.size, prepared)
                // A paused clock keeps the date it stopped on, so while nothing moves on its own a redraw for a
                // hover, a glide or a pick reads the wall clock instead and never draws a stale moment.
                TimelineView(.animation(minimumInterval: MapMotion.frame, paused: !live)) { timeline in
                    let scene = scene(prepared, at: live ? timeline.date : Date(), size: geometry.size, matches: matched)
                    let frame = frame(prepared, scene: scene)
                    ZStack(alignment: .topLeading) {
                        Canvas { context, _ in
                            BrainPainter(prepared: prepared, frame: frame, scene: scene).paint(&context)
                        }
                        logos(prepared, frame)
                        if hand == nil, let over, let index = prepared.index[over], frame.light[index] > 0 {
                            tip(prepared, frame, index: index, size: geometry.size)
                        }
                    }
                    .allowsHitTesting(false)
                }
                .accessibilityHidden(true)
                if !cinema { overlays(prepared, size: geometry.size) }
                if !cinema, let selected, let index = prepared.index[selected] {
                    TimelineView(.animation(minimumInterval: MapMotion.frame, paused: !live)) { timeline in
                        detail(prepared, index: index, at: live ? timeline.date : Date(), size: geometry.size)
                    }
                }
                if seeking && !cinema {
                    BrainSeek(text: $seek, focused: $seekFocused, found: found?.count, open: { openMatch(found, prepared) }, close: closeSeek)
                        .padding(.top, MapMetrics.seekTop)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
                if cinema {
                    Text("Press Escape to leave Cinema")
                        .font(Memnox.Console.code(Memnox.Console.Brain.caption))
                        .foregroundStyle(Memnox.Console.Brain.faint)
                        .padding(MapMetrics.inset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(.named(MapMetrics.space))
            .onContinuousHover(coordinateSpace: .named(MapMetrics.space)) { phase in
                switch phase {
                case .active(let at):
                    pointer = at
                    if overCard {
                        hover(nil)
                    } else if hand == nil {
                        hover(hit(at, prepared).map { prepared.nodes[$0].id })
                    }
                case .ended:
                    pointer = nil
                    hover(nil)
                }
            }
            .onAppear {
                stage = geometry.size
                if !own { camera = fitted(geometry.size, mode, prepared) }
            }
            .onChange(of: geometry.size) { _, now in
                stage = now
                if !own { camera = fitted(now, mode, prepared) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Memnox.Console.Brain.ground)
        .environment(\.colorScheme, .dark)
        .clipped()
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress { press in keys(press, prepared) }
        .simultaneousGesture(MagnifyGesture()
            .onChanged { value in
                let base = pinch ?? shownCamera(at: Date())
                pinch = base
                own = true
                glide = nil
                hold()
                // About where the fingers came down, so what was under them stays under them.
                camera = base.zoomed(by: value.magnification, at: (value.startLocation.x, value.startLocation.y),
                                     size: (stage.width, stage.height))
            }
            .onEnded { _ in
                pinch = nil
                letGo()
            })
        .onAppear {
            openedAt = Date()
            idle.set(speed: speed, at: Date())
            orbit.set(speed: speed, at: Date())
            motion()
            watch()
            rest(after: BrainMotion.openingLength)
        }
        .onChange(of: graph, initial: true) { _, now in stir(now, prepared) }
        .onChange(of: reduceMotion) { _, _ in motion() }
        // The 3D brain holds still on a picked node and turns on its own again once the details are put away.
        .onChange(of: selected) { _, now in
            motion()
            if now == nil, holding, hand == nil { letGo() }
        }
        .onChange(of: motionOn) { _, _ in motion() }
        .onChange(of: speed) { _, now in
            idle.set(speed: now, at: Date())
            orbit.set(speed: now, at: Date())
        }
        .onDisappear {
            idle.stop(at: Date())
            orbit.stop(at: Date())
            resume?.cancel()
            settle?.cancel()
            monitor?.stop()
            monitor = nil
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Memory graph")
    }

    private var focus: String? { selected ?? over }

    /// The map as drawn, built again only when the record or a filter changes, never for a hover or a frame.
    private func prepared() -> BrainPrepared {
        let key = BrainKey(graph: graph, shown: shown, hiddenGroups: hiddenGroups, hiddenLayers: hiddenLayers,
                           attentionOnly: attentionOnly, hiddenKinds: hiddenKinds, hiddenLinks: hiddenLinks)
        return memo.prepared(key) {
            BrainPrepared(key, map: MemoryMaps.held(LocalGraphs.map(graph, kindLabel: MemoryLines.sourceKindLabel), shown))
        }
    }

    /// Whether the frame clock has anything to draw: the idle life, the opening, an eased change, a spark or a
    /// conversation at work.
    private func moving(_ prepared: BrainPrepared) -> Bool {
        let now = Date()
        let opening = now.timeIntervalSince(openedAt) < openingLength
        return idle.running || orbit.running || opening || now < easing || pulse.sparks.busy
            || prepared.nodes.contains { working.contains($0.id) }
    }

    private var openingLength: TimeInterval { reduceMotion ? BrainMotion.stillFade : BrainMotion.openingLength }

    /// The overlays: the bar and the view's controls along the top, the heading and its stats, then the legend,
    /// Replay and Cinema, how full the brain is and the zoom along the foot, with the hints between.
    @ViewBuilder private func overlays(_ prepared: BrainPrepared, size: CGSize) -> some View {
        if let quiet = quietLine(prepared) {
            MapQuietCard(line: quiet)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        }
        VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
            HStack(alignment: .top, spacing: Memnox.Spacing.medium) {
                bar
                Spacer(minLength: Memnox.Spacing.medium)
                VStack(alignment: .trailing, spacing: Memnox.Spacing.small) {
                    Text(BrainWords.inView(prepared.nodes.count))
                        .font(Memnox.Console.code(Memnox.Console.Brain.overline))
                        .foregroundStyle(Memnox.Console.Brain.quiet)
                    BrainViewControls(mode: mode, choose: choose, motionOn: $motionOn, speed: $speed, still: reduceMotion,
                                      nodeSize: $nodeSize, map: prepared.base, hiddenKinds: $hiddenKinds, hiddenLinks: $hiddenLinks)
                }
            }
            BrainHeading(stats: MemoryGroups.stats(prepared.drawn)) { foot }
        }
        .padding(MapMetrics.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        VStack(spacing: Memnox.Spacing.medium) {
            HStack(alignment: .bottom, spacing: Memnox.Spacing.large) {
                BrainLegend(areas: prepared.areaRows, layers: prepared.layerRows, slots: prepared.areaSlots, hidden: $hiddenGroups,
                            hiddenLayers: $hiddenLayers, area: area, pick: pickArea, attentionOnly: $attentionOnly, allLabels: $allLabels)
                Spacer(minLength: Memnox.Spacing.medium)
                HStack(spacing: Memnox.Spacing.small) {
                    BrainPill(symbol: "magnifyingglass", title: "Search",
                              help: "Search the brain, or press \(BrainWords.searchKey)", enabled: true, action: openSeek)
                    BrainPill(symbol: "play.circle", title: "Replay",
                              help: "Fly the layers in again from the core outward, or press \(BrainWords.replayKey)", enabled: true, action: replay)
                    BrainPill(symbol: "film", title: "Cinema", help: "Hide everything but the brain; Escape brings it back",
                              enabled: true, action: enterCinema)
                }
                Spacer(minLength: Memnox.Spacing.medium)
                VStack(alignment: .trailing, spacing: Memnox.Spacing.medium) {
                    let growth = MemoryGroups.growth(prepared.base, sources: graph.sources)
                    if growth.total > 0 { BrainGrowth(verified: growth.verified, total: growth.total) }
                    MapZoom(camera: camera, fit: { fit(size) }, zoom: { zoom(by: $0, size: size) })
                }
            }
            HStack {
                Text(mode == .orbs ? BrainWords.orbsHint : BrainWords.leftHint)
                Spacer(minLength: Memnox.Spacing.medium)
                Text(BrainWords.rightHint)
            }
            .font(Memnox.Console.code(Memnox.Console.Brain.caption))
            .foregroundStyle(Memnox.Console.Brain.faint)
            .allowsHitTesting(false)
        }
        .padding(MapMetrics.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    /// The caller's line while nothing was learned, and a hint once the filters have taken everything off.
    private func quietLine(_ prepared: BrainPrepared) -> String? {
        if prepared.nodes.isEmpty, !prepared.base.nodes.isEmpty {
            return attentionOnly ? "Nothing here needs your attention." : "Everything is hidden. Turn an area back on in the legend."
        }
        return prepared.base.nodes.contains { $0.kind == .memory || $0.kind == .decision } ? nil : empty
    }

    /// Everything a frame needs to know about this moment beyond the marks themselves.
    private func scene(_ prepared: BrainPrepared, at date: Date, size: CGSize, matches: Set<Int>? = nil) -> BrainScene {
        let opening = date.timeIntervalSince(openedAt)
        let seconds = date.timeIntervalSinceReferenceDate
        pulse.sparks.advance(at: seconds)
        return BrainScene(mode: mode, camera: shownCamera(at: date), size: size, turn: orbTurn(at: date),
                          opening: opening < openingLength ? opening : nil, still: reduceMotion, idle: idle.seconds(at: date),
                          focus: focus, selected: selected, keyed: focused ? over : nil, over: over,
                          swell: reduceMotion ? 1 : BrainMotion.swell(date.timeIntervalSince(overAt)), area: area ?? fading,
                          areaShare: areaShare(at: date), allLabels: allLabels,
                          working: working, sparks: pulse.sparks.sparks, now: seconds, matches: matches)
    }

    /// How far the lit area has bloomed in, or the one put out has faded back.
    private func areaShare(at date: Date) -> Double {
        let bloom = reduceMotion ? 1 : BrainMotion.bloom(date.timeIntervalSince(areaAt))
        return area == nil ? 1 - bloom : bloom
    }

    /// Every mark as it is seen at this moment: flown in, turned or laid along time, and on the screen. One pass over
    /// the nodes into flat arrays, so a frame costs what the drawing holds and no more.
    private func frame(_ prepared: BrainPrepared, scene: BrainScene) -> BrainFrame {
        let count = prepared.nodes.count
        var frame = BrainFrame(x: [], y: [], radius: [], light: [], depth: [], areas: [])
        frame.x.reserveCapacity(count)
        frame.y.reserveCapacity(count)
        frame.radius.reserveCapacity(count)
        frame.light.reserveCapacity(count)
        frame.depth.reserveCapacity(count)
        let morph = reduceMotion ? nil : morphFrom.flatMap { from in
            BrainMotion.morph(Date(timeIntervalSinceReferenceDate: scene.now).timeIntervalSince(morphAt)).map { (from, $0) }
        }
        let alive = !reduceMotion
        for index in 0..<count {
            let spot = prepared.spots[index]
            let reveal = scene.opening.map {
                BrainMotion.opening(spot.layer, ring: spot.ring, around: prepared.around[index], seconds: $0, still: scene.still)
            } ?? .settled
            var seen = place(index, prepared, mode: scene.mode, reveal: reveal, scene: scene)
            if let morph {
                let before = place(index, prepared, mode: morph.0, reveal: reveal, scene: scene)
                let share = morph.1
                seen = (before.x + (seen.x - before.x) * share, before.y + (seen.y - before.y) * share,
                        before.scale + (seen.scale - before.scale) * share, before.depth + (seen.depth - before.depth) * share)
            }
            let id = prepared.nodes[index].id
            var light = reveal.light
            if alive { light *= spot.layer == .skills ? BrainMotion.shimmer(id, seconds: scene.idle) : BrainMotion.twinkle(id, seconds: scene.idle) }
            if scene.mode == .orbs || morph?.0 == .orbs { light *= MapMotion.dimBack + (1 - MapMotion.dimBack) * seen.depth }
            let world = (prepared.personSet.contains(index) ? BrainLook.avatar : Self.size(spot)) * (1 + reveal.bloom * BrainLook.bloomGrowth)
            frame.x.append(seen.x)
            frame.y.append(seen.y)
            // By the square root of the zoom, so zooming in opens room between marks rather than only growing them.
            frame.radius.append(max(BrainLook.leastDot, world * seen.scale * scene.camera.k.squareRoot() * nodeSize))
            frame.light.append(light)
            frame.depth.append(seen.depth)
        }
        frame.areas = prepared.areas.map { area in
            let at = onScreen((area.x, area.y), latitude: 0, mode: scene.mode, scene: scene)
            return CGPoint(x: at.x, y: at.y)
        }
        return frame
    }

    /// How large a mark is drawn in world points, by its layer and, in memory, its weight.
    private static func size(_ spot: BrainArmSpot) -> Double {
        switch spot.layer {
        case .skills: BrainLook.star * (spot.size >= 1 ? BrainLook.heartStar : 1)
        case .memory: BrainLook.dot + BrainLook.dotGrowth * spot.size
        case .rules: BrainLook.rule
        case .applications: BrainLook.tile
        }
    }

    /// One mark's spot on the screen in a view, its perspective scale and how near it is.
    private func place(_ index: Int, _ prepared: BrainPrepared, mode: BrainMode, reveal: BrainReveal,
                       scene: BrainScene) -> (x: Double, y: Double, scale: Double, depth: Double) {
        let spot = prepared.spots[index]
        let size = (width: Double(scene.size.width), height: Double(scene.size.height))
        switch mode {
        case .map, .orbs:
            return onScreen(Self.grown(index, prepared, reach: reveal.reach), latitude: spot.latitude, mode: mode, scene: scene)
        case .timeline:
            let at = scene.camera.onScreen(prepared.timeline[index], size: size)
            return (at.x, at.y, 1, 1)
        }
    }

    /// Where a mark stands in the world on the flat view as it grows in: a memory piece out of its area's hub, so each
    /// cluster blooms from its own middle, and every other layer out from the core.
    private static func grown(_ index: Int, _ prepared: BrainPrepared, reach: Double) -> (x: Double, y: Double) {
        let spot = prepared.spots[index]
        guard let anchor = prepared.anchors[index] else { return BrainArms.flat(spot, reach: reach) }
        let full = BrainArms.flat(spot)
        return (anchor.x + (full.x - anchor.x) * reach, anchor.y + (full.y - anchor.y) * reach)
    }

    /// A flat world spot on the screen in the map or the 3D view, with its perspective scale and nearness.
    private func onScreen(_ flat: (x: Double, y: Double), latitude: Double, mode: BrainMode,
                          scene: BrainScene) -> (x: Double, y: Double, scale: Double, depth: Double) {
        let size = (width: Double(scene.size.width), height: Double(scene.size.height))
        guard mode == .orbs else {
            let at = scene.camera.onScreen(flat, size: size)
            return (at.x, at.y, 1, 1)
        }
        let seen = SurfaceOrbit.seen(BrainArms.orb(at: flat, latitude: latitude), turn: scene.turn)
        let middle = BrainOutline.middle
        let at = scene.camera.onScreen((seen.x + middle.x, seen.y + middle.y), size: size)
        return (at.x, at.y, seen.scale, seen.depth)
    }

    /// The camera as seen at a moment: springing toward where it is going, or there.
    private func shownCamera(at date: Date) -> SurfaceCamera {
        guard let glide, !reduceMotion else { return camera }
        let share = BrainMotion.spring(date.timeIntervalSince(glide.at))
        let from = glide.from
        return SurfaceCamera(x: from.x + (camera.x - from.x) * share, y: from.y + (camera.y - from.y) * share,
                             k: from.k + (camera.k - from.k) * share)
    }

    /// The 3D view's turn at a moment: the hand's, the coast of a fling, and its own slow turn.
    private func orbTurn(at date: Date) -> SurfaceTurn {
        let coasted = fling.map { BrainMotion.coast($0.speed, seconds: date.timeIntervalSince($0.at)) } ?? 0
        var turned = yaw
        if let turnFrom, !reduceMotion {
            turned = turnFrom.yaw + (yaw - turnFrom.yaw) * BrainMotion.spring(date.timeIntervalSince(turnFrom.at))
        }
        return SurfaceTurn(yaw: turned + coasted + orbit.seconds(at: date) * BrainMotion.orbSpin, pitch: pitch)
    }

    /// Flies to a node so it is easy to reach in any view: in 3D the brain turns the shortest way until the node faces
    /// the eye and holds still there; in every view the camera springs to centre it, close enough to read its name.
    private func fly(to index: Int, _ prepared: BrainPrepared) {
        guard stage.width > 0 else { return }
        let flat = Self.grown(index, prepared, reach: 1)
        let k = max(camera.k, MapMetrics.flyZoom)
        let spot: (x: Double, y: Double)
        switch mode {
        case .orbs:
            let now = Date()
            let shown = orbTurn(at: now)
            fling = nil
            orbit = BrainClock()
            orbit.set(speed: speed, at: now)
            hold()
            let target = SurfaceOrbit.facing(BrainArms.orb(at: flat, latitude: prepared.spots[index].latitude), from: shown)
            turnFrom = BrainTurnGlide(yaw: shown.yaw, at: now)
            yaw = target.yaw
            let seen = SurfaceOrbit.seen(BrainArms.orb(at: flat, latitude: prepared.spots[index].latitude), turn: target)
            spot = (seen.x + BrainOutline.middle.x, seen.y + BrainOutline.middle.y)
        case .map:
            spot = flat
        case .timeline:
            spot = prepared.timeline[index]
        }
        own = true
        glideTo(SurfaceCamera(x: spot.x, y: spot.y, k: min(k, SurfaceGeometry.zoomMax)))
    }

    /// The mark under a point, the nearest within its own size or a fingertip of it, the nearer the eye on a tie.
    private func hit(_ at: CGPoint, _ prepared: BrainPrepared) -> Int? {
        guard stage.width > 0 else { return nil }
        let frame = frame(prepared, scene: scene(prepared, at: Date(), size: stage))
        var best: (index: Int, distance: Double, depth: Double)?
        for index in frame.x.indices where frame.light[index] > 0 {
            let distance = hypot(frame.x[index] - at.x, frame.y[index] - at.y)
            guard distance <= max(frame.radius[index], BrainLook.fingertip) else { continue }
            if let best, best.distance < distance || (best.distance == distance && best.depth >= frame.depth[index]) { continue }
            best = (index, distance, frame.depth[index])
        }
        return best?.index
    }

    /// Each app wears its own logo inside its tile, so the person's tools read at a glance.
    private func logos(_ prepared: BrainPrepared, _ frame: BrainFrame) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(prepared.logos, id: \.index) { logo in
                let side = max(BrainLook.leastLogo, frame.radius[logo.index] * BrainLook.logoShare)
                ToolMark(toolkit: logo.slug, side: side)
                    .clipShape(Circle())
                    .opacity(min(frame.light[logo.index], 1))
                    .position(x: frame.x[logo.index], y: frame.y[logo.index])
            }
            // A source wears its maker's logo inside its hub once the hub is big enough for it to read.
            ForEach(prepared.brands.filter { frame.radius[$0.index] * BrainLook.logoShare >= BrainLook.leastLogo }, id: \.index) { each in
                BrainBrandMark(brand: each.brand, side: frame.radius[each.index] * BrainLook.logoShare)
                    .opacity(min(frame.light[each.index], 1))
                    .position(x: frame.x[each.index], y: frame.y[each.index])
            }
        }
    }

    /// The hover card beside the mark under the pointer: what it is, its area and how many lines touch it, on the
    /// side of the mark with room for it.
    private func tip(_ prepared: BrainPrepared, _ frame: BrainFrame, index: Int, size: CGSize) -> some View {
        let node = prepared.nodes[index]
        let layer = prepared.spots[index].layer
        let place = prepared.areaOf[index].map(BrainWords.label) ?? BrainWords.layerWord(layer)
        let reach = frame.radius[index] + BrainLook.nameGap
        let right = frame.x[index] + reach + MapMetrics.tipWidth < size.width
        let x = right ? frame.x[index] + reach : frame.x[index] - reach - MapMetrics.tipWidth
        let y = min(max(frame.y[index] - MapMetrics.tipLift, 0), max(size.height - MapMetrics.tipTall, 0))
        let brand = prepared.brands.first { $0.index == index }?.brand ?? node.mark.map(BrainBrand.toolkit)
        let person = prepared.people.first { $0.index == index }
        return BrainTipCard(name: node.label, kind: MapWords.kindWord(node.kind), place: place, links: prepared.degree[index],
                            brand: brand, person: person.map { ($0.initials, ArmsInk.avatars[$0.colour % ArmsInk.avatars.count]) })
            .frame(width: MapMetrics.tipWidth, alignment: .leading)
            .offset(x: x, y: y)
    }

    /// The picked node's card beside it at this moment, on the side with room, its pointer at the node.
    private func detail(_ prepared: BrainPrepared, index: Int, at date: Date, size: CGSize) -> some View {
        let frame = frame(prepared, scene: scene(prepared, at: date, size: size))
        let tallest = min(MapMetrics.detailMost, max(size.height - 2 * BrainCard.margin, MapMetrics.detailLeast))
        let spot = BrainCard.place((frame.x[index], frame.y[index]), radius: frame.radius[index],
                                   card: (Double(MapMetrics.detailWidth), Double(min(cardHeight, tallest))),
                                   canvas: (Double(size.width), Double(size.height)))
        return BrainDetailCard(spot: spot, tallest: tallest, measured: { cardHeight = $0 }, hovering: { inside in
            overCard = inside
            if inside { hover(nil) }
        }) { card }
    }

    /// What the canvas search matched, best first, nil while it holds no word.
    private func matches(_ prepared: BrainPrepared) -> [Int]? {
        guard seeking, BrainSearch.words(seek) != nil else { return nil }
        return BrainSearch.matches(seek, haystacks: prepared.haystacks, labels: prepared.nodes.map(\.label), weights: prepared.weights)
    }

    /// The canvas search opens over the brain with the cursor in it.
    private func openSeek() {
        seeking = true
        seekFocused = true
    }

    /// The canvas search put away, its words cleared and the canvas lit again.
    private func closeSeek() {
        seeking = false
        seek = ""
        seekFocused = false
        focused = true
    }

    /// Enter opens the best match that is a piece rather than a hub, as the console does, since a hub is mostly its
    /// area's name; a hub only where nothing else matched.
    private func openMatch(_ found: [Int]?, _ prepared: BrainPrepared) {
        let hubs = Set(prepared.hubs)
        guard let first = found?.first(where: { !hubs.contains($0) }) ?? found?.first else { return }
        if mode != .orbs { fly(to: first, prepared) }
        pick(first, prepared)
    }

    /// The pointer came onto a mark or left it, so it swells in from now.
    private func hover(_ id: String?) {
        guard id != over else { return }
        over = id
        overAt = Date()
        ease(for: BrainMotion.swellLength)
    }

    /// An area lit from the legend or put out again, its sector blooming in.
    private func pickArea(_ group: SourceGroup?) {
        let next = area == group ? nil : group
        fading = next == nil ? area : nil
        area = next
        areaAt = Date()
        ease(for: BrainMotion.bloomLength)
    }

    /// Keeps the frame clock going for an eased change, then lets it rest.
    private func ease(for seconds: TimeInterval) {
        easing = max(easing, Date().addingTimeInterval(seconds))
        rest(after: seconds)
    }

    /// Sends a spark in from wherever the record changed: along the angle of the node standing for it when it is
    /// drawn, or along one drawn from its id.
    private func stir(_ inputs: LocalGraphInputs, _ prepared: BrainPrepared) {
        let now = Date()
        for stir in witness.observe(items: inputs.items, sources: inputs.sources, at: now) {
            let index = stir.nodes.lazy.compactMap { prepared.index[$0] }.first
            let angle = index.map { prepared.spots[$0].angle }
                ?? SurfaceOrbit.unit(stir.nodes.first ?? "", salt: BrainLook.sparkSalt) * 2 * Double.pi
            pulse.sparks.offer(angle: angle, at: now.timeIntervalSinceReferenceDate)
            rest(after: BrainMotion.sparkLife)
        }
    }

    /// Asks again, once this long has passed, whether the frame clock still has anything to draw.
    private func rest(after seconds: TimeInterval) {
        let until = Date().addingTimeInterval(seconds)
        guard until > restUntil || settle == nil else { return }
        restUntil = until
        settle?.cancel()
        settle = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            beat += 1
        }
    }

    /// The idle life runs while Motion is on and Reduce Motion is off, and in Cinema; it holds still while a node is
    /// open, so the picked node and its card stay put, and the 3D turn also waits for a hand.
    private func motion() {
        let now = Date()
        let alive = !reduceMotion && (motionOn || cinema) && selected == nil
        if alive { idle.start(at: now) } else { idle.stop(at: now) }
        if alive && !holding && mode == .orbs { orbit.start(at: now) } else { orbit.stop(at: now) }
    }

    /// A hand on the brain: the 3D turn holds still, and waits for the hand to leave.
    private func hold() {
        guard !holding else { return }
        holding = true
        resume?.cancel()
        motion()
    }

    /// The hand left: the 3D turn picks up again a moment later, so a pause between two drags is not a lurch.
    private func letGo() {
        holding = false
        resume?.cancel()
        resume = Task { @MainActor in
            try? await Task.sleep(for: .seconds(BrainLook.resumeAfter))
            guard !Task.isCancelled else { return }
            motion()
        }
    }

    /// Plays the opening again: the core, the bands, the ring, then the applications.
    private func replay() {
        openedAt = Date()
        rest(after: openingLength)
    }

    /// Another view, the dots morphing there from where they were and the camera springing to its fit.
    private func choose(_ next: BrainMode) {
        guard next != mode else { return }
        morphFrom = mode
        morphAt = Date()
        mode = next
        motion()
        own = false
        glideTo(fitted(stage, next, prepared()))
        ease(for: BrainMotion.morphLength)
    }

    private func enterCinema() {
        cinema = true
        own = false
        glideTo(fitted(stage, mode, prepared()))
        motion()
        focused = true
    }

    private func leaveCinema() {
        cinema = false
        motion()
    }

    /// The camera holding every mark a view draws, by the marks' own bounds and the room each takes, so a small brain
    /// is framed close and a large one whole; the Timeline adds its lane names at the left.
    private func fitted(_ size: CGSize, _ mode: BrainMode, _ prepared: BrainPrepared) -> SurfaceCamera {
        var points: [(x: Double, y: Double, radius: Double)] = prepared.nodes.indices.map { index in
            let at = mode == .timeline ? prepared.timeline[index] : BrainArms.flat(prepared.spots[index])
            return (at.x, at.y, Self.size(prepared.spots[index]) + BrainLook.fitRoom)
        }
        if mode != .timeline {
            points += prepared.areas.map { ($0.x, $0.y, $0.radius + BrainLook.fitRoom) }
        } else if let lane = prepared.lanes.first {
            points.append((BrainLook.laneLabelX, lane.y, BrainLook.fitRoom))
        }
        return SurfaceCamera.fitted(points: points, size: (size.width, size.height))
    }

    /// Springs the camera from where it is seen now to a new place.
    private func glideTo(_ target: SurfaceCamera) {
        glide = BrainGlide(from: shownCamera(at: Date()), at: Date())
        camera = target
        ease(for: BrainMotion.springLength)
    }

    private func fit(_ size: CGSize) {
        own = false
        glideTo(fitted(size, mode, prepared()))
    }

    /// Center stands the 3D brain back up at its resting tilt and fits the view again.
    private func center() {
        yaw = 0
        fling = nil
        turnFrom = nil
        orbit = BrainClock()
        orbit.set(speed: speed, at: Date())
        pitch = SurfaceOrbit.restingPitch
        motion()
        fit(stage)
    }

    private func zoom(by factor: Double, size: CGSize) {
        own = true
        glideTo(camera.zoomed(by: factor, at: (size.width / 2, size.height / 2), size: (size.width, size.height)))
    }

    /// Watches the scroll wheel and the right button while the canvas is up, since SwiftUI hands neither to a view.
    private func watch() {
        monitor?.stop()
        monitor = EventMonitor.local([.scrollWheel, .rightMouseDown, .rightMouseDragged, .rightMouseUp]) { event in
            MainActor.assumeIsolated { handled(event) } ? nil : event
        }
    }

    /// The wheel zooms about the pointer, and a right drag pans, only while the pointer is over the canvas; anywhere
    /// else the event goes on, so the page still scrolls. Answers whether the canvas took it.
    private func handled(_ event: NSEvent) -> Bool {
        switch event.type {
        case .scrollWheel:
            // Over the open card the wheel scrolls the card, so the map lets the event go on to it.
            guard let pointer, stage.width > 0, !overCard else { return false }
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * MapMetrics.trackpadZoom
                : event.scrollingDeltaY * MapMetrics.wheelZoom
            guard delta != 0 else { return true }
            own = true
            camera = shownCamera(at: Date()).zoomed(by: exp(delta), at: (pointer.x, pointer.y), size: (stage.width, stage.height))
            glide = nil
            return true
        case .rightMouseDown:
            guard let pointer else { return false }
            panning = Hand(camera: shownCamera(at: Date()), yaw: yaw, pitch: pitch, pans: true, moved: true, start: pointer)
            hold()
            return true
        case .rightMouseDragged:
            guard let held = panning, let pointer else { return panning != nil }
            pan(from: held, by: CGSize(width: pointer.x - held.start.x, height: pointer.y - held.start.y))
            return true
        case .rightMouseUp:
            guard panning != nil else { return false }
            panning = nil
            letGo()
            return true
        default:
            return false
        }
    }

    private func pan(from start: Hand, by translation: CGSize) {
        own = true
        glide = nil
        camera = SurfaceCamera(x: start.camera.x - translation.width / start.camera.k,
                               y: start.camera.y - translation.height / start.camera.k, k: start.camera.k)
    }

    /// Turns the 3D brain from where a drag began, round and tipped, the tip short of looking straight down.
    private func turn(from start: Hand, by translation: CGSize) {
        yaw = start.yaw + translation.width * MapMotion.turnPerPoint
        pitch = min(max(start.pitch - translation.height * MapMotion.turnPerPoint, -SurfaceOrbit.pitchLimit), SurfaceOrbit.pitchLimit)
    }

    /// A drag let go mid turn coasts on at the speed it was going, the coast folded into the hand's turn first.
    private func flung(_ drag: DragGesture.Value) {
        let now = Date()
        if let fling { yaw += BrainMotion.coast(fling.speed, seconds: now.timeIntervalSince(fling.at)) }
        guard !reduceMotion else {
            fling = nil
            return
        }
        let ahead = (drag.predictedEndTranslation.width - drag.translation.width) * MapMotion.turnPerPoint
        fling = BrainFling(speed: ahead / BrainMotion.coastTime, at: now)
        ease(for: BrainMotion.coastTime * BrainLook.coastSettle)
    }

    /// The ground: dragged, it pans, or turns the 3D brain; clicked, it picks the mark under the pointer or puts the
    /// details away; double clicked it fits again.
    private func ground(_ size: CGSize, _ prepared: BrainPrepared) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let start = hand ?? startHand()
                    let moved = start.moved || hypot(drag.translation.width, drag.translation.height) > MapMetrics.aClick
                    var held = start
                    held.moved = moved
                    hand = held
                    guard moved else { return }
                    if !start.moved { hold() }
                    if start.pans { pan(from: start, by: drag.translation) } else { turn(from: start, by: drag.translation) }
                }
                .onEnded { drag in
                    if hand?.moved != true {
                        // AppKit counts the clicks, which a drag gesture does not.
                        if (NSApp.currentEvent?.clickCount ?? 1) >= MapMetrics.doubleClick {
                            fit(size)
                        } else {
                            pick(hit(drag.location, prepared), prepared)
                        }
                    } else {
                        if hand?.pans == false { flung(drag) }
                        letGo()
                    }
                    hand = nil
                    focused = true
                })
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Memory brain")
            .accessibilityChildren {
                // The canvas draws every mark in one pass, so VoiceOver is handed each as a button of its own.
                ForEach(prepared.walk, id: \.self) { index in
                    let node = prepared.nodes[index]
                    Text(node.label)
                        .accessibilityLabel("\(BrainWords.layerWord(prepared.spots[index].layer)), \(MapWords.kindWord(node.kind)), \(node.label)")
                        .accessibilityAddTraits(selected == node.id ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction { select(node, prepared.base) }
                }
            }
    }

    /// Where a drag begins: the 3D brain turns under it, everything else pans, and Option always pans.
    private func startHand() -> Hand {
        let now = Date()
        if let fling { yaw += BrainMotion.coast(fling.speed, seconds: now.timeIntervalSince(fling.at)) }
        fling = nil
        // A hand taking the brain mid flight holds it where it is seen, so the drag starts from what is on screen.
        if let turnFrom {
            if !reduceMotion { yaw = turnFrom.yaw + (yaw - turnFrom.yaw) * BrainMotion.spring(now.timeIntervalSince(turnFrom.at)) }
            self.turnFrom = nil
        }
        return Hand(camera: shownCamera(at: now), yaw: yaw, pitch: pitch,
                    pans: mode != .orbs || NSEvent.modifierFlags.contains(.option), moved: false)
    }

    /// A press on a mark opens it, and a memory hub lights its area too; the ground puts both away.
    private func pick(_ index: Int?, _ prepared: BrainPrepared) {
        guard let index else {
            if area != nil { pickArea(nil) }
            select(nil, prepared.base)
            return
        }
        if prepared.counts.contains(where: { $0.index == index }), let group = prepared.areaOf[index], group != area { pickArea(group) }
        // In 3D a picked node is turned to the front, so whatever was clicked at the back comes round to be read.
        if mode == .orbs { fly(to: index, prepared) }
        select(prepared.nodes[index], prepared.base)
    }

    /// F fits and C centers, as the console's keys do, R replays, M and the space bar turn Motion, one to three pick
    /// the view, slash searches and Escape leaves Cinema; arrows walk the marks, Return opens one, plus and minus zoom.
    private func keys(_ press: KeyPress, _ prepared: BrainPrepared) -> KeyPress.Result {
        // The search field is inside the canvas, so while it is typed in every key is a letter rather than a shortcut.
        if seekFocused { return .ignored }
        let middle = (x: Double(stage.width / 2), y: Double(stage.height / 2))
        if press.key == .escape {
            if selected != nil {
                select(nil, prepared.base)
                return .handled
            }
            if cinema {
                leaveCinema()
                return .handled
            }
            guard area != nil else { return .ignored }
            pickArea(nil)
            return .handled
        }
        if press.key == .space {
            motionOn.toggle()
            return .handled
        }
        switch press.characters.lowercased() {
        case BrainWords.searchKey:
            openSeek()
            return .handled
        case MapWords.fitKey.lowercased(), "0":
            fit(stage)
            return .handled
        case MapWords.centerKey.lowercased():
            center()
            return .handled
        case BrainWords.replayKey.lowercased():
            replay()
            return .handled
        case BrainWords.motionKey.lowercased():
            motionOn.toggle()
            return .handled
        case "1", "2", "3":
            if let digit = Int(press.characters), BrainMode.allCases.indices.contains(digit - 1) { choose(BrainMode.allCases[digit - 1]) }
            return .handled
        case "+", "=":
            own = true
            glideTo(camera.zoomed(by: MapMetrics.pressZoom, at: middle, size: (stage.width, stage.height)))
            return .handled
        case "-":
            own = true
            glideTo(camera.zoomed(by: 1 / MapMetrics.pressZoom, at: middle, size: (stage.width, stage.height)))
            return .handled
        default:
            break
        }
        if press.key == .return, let over, let index = prepared.index[over] {
            pick(index, prepared)
            return .handled
        }
        let step: Int
        switch press.key {
        case .rightArrow, .downArrow: step = 1
        case .leftArrow, .upArrow: step = -1
        default: return .ignored
        }
        let order = prepared.walk.map { prepared.nodes[$0].id }
        guard !order.isEmpty else { return .ignored }
        let here = order.firstIndex(of: focus ?? "") ?? (step > 0 ? -1 : 0)
        let next = order[(here + step + order.count) % order.count]
        hover(next)
        if let index = prepared.index[next] { fly(to: index, prepared) }
        return .handled
    }
}

/// Where a glide set off from and when, which the spring carries to the camera's target.
struct BrainGlide {
    let from: SurfaceCamera
    let at: Date
}

/// Where a flight to a node set the 3D brain's turn off from and when, which the spring carries to the new turn.
struct BrainTurnGlide {
    let yaw: Double
    let at: Date
}

/// A 3D brain let go mid turn: how fast it was turning, in radians a second, and when.
struct BrainFling {
    let speed: Double
    let at: Date
}

/// What a drawing is built from, so it is built again only when one of these changes.
struct BrainKey: Equatable {
    let graph: LocalGraphInputs
    let shown: MemoryHomeFilter
    let hiddenGroups: Set<SourceGroup>
    let hiddenLayers: Set<BrainLayer>
    let attentionOnly: Bool
    let hiddenKinds: Set<MemoryMapNodeKind>
    let hiddenLinks: Set<MemoryLinkKind>
}

/// The map as drawn, in flat arrays a frame walks without looking anything up: each mark's spot in the layers and on
/// the Timeline, its colour slot, area and hub, and every line by the indices of its ends.
struct BrainPrepared {
    /// The map under the home filter alone, which the details and the legend's counts read.
    let base: MemoryMap
    /// What is drawn once the legend, Attention and Display have taken their share off.
    let drawn: MemoryMap
    let nodes: [MemoryMapNode]
    let spots: [BrainArmSpot]
    /// How far round its ring a rule is, from 0 at the crown to 1, so the ring lights in that order.
    let around: [Double]
    let ink: [Int]
    /// Each memory mark's area, nil for the other layers.
    let areaOf: [SourceGroup?]
    /// Each memory piece's hub, by index, which its spoke runs to; nil runs to the core.
    let hubOf: [Int?]
    let hubs: [Int]
    let counts: [(index: Int, count: Int)]
    let sectors: [BrainSector]
    /// The colour slot each area is painted from, in the order its sector comes round.
    let areaSlots: [SourceGroup: Int]
    let timeline: [(x: Double, y: Double)]
    let ticks: [BrainTick]
    let lanes: [(layer: BrainLayer, y: Double)]
    /// Each layer's row of what says no time, for its name.
    let undated: [(layer: BrainLayer, y: Double)]
    let index: [String: Int]
    let lines: [(from: Int, to: Int)]
    let named: Set<String>
    let walk: [Int]
    let logos: [(index: Int, slug: String)]
    /// The icon a rule's disc or a server's tile wears where no logo is drawn.
    let faces: [(index: Int, symbol: String)]
    let ruleSymbols: [Int]
    let coreLabel: String?
    let present: Set<BrainLayer>
    /// The legend's rows: each memory area with its count, and each other layer with its count.
    let areaRows: [(group: SourceGroup, count: Int)]
    let layerRows: [(layer: BrainLayer, count: Int)]
    /// Each memory area's cluster, and each memory mark's area by its index there, nil for the other layers.
    let areas: [BrainArea]
    let areaAt: [Int?]
    /// Where each memory mark grows out of on the opening, its area's hub, nil for the other layers.
    let anchors: [(x: Double, y: Double)?]
    /// How far out each present layer reaches, as a share of the silhouette.
    let reaches: [BrainLayer: Double]
    /// Each application's ring number and how long ago it was last used, nil where the runtime said no time.
    let numbers: [Int?]
    let ages: [String?]
    /// The memory index, MEMORY.md, and the lines from it to every memory it lists.
    let indexAt: Int?
    let indexLines: [(from: Int, to: Int)]
    /// How many drawn lines touch each mark, said on its hover card.
    let degree: [Int]
    /// The folded text each mark is found by on the canvas, and how heavy it is, which orders the matches.
    let haystacks: [String]
    let weights: [Double]
    /// The logo each source hub wears, and each person's initials and avatar colour.
    let brands: [(index: Int, brand: BrainBrand)]
    let people: [(index: Int, initials: String, colour: Int)]
    let personSet: Set<Int>

    init(_ key: BrainKey, map base: MemoryMap) {
        self.base = base
        let groups = MemoryGroups.groups(base, sources: key.graph.sources)
        // Laid out from the whole map, so taking an area off never moves what stays.
        let layout = BrainArms.layout(base, groups: groups)
        sectors = layout.sectors
        var slots: [SourceGroup: Int] = [:]
        for (index, sector) in layout.sectors.enumerated() { slots[sector.group] = index }
        areaSlots = slots
        let layerOf = { (node: MemoryMapNode) in layout.spots[node.id]?.layer ?? .memory }
        var rows: [BrainLayer: Int] = [:]
        for node in base.nodes { rows[layerOf(node), default: 0] += 1 }
        areaRows = layout.sectors.map { ($0.group, $0.count) }
        layerRows = BrainLayer.allCases.filter { $0 != .memory }.compactMap { layer in rows[layer].map { (layer, $0) } }
        let cut = key.attentionOnly ? MemoryGroups.attention(base) : base
        let nodes = cut.nodes.filter { node in
            let layer = layerOf(node)
            guard !key.hiddenKinds.contains(node.kind), !key.hiddenLayers.contains(layer) else { return false }
            return layer != .memory || !key.hiddenGroups.contains(groups[node.id] ?? .unsourced)
        }
        let kept = Set(nodes.map(\.id))
        drawn = MemoryMap(nodes: nodes, edges: cut.edges.filter { !key.hiddenLinks.contains($0.kind) && kept.contains($0.from) && kept.contains($0.to) })
        self.nodes = nodes
        let index = Dictionary(nodes.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.index = index
        let fallback = BrainArmSpot(layer: .memory, angle: 0, share: 0, ring: 0, size: 0, latitude: 0)
        var spots: [BrainArmSpot] = []
        var around: [Double] = []
        var ink: [Int] = []
        var areaOf: [SourceGroup?] = []
        var hubOf: [Int?] = []
        var hubs: [Int] = []
        var counts: [(index: Int, count: Int)] = []
        var logos: [(index: Int, slug: String)] = []
        var faces: [(index: Int, symbol: String)] = []
        var rules: [Int] = []
        var moments: [Date?] = []
        var areaAt: [Int?] = []
        var anchors: [(x: Double, y: Double)?] = []
        var numbers: [Int?] = []
        var ages: [String?] = []
        var haystacks: [String] = []
        var weights: [Double] = []
        var brands: [(index: Int, brand: BrainBrand)] = []
        var people: [(index: Int, initials: String, colour: Int)] = []
        let areaIndex = Dictionary(layout.areas.enumerated().map { ($1.group, $0) }, uniquingKeysWith: { first, _ in first })
        let now = Date()
        for (at, node) in nodes.enumerated() {
            let spot = layout.spots[node.id] ?? fallback
            spots.append(spot)
            let turn = (spot.angle - BrainArms.start).truncatingRemainder(dividingBy: 2 * Double.pi)
            around.append((turn < 0 ? turn + 2 * Double.pi : turn) / (2 * Double.pi))
            let group = spot.layer == .memory ? groups[node.id] ?? .unsourced : nil
            areaOf.append(group)
            ink.append(ArmsInk.slot(spot.layer, area: group.flatMap { slots[$0] } ?? 0))
            hubOf.append(layout.hub[node.id].flatMap { index[$0] })
            if let count = layout.counts[node.id] {
                hubs.append(at)
                counts.append((at, count))
            }
            switch spot.layer {
            case .applications:
                if let slug = node.mark { logos.append((at, slug)) } else { faces.append((at, BrainWords.serverSymbol)) }
            case .rules:
                rules.append(at)
                faces.append((at, BrainWords.ruleSymbol(node)))
            case .skills, .memory:
                break
            }
            moments.append(BrainTimeline.moment(node.at))
            areaAt.append(group.flatMap { areaIndex[$0] })
            anchors.append(layout.anchors[node.id].map { ($0.x, $0.y) })
            numbers.append(layout.numbers[node.id])
            ages.append(spot.layer == BrainLayer.applications ? BrainArms.ageChip(BrainTimeline.moment(node.at), now: now) : nil)
            let source = key.graph.sources.first { MemoryMaps.sourceId($0.name) == node.id || MemoryMaps.sourceId($0.id) == node.id }
            let path = node.kind == .skill ? LocalGraphs.skillPath(key.graph.skills, node.id) : source?.location
            haystacks.append(BrainSearch.haystack([node.label, node.detail, node.memoryKind, MapWords.kindWord(node.kind), path, node.mark]))
            weights.append(spot.size + Double(node.weight))
            if node.kind == .source, let brand = BrainFaces.brand(kind: source?.sourceKind, name: source?.name ?? node.label,
                                                                   location: source?.location) {
                brands.append((at, brand))
            }
            if node.kind == .person {
                people.append((at, BrainFaces.initials(node.label), BrainFaces.colour(node.label, count: BrainFaces.avatarColours)))
            }
        }
        self.areas = layout.areas
        self.areaAt = areaAt
        self.anchors = anchors
        self.reaches = layout.reaches
        self.numbers = numbers
        self.ages = ages
        self.haystacks = haystacks
        self.weights = weights
        self.brands = brands
        self.people = people
        personSet = Set(people.map(\.index))
        self.spots = spots
        self.around = around
        self.ink = ink
        self.areaOf = areaOf
        self.hubOf = hubOf
        self.hubs = hubs
        self.counts = counts
        self.logos = logos
        self.faces = faces
        ruleSymbols = rules
        coreLabel = layout.coreLabel
        present = Set(spots.map(\.layer))
        let laid = BrainTimeline.layout(ids: nodes.map(\.id), layers: spots.map(\.layer), moments: moments, labels: nodes.map(\.label))
        timeline = laid.spots
        ticks = laid.ticks
        lanes = laid.lanes
        undated = laid.undated
        // Built into a local first, since a closure may not read a stored property before every one is set.
        let lines: [(from: Int, to: Int)] = drawn.edges.compactMap { edge in
            guard let from = index[edge.from], let to = index[edge.to] else { return nil }
            return (from, to)
        }
        self.lines = lines
        let indexAt = layout.index.flatMap { index[$0] }
        self.indexAt = indexAt
        indexLines = indexAt.map { hub in lines.filter { $0.from == hub || $0.to == hub } } ?? []
        var degree = Array(repeating: 0, count: nodes.count)
        for line in lines {
            degree[line.from] += 1
            degree[line.to] += 1
        }
        self.degree = degree
        named = MapNames.named(drawn)
        walk = MemoryMaps.walkOrder(drawn).compactMap { index[$0] }
    }
}

/// Keeps the last drawing across redraws of the page, since a hover or a frame must not build the map again.
@MainActor
final class BrainMemo {
    private var key: BrainKey?
    private var value: BrainPrepared?

    func prepared(_ key: BrainKey, build: () -> BrainPrepared) -> BrainPrepared {
        if let value, self.key == key { return value }
        let built = build()
        self.key = key
        value = built
        return built
    }
}

/// The sparks under way, kept across frames; a frame lets finished ones go as it draws, which is no change to the
/// page's state. Unchecked because the page and the canvas that draws it both run on the main thread, which SwiftUI
/// does not say.
final class BrainPulse: @unchecked Sendable {
    var sparks = BrainSparks()
}

/// One frame of the brain: each mark's spot, size, light and nearness on the screen.
struct BrainFrame {
    var x: [Double]
    var y: [Double]
    var radius: [Double]
    var light: [Double]
    var depth: [Double]
    /// Each memory area's hub on the screen, which its pieces' and its own spokes run to.
    var areas: [CGPoint]
}

/// How the brain moves and how its depth is drawn.
enum MapMotion {
    /// Thirty frames a second is smooth for a slow sway and half the work of sixty.
    static let frame: TimeInterval = 1.0 / 30
    /// How far a drag across the ground turns the brain, in radians per point.
    static let turnPerPoint = 0.004
    /// The back of the brain is drawn at this much of the front's brightness.
    static let dimBack = 0.45
}

enum MapMetrics {
    static let space = "memory-map"
    static let inset: CGFloat = 16
    /// The display panel, as wide as the console's folding panels.
    static let column: CGFloat = 264
    /// The heading's widest, so its subline wraps rather than running under the bar.
    static let headingWidth: CGFloat = 380
    /// The legend and the growth card, narrow so they hug the corners.
    static let cardWidth: CGFloat = 240
    /// A folding panel's chevron points down once it is open.
    static let openTurn = 90.0
    static let quietWidth: CGFloat = 380
    /// The canvas search's capsule: how far below the top it floats, and how wide it is.
    static let seekTop: CGFloat = 72
    static let seekWidth: CGFloat = 360
    /// The hover card: how wide it is, how far above the mark it starts and how tall it is at the most.
    static let tipWidth: CGFloat = 220
    static let tipLift = 18.0
    static let tipTall = 96.0
    static let tipLogo: CGFloat = 22
    /// The picked node's card, the console's: as wide as its w-80, as tall as its content up to 36rem, the least it
    /// is placed by before it is first measured, and half the pointer toward the node.
    static let detailWidth: CGFloat = 320
    static let detailMost: CGFloat = 576
    static let detailLeast: CGFloat = 160
    static let pointer: CGFloat = 6
    /// A square turned an eighth of a turn is the pointer's diamond.
    static let pointerTurn = 45.0
    /// How far one notch of a mouse wheel zooms, and one point of a trackpad's scroll, as the power the zoom is raised to.
    static let wheelZoom = 0.1
    static let trackpadZoom = 0.01
    /// The clicks that make a double click.
    static let doubleClick = 2
    /// The tallest a folding panel opens to before it scrolls.
    static let foldMost: CGFloat = 200
    /// How far the pointer may travel before a press stops being a click.
    static let aClick = 4.0
    static let pressZoom = 1.2
    /// Flying to a node draws at least this close, where its name and its neighbours' are written.
    static let flyZoom = 1.6
    static let sizeStep = 0.1
    /// Past this far out a name is a smear, so it is not drawn at all.
    static let namesFrom = 0.4
    static let shadow = 0.3
    static let shadowRadius: CGFloat = 12
    static let shadowDrop: CGFloat = 8
    /// A legend row's dot, a hidden row's light, and the growth bar's height.
    static let legendDot: CGFloat = 8
    static let hiddenRow = 0.4
    static let barHeight: CGFloat = 3
}

/// The brain's own words, in Memnox's voice.
/// The brain's own words, in Memnox's voice.
enum BrainWords {
    static let replayKey = "R"
    static let motionKey = "M"
    static let searchKey = "/"
    static let seekPrompt = "SEARCH THE BRAIN"
    static let leftHint = "Drag to pan · Scroll to zoom · 1 2 3 switch views"
    static let orbsHint = "Drag to orbit · Arrows fly node to node · Click turns it to you · Scroll to zoom"
    static let rightHint = "Space for Motion · / to search · Double click to fit"
    static let undated = "No date"
    /// Routines are not something Memnox runs yet, so the band says what runs without the person today.
    static let routinesLater = "Routines come later; this ring holds the rules and standing permissions that run without you today."
    static let serverSymbol = "server.rack"

    static func label(_ group: SourceGroup) -> String {
        switch group {
        case .notes: "Notes"
        case .instructions: "Agent instructions"
        case .servers: "Memory servers"
        case .conversations: "Conversations"
        case .projects: "Projects"
        case .apps: "Apps and tools"
        case .team: "Workspace"
        case .unsourced: "Cites nothing"
        }
    }

    /// A layer's name in the capitals its band is labelled with.
    static func layerName(_ layer: BrainLayer) -> String {
        switch layer {
        case .skills: "SKILLS"
        case .memory: "MEMORY"
        case .rules: "RULES"
        case .applications: "APPLICATIONS"
        }
    }

    /// A layer said in a sentence, for VoiceOver and the legend.
    static func layerWord(_ layer: BrainLayer) -> String {
        switch layer {
        case .skills: "Skills"
        case .memory: "Memory"
        case .rules: "Rules"
        case .applications: "Applications"
        }
    }

    /// The icon a rule's disc wears, by what the rule does.
    static func ruleSymbol(_ node: MemoryMapNode) -> String {
        switch RuleEffect(rawValue: node.detail ?? "") {
        case .allow: "checkmark"
        case .ask: "hand.raised"
        case .deny: "nosign"
        case nil: "shield"
        }
    }

    /// A moment on the Timeline's axis, by its day.
    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year(.twoDigits))
    }

    static func inView(_ count: Int) -> String {
        "\(count) \(count == 1 ? "POINT" : "POINTS") IN VIEW"
    }

    /// Under the canvas search: how many matched, and that Enter opens the best.
    static func matches(_ count: Int) -> String {
        count == 0 ? "NO MATCHES" : "\(counted(count, "MATCH", "MATCHES")) · ENTER OPENS"
    }

    static func counted(_ count: Int, _ one: String, _ many: String) -> String {
        "\(count) \(count == 1 ? one : many)"
    }
}

private struct BrainHeading<Foot: View>: View {
    let stats: MemoryStats
    @ViewBuilder let foot: Foot

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            Text("WHAT YOUR AGENTS KNOW")
                .font(Memnox.Console.code(Memnox.Console.Brain.overline, .medium))
                .tracking(Memnox.Console.headingTracking)
                .foregroundStyle(Memnox.Console.Brain.quiet)
            VStack(alignment: .leading, spacing: 0) {
                Text("Every memory.").foregroundStyle(Memnox.Console.Brain.ink)
                Text("Connected.").foregroundStyle(Memnox.Console.Brain.faint)
            }
            .font(Memnox.Console.sans(Memnox.Console.Brain.headline, .semibold))
            .tracking(Memnox.Console.titleTracking)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Text("Skills at the core, memory in a sector to each area, the rules that run without you in a ring, and your applications around the outside.")
                .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
                .foregroundStyle(Memnox.Console.Brain.quiet)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: Memnox.Spacing.xxLarge) {
                stat(stats.memories, "MEMORIES")
                stat(stats.sources, "SOURCES")
                stat(stats.connections, "CONNECTIONS")
            }
            .padding(.top, Memnox.Spacing.xSmall)
            foot
        }
        .frame(maxWidth: MapMetrics.headingWidth, alignment: .leading)
    }

    private func stat(_ count: Int, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
            Text("\(count)")
                .font(Memnox.Console.sans(Memnox.Console.Brain.numeral, .semibold).monospacedDigit())
                .foregroundStyle(Memnox.Console.Brain.ink)
            Text(caption)
                .font(Memnox.Console.code(Memnox.Console.Brain.caption, .medium))
                .tracking(Memnox.Console.headingTracking)
                .foregroundStyle(Memnox.Console.Brain.faint)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The sources: each group with its colour and count, a press taking it off the brain or putting it back, then the
/// two checks.
/// The areas and the layers: each memory area with its colour and count, a press lighting its sector and the eye
/// taking it off the brain or putting it back; each other layer the same way; then the two checks.
private struct BrainLegend: View {
    let areas: [(group: SourceGroup, count: Int)]
    let layers: [(layer: BrainLayer, count: Int)]
    let slots: [SourceGroup: Int]
    @Binding var hidden: Set<SourceGroup>
    @Binding var hiddenLayers: Set<BrainLayer>
    let area: SourceGroup?
    let pick: (SourceGroup?) -> Void
    @Binding var attentionOnly: Bool
    @Binding var allLabels: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
            heading("MEMORY AREAS")
            ForEach(areas, id: \.group) { row in
                let on = !hidden.contains(row.group)
                let ink = ArmsInk.of(slot: slots[row.group] ?? 0)
                HStack(spacing: Memnox.Spacing.regular) {
                    Button { pick(row.group) } label: {
                        HStack(spacing: Memnox.Spacing.regular) {
                            dot(ink)
                            Text(BrainWords.label(row.group))
                                .font(Memnox.Console.sans(Memnox.Console.TextSize.meta, area == row.group ? .semibold : .regular))
                                .foregroundStyle(Memnox.Console.Brain.ink)
                                .lineLimit(1)
                            Spacer(minLength: Memnox.Spacing.small)
                            Text("\(row.count)")
                                .font(Memnox.Console.code(Memnox.Console.TextSize.meta).monospacedDigit())
                                .foregroundStyle(Memnox.Console.Brain.quiet)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointingHand()
                    .accessibilityLabel("\(BrainWords.label(row.group)), \(row.count)")
                    .accessibilityValue(area == row.group ? "Lit" : "")
                    .accessibilityHint("Lights its sector on the brain")
                    eye(on: on, name: BrainWords.label(row.group)) {
                        if on { hidden.insert(row.group) } else { hidden.remove(row.group) }
                    }
                }
                .opacity(on ? 1 : MapMetrics.hiddenRow)
                .padding(.vertical, Memnox.Spacing.xxSmall)
            }
            if !layers.isEmpty {
                heading("LAYERS").padding(.top, Memnox.Spacing.xSmall)
                ForEach(layers, id: \.layer) { row in
                    let on = !hiddenLayers.contains(row.layer)
                    HStack(spacing: Memnox.Spacing.regular) {
                        dot(ArmsInk.of(row.layer))
                        Text(BrainWords.layerWord(row.layer))
                            .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                            .foregroundStyle(Memnox.Console.Brain.ink)
                            .lineLimit(1)
                        Spacer(minLength: Memnox.Spacing.small)
                        Text("\(row.count)")
                            .font(Memnox.Console.code(Memnox.Console.TextSize.meta).monospacedDigit())
                            .foregroundStyle(Memnox.Console.Brain.quiet)
                        eye(on: on, name: BrainWords.layerWord(row.layer)) {
                            if on { hiddenLayers.insert(row.layer) } else { hiddenLayers.remove(row.layer) }
                        }
                    }
                    .opacity(on ? 1 : MapMetrics.hiddenRow)
                    .padding(.vertical, Memnox.Spacing.xxSmall)
                    .accessibilityElement(children: .combine)
                    if row.layer == .rules {
                        Text(BrainWords.routinesLater)
                            .font(Memnox.Console.sans(Memnox.Console.TextSize.label))
                            .foregroundStyle(Memnox.Console.Brain.faint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Rectangle().fill(Memnox.Console.Brain.edge).frame(height: Memnox.Stroke.hairline)
                .padding(.vertical, Memnox.Spacing.xSmall)
            check("Only what needs attention", on: $attentionOnly)
            check("Show all labels", on: $allLabels)
        }
        .padding(Memnox.Spacing.large)
        .frame(width: MapMetrics.cardWidth, alignment: .leading)
        .mapPanel(radius: Memnox.Console.cardRadius)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Areas and layers")
    }

    private func heading(_ words: String) -> some View {
        Text(words)
            .font(Memnox.Console.code(Memnox.Console.Brain.caption, .medium))
            .tracking(Memnox.Console.headingTracking)
            .foregroundStyle(Memnox.Console.Brain.faint)
            .padding(.bottom, Memnox.Spacing.xSmall)
    }

    private func dot(_ ink: Color) -> some View {
        Circle().fill(ink)
            .frame(width: MapMetrics.legendDot, height: MapMetrics.legendDot)
            .shadow(color: ink, radius: MapMetrics.legendDot / 2)
    }

    private func eye(on: Bool, name: String, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            Image(systemName: on ? "eye" : "eye.slash")
                .font(.system(size: Memnox.TextSize.caption))
                .foregroundStyle(Memnox.Console.Brain.quiet)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHand()
        .help(on ? "Hide \(name)" : "Show \(name)")
        .accessibilityLabel(on ? "Hide \(name)" : "Show \(name)")
    }

    private func check(_ title: String, on: Binding<Bool>) -> some View {
        Button { on.wrappedValue.toggle() } label: {
            HStack(spacing: Memnox.Spacing.regular) {
                MapBox(on: on.wrappedValue)
                Text(title)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                    .foregroundStyle(Memnox.Console.Brain.ink)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHand()
        .accessibilityLabel(title)
        .accessibilityValue(on.wrappedValue ? "On" : "Off")
    }
}

private struct BrainGrowth: View {
    let verified: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
            Text(BrainWords.counted(total, "memory in the brain", "memories in the brain"))
                .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium).monospacedDigit())
                .foregroundStyle(Memnox.Console.Brain.ink)
            Text("\(verified) verified, \(total - verified) still to settle")
                .font(Memnox.Console.sans(Memnox.Console.TextSize.meta).monospacedDigit())
                .foregroundStyle(Memnox.Console.Brain.quiet)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Memnox.Console.Brain.edge)
                    Capsule().fill(Memnox.Console.primary)
                        .frame(width: geometry.size.width * CGFloat(verified) / CGFloat(max(total, 1)))
                }
            }
            .frame(height: MapMetrics.barHeight)
        }
        .padding(Memnox.Spacing.large)
        .frame(width: MapMetrics.cardWidth, alignment: .leading)
        .mapPanel(radius: Memnox.Console.cardRadius)
        .accessibilityElement(children: .combine)
    }
}

/// A rounded button along the foot, Replay or Cinema.
private struct BrainPill: View {
    let symbol: String
    let title: String
    let help: String
    let enabled: Bool
    let action: () -> Void

    private static let disabled = 0.35

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(Memnox.Console.sans(Memnox.Console.TextSize.meta, .medium))
                .foregroundStyle(Memnox.Console.Brain.ink)
                .padding(.horizontal, Memnox.Spacing.large)
                .frame(height: Memnox.Console.controlHeight)
                .background(Memnox.Console.Brain.card, in: Capsule())
                .overlay(Capsule().strokeBorder(Memnox.Console.Brain.edge, lineWidth: Memnox.Stroke.hairline))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHand()
        .disabled(!enabled)
        .opacity(enabled ? 1 : Self.disabled)
        .help(help)
        .accessibilityLabel(title)
    }
}

/// The canvas search, a capsule centred over the brain: typing dims all but the matches, the count says how many,
/// Enter opens the best and Escape puts it away.
private struct BrainSeek: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    /// How many marks match, nil while the field holds no word.
    let found: Int?
    let open: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: Memnox.Spacing.small) {
            HStack(spacing: Memnox.Spacing.medium) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Memnox.Console.Brain.quiet)
                    .accessibilityHidden(true)
                TextField("", text: $text, prompt: Text(BrainWords.seekPrompt).foregroundColor(Memnox.Console.Brain.faint))
                    .textFieldStyle(.plain)
                    .font(Memnox.Console.code(Memnox.Console.TextSize.meta, .medium))
                    .tracking(Memnox.Console.headingTracking)
                    .foregroundStyle(Memnox.Console.Brain.ink)
                    .focused(focused)
                    .onSubmit(open)
                    .onKeyPress(.escape) {
                        close()
                        return .handled
                    }
                    .accessibilityLabel("Search the brain")
                Button(action: close) {
                    Image(systemName: "xmark").foregroundStyle(Memnox.Console.Brain.quiet)
                }
                .buttonStyle(.plain)
                .pointingHand()
                .accessibilityLabel("Close the search")
            }
            .padding(.horizontal, Memnox.Spacing.large)
            .frame(width: MapMetrics.seekWidth, height: Memnox.Console.controlHeight)
            .background(Memnox.Console.Brain.card.opacity(BrainPanel.fill), in: Capsule())
            .overlay(Capsule().strokeBorder(Memnox.Console.Brain.edge, lineWidth: Memnox.Stroke.hairline))
            if let found {
                Text(BrainWords.matches(found))
                    .font(Memnox.Console.code(Memnox.Console.Brain.caption, .medium))
                    .tracking(Memnox.Console.headingTracking)
                    .foregroundStyle(found > 0 ? Memnox.Console.Brain.quiet : Memnox.Console.Brain.faint)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }
}

/// The picked node's details on the console's card beside it, as tall as what it holds up to the most, with a small
/// pointer toward the node; no backdrop, so the map keeps its zoom and hover around it.
private struct BrainDetailCard<Content: View>: View {
    let spot: BrainCardSpot
    let tallest: CGFloat
    /// Its height as drawn, so the next frame places it by its real size.
    let measured: (CGFloat) -> Void
    let hovering: (Bool) -> Void
    @ViewBuilder let content: Content

    var body: some View {
        // Offered the most it may be, it takes only what it holds, which is measured for the next frame's placing.
        content
            .frame(width: MapMetrics.detailWidth)
            .mapPanel(radius: Memnox.Console.cardRadius)
            .background(GeometryReader { geometry in
                Color.clear.preference(key: BrainCardHeight.self, value: geometry.size.height)
            })
            .onPreferenceChange(BrainCardHeight.self) { height in
                MainActor.assumeIsolated { measured(height) }
            }
            .overlay(alignment: .topLeading) { pointer }
            .onHover(perform: hovering)
            .frame(width: MapMetrics.detailWidth, height: tallest, alignment: .topLeading)
            .offset(x: spot.x, y: spot.y)
            .opacity(spot.visible ? 1 : 0)
            .accessibilityElement(children: .contain)
    }

    /// A small diamond on the edge facing the node, half of it showing past the card.
    private var pointer: some View {
        let half = MapMetrics.pointer
        return Rectangle()
            .fill(Memnox.Console.Brain.card)
            .frame(width: half * 2, height: half * 2)
            .rotationEffect(.degrees(MapMetrics.pointerTurn))
            .offset(x: spot.pointer.x - half, y: spot.pointer.y - half)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The card's measured height, carried up from its background.
private struct BrainCardHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The hover card: the mark's logo or avatar where it has one, its name, what it is and where, and its lines.
private struct BrainTipCard: View {
    let name: String
    let kind: String
    let place: String
    let links: Int
    let brand: BrainBrand?
    let person: (initials: String, ink: Color)?

    var body: some View {
        HStack(alignment: .top, spacing: Memnox.Spacing.medium) {
            if let person {
                Text(person.initials)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.label, .semibold))
                    .foregroundStyle(Memnox.Console.Brain.ink)
                    .frame(width: MapMetrics.tipLogo, height: MapMetrics.tipLogo)
                    .background(person.ink, in: Circle())
            } else if let brand {
                BrainBrandMark(brand: brand, side: MapMetrics.tipLogo)
            }
            VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                Text(MapNames.short(name))
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
                    .foregroundStyle(Memnox.Console.Brain.ink)
                    .lineLimit(2)
                Text("\(kind.uppercased()) · \(place.uppercased())")
                    .font(Memnox.Console.code(Memnox.Console.Brain.caption, .medium))
                    .foregroundStyle(Memnox.Console.Brain.quiet)
                    .lineLimit(1)
                Text(BrainWords.counted(links, "LINK", "LINKS"))
                    .font(Memnox.Console.code(Memnox.Console.Brain.caption))
                    .foregroundStyle(Memnox.Console.Brain.faint)
            }
        }
        .padding(Memnox.Spacing.medium)
        .mapPanel(radius: Memnox.Console.controlRadius)
    }
}

/// A source's or a tool's logo on a round light tile: a tool's by its Composio slug, an agent's by its own file.
struct BrainBrandMark: View {
    let brand: BrainBrand
    let side: CGFloat

    private static let agentShare: CGFloat = 0.62

    var body: some View {
        switch brand {
        case .toolkit(let slug):
            ToolMark(toolkit: slug, side: side).clipShape(Circle())
        case .agent(let kind):
            AgentLogo(kind: kind, name: kind)
                .frame(width: side * Self.agentShare, height: side * Self.agentShare)
                .frame(width: side, height: side)
                .background(Color.white, in: Circle())
                .accessibilityHidden(true)
        }
    }
}

/// The empty brain's word, over the outline, so a first visit sees what will fill it.
private struct MapQuietCard: View {
    let line: String

    var body: some View {
        VStack(spacing: Memnox.Spacing.small) {
            Image(systemName: "brain")
                .font(.system(size: Memnox.TextSize.body, weight: .medium))
                .foregroundStyle(Memnox.Console.primary)
                .accessibilityHidden(true)
            Text(line)
                .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
                .foregroundStyle(Memnox.Console.Brain.quiet)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Memnox.Spacing.xLarge)
        .padding(.vertical, Memnox.Spacing.large)
        .frame(maxWidth: MapMetrics.quietWidth)
        .mapPanel(radius: Memnox.Console.cardRadius)
    }
}

/// The canvas's own chrome in one small group: zoom out, the zoom, zoom in, Fit, Center and Pause, then Display, which
/// opens what is shown, the lines, the size of the marks and the legend in a panel of its own.
/// The view's own controls along the top right: the three views, Motion with its speed, and Display, which opens
/// what is shown, the lines, the size of the marks and the legend in a panel of its own.
private struct BrainViewControls: View {
    let mode: BrainMode
    let choose: (BrainMode) -> Void
    @Binding var motionOn: Bool
    @Binding var speed: Double
    /// Reduce Motion is on, so nothing moves on its own and there is no speed to set.
    let still: Bool
    @Binding var nodeSize: Double
    let map: MemoryMap
    @Binding var hiddenKinds: Set<MemoryMapNodeKind>
    @Binding var hiddenLinks: Set<MemoryLinkKind>
    @State private var display = false

    private static let slider: CGFloat = 84
    private static let divider: CGFloat = 16

    var body: some View {
        HStack(spacing: Memnox.Spacing.xSmall) {
            ForEach(BrainMode.allCases, id: \.self) { each in
                let on = mode == each
                Button { choose(each) } label: {
                    Label(each.title, systemImage: each.symbol)
                        .labelStyle(KitLabel())
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.meta, on ? .medium : .regular))
                        .foregroundStyle(on ? Memnox.Console.Brain.ink : Memnox.Console.Brain.quiet)
                        .padding(.horizontal, Memnox.Spacing.medium)
                        .frame(height: Memnox.Console.controlHeight - Memnox.Spacing.small)
                        .background(on ? Memnox.Console.active : Color.clear,
                                    in: RoundedRectangle(cornerRadius: Memnox.Console.controlRadius, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHand()
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
            rule
            if !still {
                MapButton(symbol: motionOn ? "sparkles" : "pause", label: "Motion \(motionOn ? "on" : "off"), or press \(MapWords.pauseKey)",
                          on: motionOn) { motionOn.toggle() }
                Slider(value: $speed, in: BrainMotion.slowest...BrainMotion.quickest)
                    .controlSize(.mini)
                    .frame(width: Self.slider)
                    .disabled(!motionOn)
                    .help("Speed")
                    .accessibilityLabel("Motion speed")
                rule
            }
            MapButton(symbol: "slider.horizontal.3", label: "Display", on: display) { display.toggle() }
                .popover(isPresented: $display, arrowEdge: .top) {
                    MapDisplay(nodeSize: $nodeSize, map: map, hiddenKinds: $hiddenKinds, hiddenLinks: $hiddenLinks)
                        .consoleLook()
                }
        }
        .padding(Memnox.Spacing.xSmall)
        .mapPanel(radius: Memnox.Console.controlRadius)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("View controls")
    }

    private var rule: some View {
        Rectangle().fill(Memnox.Console.Brain.edge).frame(width: Memnox.Stroke.hairline, height: Self.divider)
    }
}

/// The zoom in the bottom right corner: out, Fit, and in.
private struct MapZoom: View {
    let camera: SurfaceCamera
    let fit: () -> Void
    let zoom: (Double) -> Void

    var body: some View {
        HStack(spacing: Memnox.Spacing.xxSmall) {
            MapButton(symbol: "minus", label: "Zoom out", enabled: camera.k > SurfaceGeometry.zoomMin) { zoom(1 / MapMetrics.pressZoom) }
            Button(action: fit) {
                Text("Fit")
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.meta, .medium))
                    .foregroundStyle(Memnox.Console.Brain.ink)
                    .padding(.horizontal, Memnox.Spacing.medium)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHand()
            .help("Fit the whole brain on screen, or press \(MapWords.fitKey)")
            MapButton(symbol: "plus", label: "Zoom in", enabled: camera.k < SurfaceGeometry.zoomMax) { zoom(MapMetrics.pressZoom) }
        }
        .padding(Memnox.Spacing.xSmall)
        .mapPanel(radius: Memnox.Console.controlRadius)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Zoom")
    }
}

private struct MapDisplay: View {
    @Binding var nodeSize: Double
    let map: MemoryMap
    @Binding var hiddenKinds: Set<MemoryMapNodeKind>
    @Binding var hiddenLinks: Set<MemoryLinkKind>
    @State private var open: Fold? = .show

    private enum Fold {
        case show
        case connections
        case legend
    }

    private static let percent = 100.0
    /// Sizes step in tenths, rounded so repeated steps never drift off the tenth.
    private static let tenths = 10.0

    var body: some View {
        let kinds = MapWords.kinds.map { kind in
            MapToggle(id: kind, label: MapWords.kindLabel(kind), count: map.nodes.filter { $0.kind == kind }.count)
        }
        let links = MemoryLinkKind.allCases.map { kind in
            MapToggle(id: kind, label: MapInk.of(kind).label, count: map.edges.filter { $0.kind == kind }.count)
        }
        VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
            MapSetting(label: "Size", percent: Int((nodeSize * Self.percent).rounded()),
                       atFloor: nodeSize <= SurfaceGeometry.nodeSizeMin, atCeiling: nodeSize >= SurfaceGeometry.nodeSizeMax,
                       down: { nodeSize = max(SurfaceGeometry.nodeSizeMin, ((nodeSize - MapMetrics.sizeStep) * Self.tenths).rounded() / Self.tenths) },
                       up: { nodeSize = min(SurfaceGeometry.nodeSizeMax, ((nodeSize + MapMetrics.sizeStep) * Self.tenths).rounded() / Self.tenths) })
            // The count on a folded panel says when part of the record is off the drawing.
            MapFold(name: "Show", note: "\(kinds.count - hiddenKinds.count)/\(kinds.count)", most: MapMetrics.foldMost, open: open == .show,
                    fold: { toggle(.show) }) {
                MapGroup(rows: kinds, hidden: $hiddenKinds) { kind in
                    Image(systemName: MapMark.symbol(kind))
                        .font(.system(size: Memnox.TextSize.caption))
                        .foregroundStyle(Memnox.Console.muted)
                        .frame(width: MapLegendSample.width)
                }
            }
            MapFold(name: "Connections", note: "\(links.count - hiddenLinks.count)/\(links.count)", most: MapMetrics.foldMost,
                    open: open == .connections,
                    fold: { toggle(.connections) }) {
                MapGroup(rows: links, hidden: $hiddenLinks) { kind in MapLegendSample(dash: MapInk.of(kind).dash) }
            }
            MapFold(name: "Legend", most: MapMetrics.foldMost, open: open == .legend, fold: { toggle(.legend) }) {
                MapLegend()
            }
        }
        .frame(width: MapMetrics.column, alignment: .leading)
        .padding(Memnox.Spacing.medium)
    }

    private func toggle(_ fold: Fold) {
        withAnimation(.easeOut(duration: Memnox.Motion.quick)) { open = open == fold ? nil : fold }
    }
}

/// How to read the brain, inside the Legend panel.
private struct MapLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            Text("The brain is drawn in layers from its core out. The skills your agents are given shine at the core beside the instruction files they read. Memory fills the dotted bands, a sector to each area, each hub at the inner edge with its count and its pieces fanned out behind it, the heaviest nearest. The gold ring holds the rules in force and standing permissions, and your apps, MCP servers and workspace tools sit in tiles around the outside.")
                .foregroundStyle(Memnox.Console.muted)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(MemoryLinkKind.allCases, id: \.self) { kind in
                let ink = MapInk.of(kind)
                Text(ink.label).foregroundStyle(Memnox.Console.foreground).fontWeight(.medium)
                    + Text(", \(ink.meaning.lowercased())").foregroundStyle(Memnox.Console.muted)
            }
            Text("A colour is an area, as the legend lists them; press one to light its sector. Agents are not drawn; a piece's details say which agents used it. A spark runs in to the core when memory changes, and a warm bead while a conversation works.")
                .foregroundStyle(Memnox.Console.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text("Drag to pan the map and the Timeline and to orbit the 3D orbs, hold Option or use the right button to pan, scroll or pinch to zoom about the pointer, and double click to fit it again.")
                .foregroundStyle(Memnox.Console.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
    }
}

private extension View {
    /// A small bordered card floating over the brain, on the console's dark card in either appearance.
    func mapPanel(radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(Memnox.Console.Brain.card.opacity(BrainPanel.fill), in: shape)
            .overlay(shape.strokeBorder(Memnox.Console.Brain.edge, lineWidth: Memnox.Stroke.hairline))
            .shadow(color: .black.opacity(MapMetrics.shadow), radius: MapMetrics.shadowRadius, y: MapMetrics.shadowDrop)
    }
}

/// A card lets a little of the brain through, so it reads as floating over it.
enum BrainPanel {
    static let fill = 0.88
}

/// The words the graph says, kept together so the heading, the panels and the keys agree.
enum MapWords {
    static let fitKey = "F"
    static let centerKey = "C"
    static let pauseKey = "Space"

    /// The kinds of node in the order the Show panel lists them, the console's order where it has the same kind.
    static let kinds: [MemoryMapNodeKind] = [.memory, .document, .source, .conversation, .rule, .workspace, .app, .decision, .person,
                                             .skill, .standing]

    /// The console's names where it draws the same kind, and plain ones for what only this Mac has.
    static func kindLabel(_ kind: MemoryMapNodeKind) -> String {
        switch kind {
        case .memory: "Memories"
        case .document: "Documents"
        case .source: "Sources"
        case .conversation: "Conversations"
        case .rule: "Rules in force"
        case .workspace: "Projects"
        case .app: "Apps"
        case .decision: "Workspace decisions"
        case .person: "People"
        case .skill: "Skills"
        case .standing: "Rules and permissions"
        }
    }

    /// One node's kind, said alone at the head of its details.
    static func kindWord(_ kind: MemoryMapNodeKind) -> String {
        switch kind {
        case .memory: "Memory"
        case .document: "Document"
        case .source: "Source"
        case .conversation: "Conversation"
        case .rule: "Rule"
        case .workspace: "Project"
        case .app: "App"
        case .decision: "Workspace decision"
        case .person: "Person"
        case .skill: "Skill"
        case .standing: "Rule in force"
        }
    }
}

/// A line's dash and the words for it, as the console's legend says them where it has the same line. Every line is the
/// console's blue, so the kinds are told apart by their dash and their arrow.
struct MapInk {
    let label: String
    let meaning: String
    let dash: [CGFloat]
    /// False where the line says where something belongs rather than what it points at, so no head is drawn.
    var arrow = true

    static let stroke = Memnox.Console.primary
    static let width = 1.2
    static let litWidth = 2.0
    /// Thin and quiet at rest, so the marks carry the picture and the lines only join them.
    static let restingOpacity = 0.45
    /// The glow under a line: this much of its opacity, and this many times its width.
    static let glowShare = 0.22
    static let glowWidth = 4.0
    /// A passage that changed since it was read is drawn broken, as the list strikes it through.
    static let staleDash: [CGFloat] = [2, 5]
    private static let broken: [CGFloat] = [5, 4]
    private static let dotted: [CGFloat] = [1, 4]

    static func of(_ kind: MemoryLinkKind) -> MapInk {
        switch kind {
        case .cites: MapInk(label: "Derives", meaning: "Was read out of this document", dash: [])
        case .heldIn: MapInk(label: "Read from", meaning: "The document was read out of this source", dash: [], arrow: false)
        case .governs: MapInk(label: "Governs", meaning: "Confirming it raises this rule", dash: [])
        case .restates: MapInk(label: "Restates", meaning: "Says again what an earlier fact said", dash: broken)
        case .worksIn: MapInk(label: "Works in", meaning: "The conversation ran in this project's folder", dash: broken, arrow: false)
        case .reads: MapInk(label: "Reads", meaning: "The conversation read this through a call", dash: dotted)
        case .within: MapInk(label: "Kept for", meaning: "Kept for this project", dash: broken, arrow: false)
        case .pulledFrom: MapInk(label: "Pulled from", meaning: "The workspace read it out of this tool", dash: [], arrow: false)
        case .said: MapInk(label: "Said", meaning: "This person said what it was read out of", dash: dotted)
        case .names: MapInk(label: "Names", meaning: "Names this person as owner, approver or party", dash: broken)
        case .confirmed: MapInk(label: "Confirmed", meaning: "This person confirmed it for the workspace", dash: [])
        case .memberOf: MapInk(label: "Member of", meaning: "The directory puts this person here", dash: broken, arrow: false)
        case .linksTo: MapInk(label: "Links to", meaning: "Its words link to this, often in another tool", dash: dotted)
        case .relates: MapInk(label: "Relates", meaning: "Says something alike, proposed by comparison and stated by nobody", dash: dotted, arrow: false)
        }
    }
}

/// A pill holding a number: what it is, what it is at, and a step either side.
private struct MapSetting: View {
    let label: String
    let percent: Int
    let atFloor: Bool
    let atCeiling: Bool
    let down: () -> Void
    let up: () -> Void

    /// Wide enough for 300 percent, so the pill does not twitch wider on the way from 90 to 100.
    private static let readout: CGFloat = 40

    var body: some View {
        HStack(spacing: Memnox.Spacing.xSmall) {
            Text(label)
                .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
                .foregroundStyle(Memnox.Console.foreground)
            Text("\(percent)%")
                .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall).monospacedDigit())
                .foregroundStyle(Memnox.Console.muted)
                .frame(width: Self.readout, alignment: .trailing)
                .accessibilityLabel("\(label) \(percent) percent")
            MapButton(symbol: "minus", label: "\(label) down", enabled: !atFloor, action: down)
            MapButton(symbol: "plus", label: "\(label) up", enabled: !atCeiling, action: up)
        }
        .padding(.leading, Memnox.Spacing.large)
        .padding(.trailing, Memnox.Spacing.xSmall)
        .frame(height: Memnox.Console.controlHeight)
        .mapPanel(radius: Memnox.Console.controlRadius)
    }
}

private struct MapButton: View {
    let symbol: String
    let label: String
    var enabled = true
    /// Lit while what it opens is open.
    var on = false
    let action: () -> Void

    private static let side: CGFloat = 26
    private static let disabled = 0.35

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: Memnox.TextSize.caption, weight: .medium))
                .foregroundStyle(on ? Memnox.Console.primary : Memnox.Console.muted)
                .frame(width: Self.side, height: Self.side)
                .background(on ? Memnox.Console.active : Color.clear,
                            in: RoundedRectangle(cornerRadius: Memnox.Console.controlRadius, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverLight(radius: Memnox.Console.controlRadius, inset: 0)
        .disabled(!enabled)
        .opacity(enabled ? 1 : Self.disabled)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// A pill that opens onto something read rather than held, with its count said while it is folded.
private struct MapFold<Content: View>: View {
    let name: String
    var note: String?
    /// The tallest it opens to before it scrolls, so a long list never pushes the column over the heading.
    var most: CGFloat?
    let open: Bool
    let fold: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: fold) {
                HStack(spacing: Memnox.Spacing.medium) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: Memnox.TextSize.caption, weight: .semibold))
                        .foregroundStyle(Memnox.Console.muted)
                        .rotationEffect(.degrees(open ? MapMetrics.openTurn : 0))
                        .accessibilityHidden(true)
                    Text(name)
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
                        .foregroundStyle(Memnox.Console.foreground)
                    Spacer(minLength: Memnox.Spacing.small)
                    if let note {
                        Text(note)
                            .font(Memnox.Console.sans(Memnox.Console.TextSize.label).monospacedDigit())
                            .foregroundStyle(Memnox.Console.muted)
                    }
                }
                .padding(.horizontal, Memnox.Spacing.large)
                .frame(height: Memnox.Console.controlHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHand()
            .accessibilityLabel(name)
            .accessibilityValue(open ? "Open" : "Folded")
            if open {
                Rectangle().fill(Memnox.Console.border).frame(height: Memnox.Stroke.hairline)
                if let most {
                    ScrollView(.vertical) { body(content) }
                        .scrollIndicators(.automatic)
                        .frame(height: most)
                } else {
                    body(content)
                }
            }
        }
        .frame(width: MapMetrics.column, alignment: .leading)
        .mapPanel(radius: Memnox.Console.cardRadius)
    }

    private func body(_ content: Content) -> some View {
        content
            .padding(.horizontal, Memnox.Spacing.large)
            .padding(.vertical, Memnox.Spacing.regular)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One row a panel can take off the drawing, counted, because hiding a kind is a decision about the picture.
private struct MapToggle<ID: Hashable>: Identifiable {
    let id: ID
    let label: String
    let count: Int
}

/// What is on the drawing and what has been taken off it, each row a tick box, and one press for the lot.
private struct MapGroup<ID: Hashable, Mark: View>: View {
    let rows: [MapToggle<ID>]
    @Binding var hidden: Set<ID>
    @ViewBuilder let mark: (ID) -> Mark

    var body: some View {
        let all = hidden.isEmpty
        VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
            ForEach(rows) { row in
                let on = !hidden.contains(row.id)
                Button {
                    if on { hidden.insert(row.id) } else { hidden.remove(row.id) }
                } label: {
                    HStack(spacing: Memnox.Spacing.regular) {
                        MapBox(on: on)
                        mark(row.id).accessibilityHidden(true)
                        Text(row.label)
                            .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
                            .foregroundStyle(on ? Memnox.Console.foreground : Memnox.Console.muted)
                            .lineLimit(1)
                        Spacer(minLength: Memnox.Spacing.small)
                        Text("\(row.count)")
                            .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall).monospacedDigit())
                            .foregroundStyle(Memnox.Console.muted)
                    }
                    .padding(.vertical, Memnox.Spacing.xSmall)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHand()
                .accessibilityLabel("\(row.label), \(row.count)")
                .accessibilityValue(on ? "Shown" : "Hidden")
            }
            Button(all ? "Hide all" : "Show all") { hidden = all ? Set(rows.map(\.id)) : [] }
                .buttonStyle(.plain)
                .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                .foregroundStyle(Memnox.Console.muted)
                .pointingHand()
                .padding(.top, Memnox.Spacing.xSmall)
        }
    }
}

/// A tick box drawn rather than native, so it wears the console's own blue.
private struct MapBox: View {
    let on: Bool

    private static let side: CGFloat = 14
    private static let radius: CGFloat = 4
    private static let tick: CGFloat = 8

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        ZStack {
            shape.fill(on ? Memnox.Console.primary : Memnox.Console.background)
            shape.strokeBorder(on ? Memnox.Console.primary : Memnox.Console.border, lineWidth: Memnox.Stroke.hairline)
            if on {
                Image(systemName: "checkmark")
                    .font(.system(size: Self.tick, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: Self.side, height: Self.side)
        .accessibilityHidden(true)
    }
}

/// A short stretch of line drawn the way the graph draws one kind, so a key reads like the drawing.
private struct MapLegendSample: View {
    let dash: [CGFloat]

    static let width: CGFloat = 22
    private static let line: CGFloat = 2

    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: Self.line / 2, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width - Self.line / 2, y: size.height / 2))
            context.stroke(path, with: .color(MapInk.stroke), style: StrokeStyle(lineWidth: Self.line, lineCap: .round, dash: dash))
        }
        .frame(width: Self.width, height: Memnox.Spacing.medium)
        .accessibilityHidden(true)
    }
}

