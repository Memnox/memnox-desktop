import AppKit
import MetalKit
import MemnoxVoiceCore
import SwiftUI

/// The scan, on the whole screen: Memnox in the middle, a sweep going round, and each agent on
/// this Mac found in turn and set in a ring with its own logo, a line back to the middle, what it
/// reaches and what it is doing now. A click or Escape closes it, and it goes on its own after a while.
@MainActor
final class ScanPanel {
    private let panel: KeyablePanel
    private var hide: Task<Void, Never>?
    private var escape: Any?
    private let model = ScanModel()
    /// Long enough to hear it said and look at every agent, never a screen that stays up on its own.
    private static let showFor: UInt64 = 25

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
        if let escape { NSEvent.removeMonitor(escape) }
        escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // 53 is Escape, which closes it the way it closes any full screen view.
            if event.keyCode == 53 { self?.dismiss(); return nil }
            return event
        }
        hide?.cancel()
        hide = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.showFor * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        hide?.cancel()
        if let escape { NSEvent.removeMonitor(escape) }
        escape = nil
        withAnimation(.easeIn(duration: 0.35)) { model.phase = .leaving }
        Task { [panel] in
            try? await Task.sleep(nanoseconds: 400_000_000)
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
    static let perAgent = 0.32
    static let warmUp = 0.7

    func begin() {
        revealed = 0
        withAnimation(.easeOut(duration: 0.5)) { phase = .scanning }
        finding?.cancel()
        finding = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.warmUp * 1_000_000_000))
            guard let self else { return }
            for index in self.agents.indices {
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) { self.revealed = index + 1 }
                try? await Task.sleep(nanoseconds: UInt64(Self.perAgent * 1_000_000_000))
            }
            withAnimation(.easeOut(duration: 0.6)) { self.phase = .found }
        }
    }
}

struct ScanView: View {
    @ObservedObject var model: ScanModel
    let close: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let center = CGPoint(x: size.width / 2, y: size.height / 2 + 10)
            let ring = ScanLayout.ring(in: size)
            ZStack {
                ScanBackdrop(phase: model.phase)
                ScanGrid().opacity(model.phase == .hidden ? 0 : 0.45)
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
                    .position(x: center.x, y: max(90, center.y - ring.height - 160))
                ScanSummary(agents: model.agents, phase: model.phase)
                    .position(x: center.x, y: size.height - 70)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: close)
        }
        .opacity(model.phase == .leaving || model.phase == .hidden ? 0 : 1)
        .scaleEffect(model.phase == .leaving ? 1.03 : 1)
        .blur(radius: model.phase == .leaving ? 6 : 0)
        .ignoresSafeArea()
    }
}

/// Where each agent sits: evenly round an ellipse wider than it is tall, starting at the top, so
/// the ring fills a wide screen rather than leaving its sides empty.
enum ScanLayout {
    static func ring(in size: CGSize) -> CGSize {
        CGSize(width: min(size.width * 0.34, 560), height: min(size.height * 0.29, 320))
    }

    static func point(_ index: Int, of count: Int, around center: CGPoint, ring: CGSize) -> CGPoint {
        let step = 2 * Double.pi / Double(max(count, 1))
        let angle = -Double.pi / 2 + step * Double(index)
        return CGPoint(x: center.x + ring.width * cos(angle), y: center.y + ring.height * sin(angle))
    }
}

/// Black like the island, lit faintly blue from the middle, over a blur of whatever is behind.
private struct ScanBackdrop: View {
    let phase: ScanModel.Phase

