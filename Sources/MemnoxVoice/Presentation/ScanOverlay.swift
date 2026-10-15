import AppKit
import MetalKit
import MemnoxVoiceCore
import SwiftUI

/// Converts the seconds the scan waits into the nanoseconds `Task.sleep` takes.
private let nanosecondsPerSecond: TimeInterval = 1_000_000_000

/// The scan, on the whole screen: Memnox in the middle, a sweep going round, and each agent on
/// this Mac found in turn and set in a ring with its own logo, a line back to the middle, what it
/// reaches and what it is doing now. A click or Escape closes it, and it goes on its own after a while.
@MainActor
final class ScanPanel {
    private let panel: KeyablePanel
    private var hide: Task<Void, Never>?
    private var escape: EventMonitor?
    private let model = ScanModel()
    /// Long enough to hear it said and look at every agent, never a screen that stays up on its own.
    private static let showFor: TimeInterval = 25
    /// The fade out, a touch quicker than the panel's removal so it is gone before the panel is.
    private static let fadeOut: TimeInterval = 0.35
    private static let removeAfter: TimeInterval = 0.4

    init() {
        panel = KeyablePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Dark in every look, because it is a veil of dark glass over the whole screen and a light one would whiten the desktop.
        panel.appearance = NSAppearance(named: .darkAqua)
        // Above every window, the way a presentation is, since this screen is the answer.
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
    }

    func present(_ agents: [AgentNode], title: String) {
        guard let screen = NSScreen.main else { return }
        model.agents = agents
        model.title = title
        model.phase = .hidden
        panel.setFrame(screen.frame, display: false)
        panel.contentView = FirstClickHosting(rootView: ScanView(model: model) { [weak self] in self?.dismiss() })
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.makeKey()
        model.begin()
        escape?.stop()
        escape = EventMonitor.local(.keyDown) { [weak self] event in
            // Escape closes it the way it closes any full screen view.
            if event.keyCode == KeyCode.escape { self?.dismiss(); return nil }
            return event
        }
        hide?.cancel()
        hide = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.showFor * nanosecondsPerSecond))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        hide?.cancel()
        escape?.stop()
        escape = nil
        withAnimation(.easeIn(duration: Self.fadeOut)) { model.phase = .leaving }
        Task { [panel] in
            try? await Task.sleep(nanoseconds: UInt64(Self.removeAfter * nanosecondsPerSecond))
            panel.orderOut(nil)
        }
    }
}

/// Where the scan is: the field comes up, the sweep finds the agents one by one, then it rests.
@MainActor
final class ScanModel: ObservableObject {
    enum Phase { case hidden, scanning, found, leaving }

    @Published var phase: Phase = .hidden
    @Published var agents: [AgentNode] = []
    @Published var title = "Your agents"
    /// How many agents the sweep has reached so far, so they appear as it passes them.
    @Published var revealed = 0
    private var finding: Task<Void, Never>?

    /// A beat per agent, quick enough that eight are found in about two seconds.
    private static let perAgent: TimeInterval = 0.32
    private static let warmUp: TimeInterval = 0.7
    /// Each agent springs into place with a little overshoot, so it reads as arriving.
    private static let revealResponse = 0.55
    private static let revealDamping = 0.78
    private static let settle: TimeInterval = 0.6

    func begin() {
        revealed = 0
        withAnimation(.easeOut(duration: Memnox.Motion.slow)) { phase = .scanning }
        finding?.cancel()
        finding = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.warmUp * nanosecondsPerSecond))
            guard let self else { return }
            for index in self.agents.indices {
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: Self.revealResponse, dampingFraction: Self.revealDamping)) { self.revealed = index + 1 }
                try? await Task.sleep(nanoseconds: UInt64(Self.perAgent * nanosecondsPerSecond))
            }
            withAnimation(.easeOut(duration: Self.settle)) { self.phase = .found }
        }
    }
}

struct ScanView: View {
    @ObservedObject var model: ScanModel
    let close: () -> Void

