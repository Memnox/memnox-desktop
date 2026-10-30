import MemnoxVoiceCore
import SwiftUI

/// The memory listed above, drawn as a map: each fact beside the document its evidence cites, each document in its
/// source, and each rule a fact governs. Every line is a field on a record. Picking a node opens it in the details; the
/// drawing pans, zooms, fits and is walked from the keyboard, as the console's surface is.
struct MemoryMapView: View {
    let items: [MemoryItemView]
    let sources: [MemorySourceView]
    /// The node whose details are open: a fact's id, or a document's or a source's node id.
    let selected: String?
    let select: (MemoryMapNode?) -> Void

    @StateObject private var world = SurfaceWorld()
    @State private var camera = SurfaceCamera.atRest
    @State private var nodeSize = 1.0
    @State private var over: String?
    /// Somebody has taken the camera, so it stops following the fit.
    @State private var own = false
    @State private var pan: (camera: SurfaceCamera, moved: Bool)?
    @State private var grab: Grab?
    @State private var pinch: SurfaceCamera?
    @State private var stage = CGSize.zero
    @FocusState private var focused: Bool

    private struct Grab {
        let id: String
        let along: [(id: String, dx: Double, dy: Double)]
        let dx: Double
        let dy: Double
        let from: (x: Double, y: Double)
        var moved: Bool
    }