    var body: some View {
        ZStack {
            Glass(material: .fullScreenUI, cornerRadius: 0)
            Color.black.opacity(0.9)
            RadialGradient(
                colors: [Memnox.Palette.primary.opacity(phase == .scanning ? 0.22 : 0.14), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 700
            )
            .animation(.easeInOut(duration: 0.8), value: phase)
        }
        .opacity(phase == .hidden ? 0 : 1)
    }
}

/// A faint field of dots, so the screen reads as an instrument rather than a dark sheet.
private struct ScanGrid: View {
    var body: some View {
        Canvas { context, size in
            let gap: CGFloat = 34
            var y: CGFloat = gap / 2
            while y < size.height {
                var x: CGFloat = gap / 2
                while x < size.width {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.4, height: 1.4)), with: .color(.white.opacity(0.08)))
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

    var body: some View {
        let line = Path { path in
            path.move(to: from)
            path.addLine(to: to)
        }
        ZStack {
            line
                .trim(from: 0, to: shown ? 1 : 0)
                .stroke(
                    LinearGradient(
                        colors: [Memnox.Palette.primary.opacity(0.5), colour.opacity(0.55)],
                        startPoint: UnitPoint(x: from.x > to.x ? 1 : 0, y: from.y > to.y ? 1 : 0),
                        endPoint: UnitPoint(x: from.x > to.x ? 0 : 1, y: from.y > to.y ? 0 : 1)
                    ),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [2, 5])
                )
                .animation(.easeOut(duration: 0.55), value: shown)
            if live && shown {
                TimelineView(.animation) { timeline in
                    let travel = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                    Circle()
                        .fill(colour)
                        .frame(width: 6, height: 6)
                        .shadow(color: colour, radius: 8)
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

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3, id: \.self) { wave in
                    let progress = ((time + Double(wave) * 0.8).truncatingRemainder(dividingBy: 2.4)) / 2.4
                    Circle()
                        .stroke(Memnox.Palette.primary.opacity((1 - progress) * (phase == .scanning ? 0.45 : 0.12)), lineWidth: 1)
                        .frame(width: Self.size * (0.8 + progress * 1.6), height: Self.size * (0.8 + progress * 1.6))
                }
                RadialGradient(colors: [Memnox.Palette.primary.opacity(0.3), .clear], center: .center, startRadius: 0, endRadius: Self.size * 0.8)
                    .frame(width: Self.size * 1.6, height: Self.size * 1.6)
                ScanOrb(state: phase == .scanning ? .thinking : .idle)
                    .frame(width: Self.size / 0.62, height: Self.size / 0.62)
            }
        }
        .scaleEffect(phase == .hidden ? 0.5 : 1)
        .animation(.spring(response: 0.7, dampingFraction: 0.72), value: phase)
        .allowsHitTesting(false)
    }
}

/// A Metal orb of its own for the scan, drawn by the same renderer as the island's.
private struct ScanOrb: NSViewRepresentable {
    let state: VoiceState

    final class Coordinator {
        var renderer: OrbRenderer?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.preferredFramesPerSecond = 60
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

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(phase == .found ? IslandPalette.green : Memnox.Palette.sky)
                    .frame(width: 7, height: 7)
                Text(phase == .found ? "Scan complete" : "Scanning this Mac")
                    .font(Memnox.sans(12, .semibold))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.07)))
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(found)")
                    .font(Memnox.display(58))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(value: Double(found)))
                Text(total == 1 ? "agent on this Mac" : "agents on this Mac")
                    .font(Memnox.display(28))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .opacity(phase == .hidden ? 0 : 1)
        .offset(y: phase == .hidden ? -12 : 0)
        .animation(.easeOut(duration: 0.5), value: phase)
        .animation(.snappy, value: found)
        .allowsHitTesting(false)
    }
}

/// One agent as a card in its own colour: its logo, what it reaches, what it is connected to, and what it is doing now.
private struct AgentCard: View {
    let agent: AgentNode
    let shown: Bool