    private enum Layout {
        /// The ring sits a little below the true middle, leaving room for the heading above it.
        static let centreDrop: CGFloat = 10
        static let gridOpacity = 0.45
        /// The heading never rides higher than this from the top of the screen.
        static let headingTop: CGFloat = 90
        static let headingAboveRing: CGFloat = 160
        static let summaryFromBottom: CGFloat = 70
        /// Leaving, the whole field swells and softens as it fades.
        static let leavingScale: CGFloat = 1.03
        static let leavingBlur: CGFloat = 6
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let center = CGPoint(x: size.width / 2, y: size.height / 2 + Layout.centreDrop)
            let ring = ScanLayout.ring(in: size)
            ZStack {
                ScanBackdrop(phase: model.phase)
                ScanGrid().opacity(model.phase == .hidden ? 0 : Layout.gridOpacity)
                ForEach(Array(model.agents.enumerated()), id: \.element.id) { index, agent in
                    let point = ScanLayout.point(index, of: model.agents.count, around: center, ring: ring)
                    ScanLink(from: center, to: point, colour: IslandPalette.color(agent.kind), shown: index < model.revealed, live: agent.working > 0)
                }
                ScanCore(phase: model.phase)
                    .position(center)
                ForEach(Array(model.agents.enumerated()), id: \.element.id) { index, agent in
                    let point = ScanLayout.point(index, of: model.agents.count, around: center, ring: ring)
                    let shown = index < model.revealed
                    // Each agent springs out of the orb to its place, so it reads as found by it.
                    AgentCard(agent: agent, shown: shown)
                        .position(shown ? point : center)
                }
                ScanHeading(found: model.revealed, total: model.agents.count, phase: model.phase)
                    .position(x: center.x, y: max(Layout.headingTop, center.y - ring.height - Layout.headingAboveRing))
                ScanSummary(agents: model.agents, phase: model.phase)
                    .position(x: center.x, y: size.height - Layout.summaryFromBottom)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: close)
        }
        .opacity(model.phase == .leaving || model.phase == .hidden ? 0 : 1)
        .scaleEffect(model.phase == .leaving ? Layout.leavingScale : 1)
        .blur(radius: model.phase == .leaving ? Layout.leavingBlur : 0)
        .ignoresSafeArea()
    }
}

/// Where each agent sits: evenly round an ellipse wider than it is tall, starting at the top, so
/// the ring fills a wide screen rather than leaving its sides empty.
enum ScanLayout {
    /// The ring's radii as a share of the screen, capped so a very large display does not scatter the cards.
    private enum Ring {
        static let widthShare: CGFloat = 0.34
        static let maxWidth: CGFloat = 560
        static let heightShare: CGFloat = 0.29
        static let maxHeight: CGFloat = 320
    }

    static func ring(in size: CGSize) -> CGSize {
        CGSize(width: min(size.width * Ring.widthShare, Ring.maxWidth), height: min(size.height * Ring.heightShare, Ring.maxHeight))
    }

    static func point(_ index: Int, of count: Int, around center: CGPoint, ring: CGSize) -> CGPoint {
        let step = 2 * Double.pi / Double(max(count, 1))
        let angle = -Double.pi / 2 + step * Double(index)
        return CGPoint(x: center.x + ring.width * cos(angle), y: center.y + ring.height * sin(angle))
    }
}

/// Flat black like the island over a blur of whatever is behind, dark enough that every card and figure reads on it.
private struct ScanBackdrop: View {
    let phase: ScanModel.Phase

    private enum Layout {
        static let dim = 0.9
    }

    var body: some View {
        ZStack {
            Glass(material: .fullScreenUI, cornerRadius: 0)
            Color.black.opacity(Layout.dim)
        }
        .opacity(phase == .hidden ? 0 : 1)
    }
}

/// A faint field of dots, so the screen reads as an instrument rather than a dark sheet.
private struct ScanGrid: View {
    private static let gap: CGFloat = 34
    private static let dot: CGFloat = 1.4

    var body: some View {
        Canvas { context, size in
            let gap = Self.gap
            var y: CGFloat = gap / 2
            while y < size.height {
                var x: CGFloat = gap / 2
                while x < size.width {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: Self.dot, height: Self.dot)), with: .color(.white.opacity(Memnox.Ink.fill)))
                    x += gap
                }
                y += gap
            }
        }
        .allowsHitTesting(false)
    }
}