    var body: some View {
        let map = MemoryMaps.map(items, sources: sources, kindLabel: MemoryLines.sourceKindLabel)
        let placed = placedNodes(map)
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ground(geometry.size)
                MapLines(edges: map.edges, placed: placed, camera: camera, size: geometry.size, nodeSize: nodeSize, focus: focus)
                    .allowsHitTesting(false)
                ForEach(placed, id: \.id) { node in
                    mark(node, map: map, placed: placed, size: geometry.size)
                }
                MapControls(camera: camera, nodeSize: $nodeSize, fit: { fit(placed, geometry.size) },
                            arrange: { own = false; world.reseed() },
                            zoom: { zoom(by: $0, size: geometry.size) })
                    .padding(MapMetrics.inset)
                MapLegend()
                    .padding(MapMetrics.inset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .coordinateSpace(.named(MapMetrics.space))
            .onAppear { stage = geometry.size }
            .onChange(of: geometry.size) { _, now in stage = now }
        }
        .frame(height: MapMetrics.height)
        .background(stageFill)
        .clipShape(RoundedRectangle(cornerRadius: Memnox.Console.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Memnox.Console.cardRadius, style: .continuous)
            .strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress { press in keys(press, map: map, placed: placed) }
        .simultaneousGesture(MagnifyGesture()
            .onChanged { value in
                let base = pinch ?? camera
                pinch = base
                own = true
                camera = base.zoomed(by: value.magnification, at: (stage.width / 2, stage.height / 2), size: (stage.width, stage.height))
            }
            .onEnded { _ in pinch = nil })
        .onAppear { sync(map) }
        .onChange(of: map) { _, now in sync(now) }
        .onChange(of: nodeSize) { _, _ in sync(map) }
        .onReceive(world.$bodies) { _ in follow(map) }
        .onDisappear { world.stop() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Memory map")
    }

    /// A pool of light under the middle, so the surface has a near edge and a far one.
    private var stageFill: some View {
        ZStack {
            Memnox.Console.card
            RadialGradient(colors: [Memnox.Console.primary.opacity(MapMetrics.glow), .clear], center: UnitPoint(x: 0.5, y: 0.42),
                           startRadius: 0, endRadius: MapMetrics.glowRadius)
        }
    }

    private var focus: String? { selected ?? over }

    private func placedNodes(_ map: MemoryMap) -> [MemoryMapNode] {
        map.nodes.map { node in
            guard let spot = world.spot(node.id) else { return node }
            var moved = node
            moved.place.x = spot.x
            moved.place.y = spot.y
            return moved
        }
    }

    private func sync(_ map: MemoryMap) {
        world.sync(map.nodes.map(\.place), links: map.edges.map { SurfaceLink(from: $0.from, to: $0.to) }, sized: nodeSize)
    }

    /// Keeps the drawing fitted while it settles, until somebody takes the camera or picks a node.
    private func follow(_ map: MemoryMap) {
        guard !own, selected == nil, stage.width > 0 else { return }
        let want = SurfaceCamera.fitted(placedNodes(map).map(\.place), size: (stage.width, stage.height), sized: nodeSize, inset: MapMetrics.panel)
        let there = abs(want.x - camera.x) < MapMetrics.settledPan && abs(want.y - camera.y) < MapMetrics.settledPan
            && abs(want.k - camera.k) < MapMetrics.settledZoom
        if !there { camera = want }
    }

    private func fit(_ placed: [MemoryMapNode], _ size: CGSize) {
        own = false
        camera = SurfaceCamera.fitted(placed.map(\.place), size: (size.width, size.height), sized: nodeSize, inset: MapMetrics.panel)
    }

    private func zoom(by factor: Double, size: CGSize) {
        own = true
        camera = camera.zoomed(by: factor, at: (size.width / 2, size.height / 2), size: (size.width, size.height))
    }

    /// The ground: dragged, it pans; clicked, it puts the details away, and panning across it does not.
    private func ground(_ size: CGSize) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let start = pan ?? (camera, false)
                    let moved = start.moved || hypot(drag.translation.width, drag.translation.height) > MapMetrics.aClick
                    pan = (start.camera, moved)
                    if moved { own = true }
                    camera = SurfaceCamera(x: start.camera.x - drag.translation.width / start.camera.k,
                                           y: start.camera.y - drag.translation.height / start.camera.k, k: start.camera.k)
                }
                .onEnded { _ in
                    if pan?.moved != true { select(nil) }
                    pan = nil
                    focused = true
                })
    }

    private func mark(_ node: MemoryMapNode, map: MemoryMap, placed: [MemoryMapNode], size: CGSize) -> some View {
        let screen = camera.onScreen((node.place.x, node.place.y), size: (size.width, size.height))
        let picked = selected == node.id
        let joined = focus == nil || focus == node.id
            || map.edges.contains { ($0.from == focus && $0.to == node.id) || ($0.to == focus && $0.from == node.id) }
        // Hover and the drag sit on the mark itself, before it is positioned, since a positioned view fills the stage.
        return MapMark(node: node, selected: picked, keyed: focused && over == node.id, showName: camera.k >= MapMetrics.namesFrom)
            .scaleEffect(SurfaceGeometry.scaleOf(node.place.depth) * nodeSize * camera.k)
            .opacity(joined ? 1 : MapMetrics.faded)
            .onHover { inside in over = inside ? node.id : (over == node.id ? nil : over) }
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(MapMetrics.space))
                .onChanged { drag in hold(node, drag: drag, map: map, placed: placed) }
                .onEnded { _ in drop(node) })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(node.label)
            .accessibilityAddTraits(picked ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { select(node) }
            .position(x: screen.x, y: screen.y)
            .zIndex(node.place.depth * MapMetrics.depthLayers + (picked ? MapMetrics.selectedLift : 0))
    }

    /// Picks a node up and carries it, and a document carries the facts that cite it, or the cluster tears in half.
    private func hold(_ node: MemoryMapNode, drag: DragGesture.Value, map: MemoryMap, placed: [MemoryMapNode]) {
        let by = (x: drag.translation.width / camera.k, y: drag.translation.height / camera.k)
        if grab == nil {
            let along = MemoryMaps.carriedWith(map, node.id).compactMap { id -> (id: String, dx: Double, dy: Double)? in
                guard let other = placed.first(where: { $0.id == id }) else { return nil }
                return (id, other.place.x - node.place.x, other.place.y - node.place.y)
            }
            grab = Grab(id: node.id, along: along, dx: 0, dy: 0, from: (node.place.x, node.place.y), moved: false)
        }
        guard var held = grab else { return }
        // A hand that trembles while clicking is not a drag, and must not stir the map.
        if !held.moved, hypot(drag.translation.width, drag.translation.height) <= MapMetrics.aClick { return }
        held.moved = true
        grab = held
        world.pinned = node.id
        own = true
        let x = held.from.x + by.x
        let y = held.from.y + by.y
        world.put(node.id, x: x, y: y)
        for each in held.along { world.put(each.id, x: x + each.dx, y: y + each.dy) }
    }

    /// Lets a node go; a press that never moved is a choice, and a drag is not.
    private func drop(_ node: MemoryMapNode) {
        let moved = grab?.moved == true
        grab = nil
        world.pinned = nil
        world.stir(SurfaceSettling.heatStirred)
        if !moved { select(node) }
        focused = true
    }

    /// Arrows walk the nodes in the drawing's own order, Return opens the one walked to, plus and minus zoom, and zero
    /// fits it again.
    private func keys(_ press: KeyPress, map: MemoryMap, placed: [MemoryMapNode]) -> KeyPress.Result {
        let middle = (x: Double(stage.width / 2), y: Double(stage.height / 2))
        switch press.characters {
        case "+", "=":
            own = true
            camera = camera.zoomed(by: MapMetrics.pressZoom, at: middle, size: (stage.width, stage.height))
            return .handled
        case "-":
            own = true
            camera = camera.zoomed(by: 1 / MapMetrics.pressZoom, at: middle, size: (stage.width, stage.height))
            return .handled
        case "0":
            fit(placed, stage)
            return .handled
        default:
            break
        }
        if press.key == .return, let over, let node = map.nodes.first(where: { $0.id == over }) {
            select(node)
            return .handled
        }
        let step: Int
        switch press.key {
        case .rightArrow, .downArrow: step = 1
        case .leftArrow, .upArrow: step = -1
        default: return .ignored
        }
        let order = MemoryMaps.walkOrder(map)
        guard !order.isEmpty else { return .ignored }
        let here = order.firstIndex(of: focus ?? "") ?? (step > 0 ? -1 : 0)
        over = order[(here + step + order.count) % order.count]
        return .handled
    }
}