    var body: some View {
        let colour = IslandPalette.color(agent.kind)
        IslandCard(veil: status == nil ? colour.opacity(0.22) : statusColour.opacity(0.38)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    AgentLogo(kind: agent.kind, name: agent.name)
                        .frame(width: 20, height: 20)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(colour))
                        .shadow(color: colour.opacity(0.6), radius: 10)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(agent.name)
                            .font(Memnox.sans(15, .semibold))
                            .foregroundStyle(.white)
                        Text(reach)
                            .font(Memnox.sans(11))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                ForEach(connections, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                if let status {
                    HStack(spacing: 6) {
                        Circle().fill(statusColour).frame(width: 6, height: 6)
                        Text(status).font(Memnox.sans(11, .medium))
                    }
                    .foregroundStyle(statusColour)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(statusColour.opacity(0.14)))
                }
            }
            .padding(14)
            .frame(width: 230, alignment: .leading)
        }
        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
        .scaleEffect(shown ? 1 : 0.2)
        .opacity(shown ? 1 : 0)
        .blur(radius: shown ? 0 : 10)
        .allowsHitTesting(false)
    }

    /// Counted facts only: its MCP servers and the kinds of thing it can touch.
    private var reach: String {
        let servers = agent.servers == 0 ? [] : ["\(agent.servers) MCP \(agent.servers == 1 ? "server" : "servers")"]
        let words = agent.reaches.prefix(3).map { Self.spoken[$0] ?? $0 }
        let parts = servers + words
        return parts.isEmpty ? "nothing beyond its own app" : parts.joined(separator: " \u{00B7} ")
    }

    /// What it is connected to by name: its MCP servers with their tools, then the CLIs signed in for its shell.
    private var connections: [String] {
        let servers = (agent.mcp ?? []).map { server -> String in
            guard let tools = server.tools else { return server.name }
            return "\(server.name) \(tools)"
        }
        var lines: [String] = []
        if !servers.isEmpty { lines.append("mcp  " + Self.listed(servers, most: 3)) }
        if let clis = agent.clis, !clis.isEmpty { lines.append("cli  " + Self.listed(clis, most: 4)) }
        return lines
    }

    /// A few by name and the rest as a count, so one card never grows wider than the ring allows.
    private static func listed(_ names: [String], most: Int) -> String {
        let shown = names.prefix(most).joined(separator: " \u{00B7} ")
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

    var body: some View {
        let done = phase == .found
        HStack(spacing: 22) {
            figure(agents.count, "agents")
            figure(agents.reduce(0) { $0 + ($1.mcp ?? []).reduce(0) { $0 + ($1.tools ?? 0) } }, "MCP tools")
            figure(agents.reduce(0) { $0 + ($1.mcp ?? []).reduce(0) { $0 + ($1.changing ?? 0) } }, "can change things", tint: IslandPalette.amber)
            figure(agents.reduce(0) { $0 + $1.working }, "working", tint: IslandPalette.green)
            Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1, height: 22)
            HStack(spacing: 6) {
                Keycap(label: "esc")
                Text("or click to close").font(Memnox.sans(11)).foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(Capsule().fill(Color.black))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.6), radius: 24, y: 10)
        .opacity(done ? 1 : 0)
        .offset(y: done ? 0 : 24)
        .animation(.spring(response: 0.5, dampingFraction: 0.72), value: done)
        .allowsHitTesting(false)
    }

    private func figure(_ value: Int, _ label: String, tint: Color = .white) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(phase == .found ? value : 0)")
                .font(Memnox.sans(17, .semibold))
                .foregroundStyle(tint)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(phase == .found ? value : 0)))
                .animation(.easeOut(duration: 0.9).delay(0.2), value: phase)
            Text(label).font(Memnox.sans(12)).foregroundStyle(.white.opacity(0.55))
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
                .font(Memnox.display(26))
                .foregroundStyle(Color(hex: 0x0B1A2E))
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

    @MainActor
    static func image(for kind: String) -> NSImage? {
        guard let file = files[kind] else { return nil }
        if let kept = cache[file] { return kept }
        let parts = file.split(separator: ".")
        guard parts.count == 2,
              let url = Bundle.main.url(forResource: String(parts[0]), withExtension: String(parts[1]), subdirectory: "AgentLogos"),
              let image = NSImage(contentsOf: url)
        else { return nil }
        cache[file] = image
        return image
    }
}