/// The line from the orb to an agent in that agent's colour: drawn out as the agent is found, and
/// with a light running along it while that agent has a session working.
private struct ScanLink: View {
    let from: CGPoint
    let to: CGPoint
    let colour: Color
    let shown: Bool
    let live: Bool

    private enum Layout {
        static let lineOpacity = 0.55
        static let lineWidth: CGFloat = 1.2
        /// A dotted line, so it reads as a reach rather than a wire.
        static let dash: [CGFloat] = [2, 5]
        static let drawOut: TimeInterval = 0.55
        /// How long the light takes to run the line once.
        static let lap: TimeInterval = 1.6
        static let light: CGFloat = 6
        static let lightGlow: CGFloat = 8
    }

    var body: some View {
        let line = Path { path in
            path.move(to: from)
            path.addLine(to: to)
        }
        ZStack {
            line
                .trim(from: 0, to: shown ? 1 : 0)
                .stroke(
                    colour.opacity(Layout.lineOpacity),
                    style: StrokeStyle(lineWidth: Layout.lineWidth, lineCap: .round, dash: Layout.dash)
                )
                .animation(.easeOut(duration: Layout.drawOut), value: shown)
            if live && shown {
                TimelineView(.animation) { timeline in
                    let travel = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Layout.lap) / Layout.lap
                    Circle()
                        .fill(colour)
                        .frame(width: Layout.light, height: Layout.light)
                        .shadow(color: colour, radius: Layout.lightGlow)
                        .position(x: from.x + (to.x - from.x) * travel, y: from.y + (to.y - from.y) * travel)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Memnox in the middle: the same orb as the island, swirling while it looks and settling once it
/// has found them all, with a pulse going out from it as it scans.
private struct ScanCore: View {
    let phase: ScanModel.Phase
    private static let size: CGFloat = 200

    private enum Pulse {
        static let waves = 3
        /// Waves start this far apart in time, so three are always out at once over one lap.
        static let stagger: TimeInterval = 0.8
        static let lap: TimeInterval = 2.4
        /// A wave starts just inside the orb and grows by this much of its size as it goes out.
        static let startScale = 0.8
        static let growth = 1.6
        static let scanningOpacity = 0.45
        static let restingOpacity = 0.12
    }

    private enum Layout {
        /// The share of its canvas the orb fills, the same as the island's orb, so the two draw alike.
        static let orbFill: CGFloat = 0.62
        static let hiddenScale: CGFloat = 0.5
        static let arriveResponse = 0.7
        static let arriveDamping = 0.72
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<Pulse.waves, id: \.self) { wave in
                    let progress = ((time + Double(wave) * Pulse.stagger).truncatingRemainder(dividingBy: Pulse.lap)) / Pulse.lap
                    Circle()
                        .stroke(Memnox.Palette.primary.opacity((1 - progress) * (phase == .scanning ? Pulse.scanningOpacity : Pulse.restingOpacity)), lineWidth: Memnox.Stroke.hairline)
                        .frame(width: Self.size * (Pulse.startScale + progress * Pulse.growth), height: Self.size * (Pulse.startScale + progress * Pulse.growth))
                }
                ScanOrb(state: phase == .scanning ? .thinking : .idle)
                    .frame(width: Self.size / Layout.orbFill, height: Self.size / Layout.orbFill)
            }
        }
        .scaleEffect(phase == .hidden ? Layout.hiddenScale : 1)
        .animation(.spring(response: Layout.arriveResponse, dampingFraction: Layout.arriveDamping), value: phase)
        .allowsHitTesting(false)
    }
}

/// A Metal orb of its own for the scan, drawn by the same renderer as the island's.
private struct ScanOrb: NSViewRepresentable {
    let state: VoiceState
    private static let framesPerSecond = 60