enum MapMetrics {
    static let space = "memory-map"
    static let height: CGFloat = 560
    static let inset: CGFloat = 12
    /// The column the controls float in, which the drawing is fitted beside.
    static let panel = 220.0
    /// How far the pointer may travel before a press stops being a click.
    static let aClick = 4.0
    static let pressZoom = 1.2
    static let sizeStep = 0.1
    /// Past this far out a name is a smear, so it is not drawn at all.
    static let namesFrom = 0.45
    static let faded = 0.3
    static let unlitShare = 0.25
    static let depthLayers = 100.0
    static let selectedLift = 200.0
    static let settledPan = 0.5
    static let settledZoom = 0.002
    static let glow = 0.07
    static let glowRadius: CGFloat = 420
    static let shadow = 0.1
    static let shadowRadius: CGFloat = 12
    static let shadowDrop: CGFloat = 8
}

/// The lines of the map, each a field on the record, drawn under the marks and stopped at their edges.
private struct MapLines: View {
    let edges: [MemoryMapEdge]
    let placed: [MemoryMapNode]
    let camera: SurfaceCamera
    let size: CGSize
    let nodeSize: Double
    let focus: String?

    private static let arrowLength = 7.0
    private static let arrowHalf = 2.8

    var body: some View {
        Canvas { context, _ in
            var at: [String: Placed] = [:]
            for node in placed { at[node.id] = node.place }
            for edge in edges {
                guard let from = at[edge.from], let to = at[edge.to],
                      let line = SurfaceGeometry.between(from, to, sized: nodeSize) else { continue }
                draw(edge, line: line, in: &context)
            }
        }
    }