    final class Coordinator {
        var renderer: OrbRenderer?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.preferredFramesPerSecond = Self.framesPerSecond
        view.wantsLayer = true
        view.layer?.isOpaque = false
        let renderer = OrbRenderer(view: view)
        view.delegate = renderer
        context.coordinator.renderer = renderer
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.renderer?.state = state
    }
}

/// The heading: what this is, and the count rolling up as the orb finds each agent.
private struct ScanHeading: View {
    let found: Int
    let total: Int
    let phase: ScanModel.Phase

    private enum Layout {
        static let dot: CGFloat = 7
        static let badgeTextOpacity = 0.7
        static let badgeFillOpacity = 0.07
        static let countSize: CGFloat = 58
        static let countLabelSize: CGFloat = 28
        static let countLabelOpacity = 0.8
        /// Hidden, it waits a little above its place and drops in as it appears.
        static let hiddenLift: CGFloat = -12
    }

    var body: some View {
        VStack(spacing: Memnox.Spacing.regular) {
            HStack(spacing: Memnox.Spacing.medium) {
                Circle()
                    .fill(phase == .found ? IslandPalette.green : Memnox.Palette.sky)
                    .frame(width: Layout.dot, height: Layout.dot)
                Text(phase == .found ? "Scan complete" : "Scanning this Mac")
                    .font(Memnox.sans(Memnox.TextSize.footnote, .semibold))
                    .foregroundStyle(Color.white.opacity(Layout.badgeTextOpacity))
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, Memnox.Spacing.large)
            .padding(.vertical, Memnox.Spacing.small)
            .background(Capsule().fill(Color.white.opacity(Layout.badgeFillOpacity)))
            HStack(alignment: .firstTextBaseline, spacing: Memnox.Spacing.large) {
                Text("\(found)")
                    .font(Memnox.display(Layout.countSize))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(value: Double(found)))
                Text(total == 1 ? "agent on this Mac" : "agents on this Mac")
                    .font(Memnox.display(Layout.countLabelSize))
                    .foregroundStyle(.white.opacity(Layout.countLabelOpacity))
            }
        }
        .opacity(phase == .hidden ? 0 : 1)
        .offset(y: phase == .hidden ? Layout.hiddenLift : 0)
        .animation(.easeOut(duration: Memnox.Motion.slow), value: phase)
        .animation(.snappy, value: found)
        .allowsHitTesting(false)
    }
}

/// One agent on the shared flat surface: its logo on a tile, what it reaches, what it is connected to, and what it is doing now.
private struct AgentCard: View {
    let agent: AgentNode
    let shown: Bool

    private enum Layout {
        /// An agent with work going takes its status colour on its edge, so a busy one is found first.
        static let statusEdgeOpacity = 0.6
        static let logo: CGFloat = 36
        static let titleSpacing: CGFloat = 1
        static let connectionOpacity = 0.7
        static let statusDot: CGFloat = 6
        static let statusPaddingX: CGFloat = 9
        static let statusPaddingY: CGFloat = 3
        static let statusFillOpacity = 0.14
        static let width: CGFloat = 230
        static let shadowOpacity = 0.5
        static let shadowRadius: CGFloat = 20
        static let shadowDrop: CGFloat = 10
        /// Unfound, it sits small and blurred inside the orb, so it grows out of it when found.
        static let hiddenScale: CGFloat = 0.2
        static let hiddenBlur: CGFloat = 10
        static let reachShown = 3
        static let serversShown = 3
        static let clisShown = 4
    }

    /// The dot between items in a line.
    private static let separator = " \u{00B7} "

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            HStack(spacing: Memnox.Spacing.regular) {
                BrandLogo(agent: agent.kind, name: agent.name, size: Layout.logo)
                VStack(alignment: .leading, spacing: Layout.titleSpacing) {
                    Text(agent.name)
                        .font(Memnox.sans(Memnox.TextSize.headline, .semibold))
                        .foregroundStyle(.white)
                    Text(reach)
                        .font(Memnox.sans(Memnox.TextSize.caption))
                        .foregroundStyle(.white.opacity(Memnox.Ink.secondary))
                        .lineLimit(1)
                }
            }
            ForEach(connections, id: \.self) { line in
                Text(line)
                    .font(.system(size: Memnox.TextSize.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(Layout.connectionOpacity))
                    .lineLimit(1)
            }
            if let status {
                HStack(spacing: Memnox.Spacing.small) {
                    Circle().fill(statusColour).frame(width: Layout.statusDot, height: Layout.statusDot)
                    Text(status).font(Memnox.sans(Memnox.TextSize.caption, .medium))
                }
                .foregroundStyle(statusColour)
                .padding(.horizontal, Layout.statusPaddingX)
                .padding(.vertical, Layout.statusPaddingY)
                .background(Capsule().fill(statusColour.opacity(Layout.statusFillOpacity)))
            }
        }
        .padding(SurfaceStyle.padding)
        .frame(width: Layout.width, alignment: .leading)
        .surface(accent: status == nil ? nil : statusColour.opacity(Layout.statusEdgeOpacity))
        .shadow(color: .black.opacity(Layout.shadowOpacity), radius: Layout.shadowRadius, y: Layout.shadowDrop)
        .scaleEffect(shown ? 1 : Layout.hiddenScale)
        .opacity(shown ? 1 : 0)
        .blur(radius: shown ? 0 : Layout.hiddenBlur)
        .allowsHitTesting(false)
    }

    /// Counted facts only: its MCP servers and the kinds of thing it can touch.
    private var reach: String {
        let servers = agent.servers == 0 ? [] : ["\(agent.servers) MCP \(agent.servers == 1 ? "server" : "servers")"]
        let words = agent.reaches.prefix(Layout.reachShown).map { Self.spoken[$0] ?? $0 }
        let parts = servers + words
        return parts.isEmpty ? "nothing beyond its own app" : parts.joined(separator: Self.separator)
    }

    /// What it is connected to by name: its MCP servers with their tools, then the CLIs signed in for its shell.
    private var connections: [String] {
        let servers = (agent.mcp ?? []).map { server -> String in
            guard let tools = server.tools else { return server.name }
            return "\(server.name) \(tools)"
        }
        var lines: [String] = []
        if !servers.isEmpty { lines.append("mcp  " + Self.listed(servers, most: Layout.serversShown)) }
        if let clis = agent.clis, !clis.isEmpty { lines.append("cli  " + Self.listed(clis, most: Layout.clisShown)) }
        return lines
    }

    /// A few by name and the rest as a count, so one card never grows wider than the ring allows.
    private static func listed(_ names: [String], most: Int) -> String {
        let shown = names.prefix(most).joined(separator: separator)
        return names.count > most ? "\(shown) +\(names.count - most)" : shown
    }

    private static let spoken = ["shell": "shell", "filesystem": "files", "git": "git", "network": "network", "browser": "browser", "cloud": "cloud", "docker": "docker"]

    private var status: String? {
        if agent.working > 0 { return agent.working == 1 ? "1 working" : "\(agent.working) working" }
        if agent.open > 0 { return agent.open == 1 ? "1 waiting on you" : "\(agent.open) waiting on you" }
        return nil
    }

    private var statusColour: Color {
        if agent.working > 0 { return IslandPalette.green }
        if agent.open > 0 { return IslandPalette.amber }
        return Memnox.Palette.primary
    }
}

/// The totals along the bottom in the island's own black pill, counting up once the scan is done.
private struct ScanSummary: View {
    let agents: [AgentNode]
    let phase: ScanModel.Phase

    private enum Layout {
        static let spacing: CGFloat = 22
        static let dividerOpacity = 0.1
        static let dividerHeight: CGFloat = 22
        static let paddingX: CGFloat = 22
        static let borderOpacity = 0.08
        static let shadowOpacity = 0.6
        static let shadowRadius: CGFloat = 24
        static let shadowDrop: CGFloat = 10
        /// Before the scan is done it waits below its place and rises in.
        static let hiddenDrop: CGFloat = 24
        static let riseResponse = 0.5
        static let riseDamping = 0.72
        /// The figures count up after the pill has started to rise, so the eye is on them.
        static let countUp: TimeInterval = 0.9
        static let countUpDelay: TimeInterval = 0.2
        static let labelOpacity = 0.55
    }