    private func draw(_ edge: MemoryMapEdge, line: SurfaceLine, in context: inout GraphicsContext) {
        let lit = focus == edge.from || focus == edge.to
        let ink = MapInk.of(edge.kind)
        // Kept faint rather than removed: the lines that are not the answer say how much else there is.
        let opacity = (lit ? 1 : MapInk.restingOpacity) * (focus != nil && !lit ? MapMetrics.unlitShare : 1)
        let start = camera.onScreen((line.x1, line.y1), size: (size.width, size.height))
        let end = camera.onScreen((line.x2, line.y2), size: (size.width, size.height))
        var path = Path()
        path.move(to: CGPoint(x: start.x, y: start.y))
        path.addLine(to: CGPoint(x: end.x, y: end.y))
        let dash = (edge.stale ? MapInk.staleDash : ink.dash).map { $0 * CGFloat(camera.k) }
        let width = (lit ? MapInk.litWidth : MapInk.width) * camera.k
        context.stroke(path, with: .color(ink.stroke.opacity(opacity)), style: StrokeStyle(lineWidth: width, lineCap: .round, dash: dash))
        guard edge.kind != .heldIn else { return }
        let turn = atan2(end.y - start.y, end.x - start.x)
        var head = Path()
        head.move(to: .zero)
        head.addLine(to: CGPoint(x: -Self.arrowLength, y: Self.arrowHalf))
        head.addLine(to: CGPoint(x: -Self.arrowLength, y: -Self.arrowHalf))
        head.closeSubpath()
        let place = CGAffineTransform(translationX: end.x, y: end.y).rotated(by: turn).scaledBy(x: camera.k, y: camera.k)
        context.fill(head.applying(place), with: .color(ink.stroke.opacity(opacity)))
    }
}

/// A line's colour, its dash and the words for it, as the console's legend says them.
struct MapInk {
    let label: String
    let meaning: String
    let stroke: Color
    let dash: [CGFloat]

    static let width = 1.5
    static let litWidth = 2.0
    static let restingOpacity = 0.7
    /// A passage that changed since it was read is drawn broken, as the list strikes it through.
    static let staleDash: [CGFloat] = [2, 5]

    static func of(_ kind: MemoryLinkKind) -> MapInk {
        switch kind {
        case .cites: MapInk(label: "Cites", meaning: "Its evidence is a passage of this document", stroke: Memnox.Console.warm, dash: [])
        case .heldIn: MapInk(label: "Read from", meaning: "The document was read out of this source", stroke: Memnox.Console.muted, dash: [])
        case .governs: MapInk(label: "Governs", meaning: "Confirming it raises this rule", stroke: Memnox.Console.primary, dash: [])
        case .restates: MapInk(label: "Restates", meaning: "Says again what an earlier fact said", stroke: Memnox.Console.violet, dash: [5, 4])
        }
    }
}

/// Fit, Arrange again and the zoom, then the size of the marks, floating over the drawing's top corner.
private struct MapControls: View {
    let camera: SurfaceCamera
    @Binding var nodeSize: Double
    let fit: () -> Void
    let arrange: () -> Void
    let zoom: (Double) -> Void

    private static let percent = 100.0
    private static let zoomWidth: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            HStack(spacing: Memnox.Spacing.xxSmall) {
                MapButton(symbol: "arrow.up.left.and.arrow.down.right", label: "Fit the map", action: fit)
                MapButton(symbol: "arrow.counterclockwise", label: "Arrange again", action: arrange)
                Rectangle().fill(Memnox.Console.border).frame(width: Memnox.Stroke.hairline, height: Memnox.Spacing.xxLarge)
                    .padding(.horizontal, Memnox.Spacing.xxSmall)
                MapButton(symbol: "minus", label: "Zoom out", enabled: camera.k > SurfaceGeometry.zoomMin) { zoom(1 / MapMetrics.pressZoom) }
                Text("\(Int((camera.k * Self.percent).rounded()))%")
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.meta).monospacedDigit())
                    .foregroundStyle(Memnox.Console.muted)
                    .frame(width: Self.zoomWidth)
                    .accessibilityLabel("Zoom \(Int((camera.k * Self.percent).rounded())) percent")
                MapButton(symbol: "plus", label: "Zoom in", enabled: camera.k < SurfaceGeometry.zoomMax) { zoom(MapMetrics.pressZoom) }
            }
            .mapPanel()
            HStack(spacing: Memnox.Spacing.xxSmall) {
                Text("Size")
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                    .foregroundStyle(Memnox.Console.muted)
                    .padding(.horizontal, Memnox.Spacing.small)
                MapButton(symbol: "minus", label: "Smaller marks", enabled: nodeSize > SurfaceGeometry.nodeSizeMin) {
                    nodeSize = max(SurfaceGeometry.nodeSizeMin, ((nodeSize - MapMetrics.sizeStep) * 10).rounded() / 10)
                }
                MapButton(symbol: "plus", label: "Larger marks", enabled: nodeSize < SurfaceGeometry.nodeSizeMax) {
                    nodeSize = min(SurfaceGeometry.nodeSizeMax, ((nodeSize + MapMetrics.sizeStep) * 10).rounded() / 10)
                }
            }
            .mapPanel()
        }
    }
}

private struct MapButton: View {
    let symbol: String
    let label: String
    var enabled = true
    let action: () -> Void

    private static let side: CGFloat = 28
    private static let disabled = 0.35

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: Memnox.TextSize.footnote, weight: .medium))
                .foregroundStyle(Memnox.Console.muted)
                .frame(width: Self.side, height: Self.side)
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

private extension View {
    /// A small bordered card floating over the drawing, lifted a little off it.
    func mapPanel() -> some View {
        let shape = RoundedRectangle(cornerRadius: Memnox.Console.controlRadius, style: .continuous)
        return padding(Memnox.Spacing.xSmall)
            .background(Memnox.Console.card, in: shape)
            .overlay(shape.strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
            .shadow(color: .black.opacity(MapMetrics.shadow), radius: MapMetrics.shadowRadius, y: MapMetrics.shadowDrop)
    }
}

/// How to read the lines and the rails, folded so it never covers the drawing until asked.
private struct MapLegend: View {
    @State private var open = false

    private static let width: CGFloat = 260
    private static let sample: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            Button { withAnimation(.easeOut(duration: Memnox.Motion.quick)) { open.toggle() } } label: {
                Text("How to read the map".uppercased())
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.label, .medium))
                    .tracking(Memnox.Console.headingTracking * 0.8)
                    .foregroundStyle(Memnox.Console.muted)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHand()
            .accessibilityLabel("How to read the map")
            .accessibilityValue(open ? "Shown" : "Folded")
            if open {
                ForEach(MemoryLinkKind.allCases, id: \.self) { kind in
                    let ink = MapInk.of(kind)
                    row(stroke: ink.stroke, dash: ink.dash) {
                        Text(ink.label).foregroundStyle(Memnox.Console.foreground).fontWeight(.medium)
                            + Text(", \(ink.meaning.lowercased())").foregroundStyle(Memnox.Console.muted)
                    }
                }
                row(stroke: Memnox.Console.warm, dash: MapInk.staleDash) {
                    Text("Broken where the passage changed since it was read").foregroundStyle(Memnox.Console.muted)
                }
                Text("The rail down a fact is where it stands: green verified, amber waiting, red in conflict, grey no longer told to agents. A fact citing nothing stands alone.")
                    .foregroundStyle(Memnox.Console.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
        .padding(.horizontal, Memnox.Spacing.large)
        .padding(.vertical, Memnox.Spacing.medium)
        .frame(width: open ? Self.width : nil, alignment: .leading)
        .mapPanel()
    }

    private func row(stroke: Color, dash: [CGFloat], words: () -> Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Memnox.Spacing.medium) {
            Canvas { context, size in
                var path = Path()
                path.move(to: CGPoint(x: 1, y: size.height / 2))
                path.addLine(to: CGPoint(x: size.width - 1, y: size.height / 2))
                context.stroke(path, with: .color(stroke), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: dash))
            }
            .frame(width: Self.sample, height: Memnox.Spacing.medium)
            .accessibilityHidden(true)
            words().fixedSize(horizontal: false, vertical: true)
        }
    }
}