    var body: some View {
        let done = phase == .found
        HStack(spacing: Layout.spacing) {
            figure(agents.count, "agents")
            figure(agents.reduce(0) { $0 + ($1.mcp ?? []).reduce(0) { $0 + ($1.tools ?? 0) } }, "MCP tools")
            figure(agents.reduce(0) { $0 + ($1.mcp ?? []).reduce(0) { $0 + ($1.changing ?? 0) } }, "can change things", tint: IslandPalette.amber)
            figure(agents.reduce(0) { $0 + $1.working }, "working", tint: IslandPalette.green)
            Rectangle().fill(Color.white.opacity(Layout.dividerOpacity)).frame(width: Memnox.Stroke.hairline, height: Layout.dividerHeight)
            HStack(spacing: Memnox.Spacing.small) {
                Keycap(label: "esc")
                Text("or click to close").font(Memnox.sans(Memnox.TextSize.caption)).foregroundStyle(.white.opacity(Memnox.Ink.tertiary))
            }
        }
        .padding(.horizontal, Layout.paddingX)
        .padding(.vertical, Memnox.Spacing.large)
        .background(Capsule().fill(Color.black))
        .overlay(Capsule().strokeBorder(Color.white.opacity(Layout.borderOpacity), lineWidth: Memnox.Stroke.hairline))
        .shadow(color: .black.opacity(Layout.shadowOpacity), radius: Layout.shadowRadius, y: Layout.shadowDrop)
        .opacity(done ? 1 : 0)
        .offset(y: done ? 0 : Layout.hiddenDrop)
        .animation(.spring(response: Layout.riseResponse, dampingFraction: Layout.riseDamping), value: done)
        .allowsHitTesting(false)
    }

    private func figure(_ value: Int, _ label: String, tint: Color = .white) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Memnox.Spacing.small) {
            Text("\(phase == .found ? value : 0)")
                .font(Memnox.sans(Memnox.TextSize.title, .semibold))
                .foregroundStyle(tint)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(phase == .found ? value : 0)))
                .animation(.easeOut(duration: Layout.countUp).delay(Layout.countUpDelay), value: phase)
            Text(label).font(Memnox.sans(Memnox.TextSize.footnote)).foregroundStyle(.white.opacity(Layout.labelOpacity))
        }
    }
}

/// An agent's own logo, from the ones Memnox's site uses, or its first letter when there is none.
struct AgentLogo: View {
    let kind: String
    let name: String

    var body: some View {
        if let image = Self.image(for: kind) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            Text(String(name.prefix(1)).uppercased())
                .font(Memnox.display(Self.initialSize))
                .foregroundStyle(Self.initialInk)
        }
    }

    /// The product's logo by its kind; Codex is OpenAI's, and Claude Desktop shares Claude Code's.
    private static let files: [String: String] = [
        "claude-code": "claude.svg", "claude-desktop": "claude.svg", "claude": "claude.svg",
        "cursor": "cursor.svg",
        "codex": "openai.svg", "codex-cli": "openai.svg",
        "hermes": "hermes.webp", "openclaw": "openclaw.webp", "cline": "cline.webp",
        "antigravity": "antigravity.svg",
    ]

    private static var cache: [String: NSImage] = [:]
    private static let initialSize: CGFloat = 26
    /// A deep navy, so the initial reads on the light disc the notch draws behind a logo.
    private static let initialInk = Color(hex: 0x0B1A2E)
    /// The app bundle's folder of logos, copied in by the build script.
    private static let folder = "AgentLogos"
    /// Every logo file is a name and an extension, nothing more.
    private static let fileNameParts = 2

    @MainActor
    static func image(for kind: String) -> NSImage? {
        guard let file = files[kind] else { return nil }
        if let kept = cache[file] { return kept }
        let parts = file.split(separator: ".")
        guard parts.count == fileNameParts,
              let url = Bundle.main.url(forResource: String(parts[0]), withExtension: String(parts[1]), subdirectory: folder),
              let image = NSImage(contentsOf: url)
        else { return nil }
        cache[file] = image
        return image
    }
}
