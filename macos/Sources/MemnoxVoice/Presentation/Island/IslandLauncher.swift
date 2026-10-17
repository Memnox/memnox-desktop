import MemnoxVoiceCore
import SwiftUI

/// The notch's measures for tiles and the round buttons beside it, as Vorssaint draws its own notch.
enum NotchMetrics {
    static let tileHeight: CGFloat = 86
    static let tileWidth: CGFloat = 92
    static let tileSpacing: CGFloat = 8
    static let tileRadius: CGFloat = 16
    static let tileSymbol: CGFloat = 22
    static let tileSymbolFrame: CGFloat = 25
    static let tileTitle: CGFloat = 11
    static let tileCaption: CGFloat = 10
    static let tileLineSpacing: CGFloat = 6
    static let tileColumns = 5
    /// White over the black at rest, under the pointer, and the rim at rest and lit.
    static let tileFill = 0.045
    static let tileLitFill = 0.12
    static let tileRim = 0.04
    static let tileLitRim = 0.55
    static let captionInk = 0.6
    static let symbolInk = 0.85
    /// The round buttons beside the open island.
    static let satelliteDiameter: CGFloat = 44
    static let satelliteGap: CGFloat = 12
    static let satelliteStep: CGFloat = 54
    static let satelliteSymbol: CGFloat = 17
    static let satelliteRim = 0.16
    static let satelliteRimWidth: CGFloat = 0.75
    /// How far the satellites reach out from the island on each side, for the window and its clicks.
    static let satelliteReach: CGFloat = satelliteGap + satelliteDiameter
    /// The island's title, as the notch titles its pages, a step under Vorssaint's so it sits inside the notch row.
    static let titleSize: CGFloat = 15
}

/// Vorssaint's notch press: a light wash under the pointer, a small lift, and a give when pressed.
struct NotchPressStyle: ButtonStyle {
    var cornerRadius: CGFloat = NotchMetrics.tileRadius
    var lifts = true
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let hoverWash = 0.09
    private static let pressedOpacity = 0.8
    private static let disabledOpacity = 0.4
    private static let pressedScale: CGFloat = 0.965
    private static let hoverScale: CGFloat = 1.022

    func makeBody(configuration: Configuration) -> some View {
        let lit = enabled && hovered
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(lit ? Self.hoverWash : 0))
                    .allowsHitTesting(false)
            }
            .opacity(enabled ? (configuration.isPressed ? Self.pressedOpacity : 1) : Self.disabledOpacity)
            .scaleEffect(reduceMotion || !lifts ? 1 : configuration.isPressed ? Self.pressedScale : (lit ? Self.hoverScale : 1))
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.75), value: hovered)
            .onHover { hovered = $0 }
            .pointingHand()
    }
}

/// One tile of the notch's grid: a mark, its name, and a quiet line under it such as a shortcut or a state.
struct NotchTile<Mark: View>: View {
    let title: String
    var caption: String?
    var lit = false
    let action: () -> Void
    @ViewBuilder let mark: Mark
    /// Counted on every click, so the tile's symbol gives a small bounce that says the click landed.
    @State private var taps = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: NotchMetrics.tileRadius, style: .continuous)
        Button {
            taps += 1
            action()
        } label: {
            VStack(spacing: NotchMetrics.tileLineSpacing) {
                mark.frame(width: NotchMetrics.tileSymbolFrame, height: NotchMetrics.tileSymbolFrame)
                    .symbolEffect(.bounce, value: taps)
                Text(title)
                    .font(.system(size: NotchMetrics.tileTitle, weight: .medium))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if let caption {
                    Text(caption)
                        .font(.system(size: NotchMetrics.tileCaption, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(NotchMetrics.captionInk))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, Memnox.Spacing.small)
            .frame(maxWidth: .infinity)
            .frame(height: NotchMetrics.tileHeight)
            .background(Color.white.opacity(lit ? NotchMetrics.tileLitFill : NotchMetrics.tileFill), in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(lit ? NotchMetrics.tileLitRim : NotchMetrics.tileRim), lineWidth: Memnox.Stroke.hairline))
            .contentShape(shape)
        }
        .buttonStyle(NotchPressStyle(lifts: false))
        .help(title)
        .accessibilityLabel(caption.map { "\(title), \($0)" } ?? title)
    }
}

/// A tile's SF Symbol in the notch's ink, or in a colour of its own for the few tiles Vorssaint colours.
struct NotchSymbol: View {
    let name: String
    var tint: Color = Color.white.opacity(NotchMetrics.symbolInk)

    var body: some View {
        Image(systemName: name)
            .font(.system(size: NotchMetrics.tileSymbol, weight: .medium))
            .foregroundStyle(tint)
    }
}

/// Everything Memnox does from the notch, as Vorssaint's grid of tiles, with the person's agents and apps one tile away.
struct IslandLauncher: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var tools: ToolsModel
    @ObservedObject private var mute = VoiceMute.shared

    private enum Symbol {
        static let talk = "waveform"
        static let sessions = "square.stack.3d.up"
        static let history = "clock.arrow.circlepath"
        static let tools = "square.grid.2x2"
        static let rule = "shield.lefthalf.filled"
        static let mute = "speaker.slash"
        static let unmute = "speaker.wave.2"
        static let copy = "doc.on.clipboard"
        static let phones = "iphone"
        static let dictation = "keyboard"
        static let settings = "gearshape"
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: NotchMetrics.tileSpacing), count: NotchMetrics.tileColumns)
    }

    var body: some View {
        Group {
            if let tool = model.pickedTool {
                IslandToolPage(connection: tool, ask: ask)
            } else if model.launcherTools {
                toolsGrid
            } else {
                actions
            }
        }
        // A new page of tiles arrives afresh, so switching to the tools or to one app staggers them in again.
        .id(model.pickedTool?.id ?? (model.launcherTools ? "tools" : "actions"))
        .padding(.top, Island.top(model.notch))
        .padding([.horizontal, .bottom], Island.contentInset)
        .onAppear { tools.refresh() }
    }

    private var actions: some View {
        let working = model.working.count
        return LazyVGrid(columns: columns, spacing: NotchMetrics.tileSpacing) {
            NotchTile(title: "Talk", caption: "\u{2325} Space", action: model.tapped) {
                NotchSymbol(name: Symbol.talk, tint: Memnox.Palette.sky)
            }
            .notchArrival(order: 0)
            NotchTile(title: "Sessions", caption: working == 0 ? "None working" : "\(working) working", action: showSessions) {
                NotchSymbol(name: Symbol.sessions)
            }
            .notchArrival(order: 1)
            NotchTile(title: "History", caption: "Recent answers", lit: model.sideOpen, action: model.toggleSide) {
                NotchSymbol(name: Symbol.history)
            }
            .notchArrival(order: 2)
            NotchTile(title: "Tools", caption: toolsCaption, action: showTools) {
                NotchSymbol(name: Symbol.tools)
            }
            .notchArrival(order: 3)
            NotchTile(title: "Say a rule", caption: "Hold \u{2303}\u{2325}", action: model.sayRule) {
                NotchSymbol(name: Symbol.rule, tint: IslandPalette.amber)
            }
            .notchArrival(order: 4)
            NotchTile(title: mute.on ? "Unmute" : "Mute", caption: mute.on ? "Voice off" : "Voice on", lit: mute.on, action: mute.toggle) {
                NotchSymbol(name: mute.on ? Symbol.mute : Symbol.unmute, tint: mute.on ? IslandPalette.red : Color.white.opacity(NotchMetrics.symbolInk))
                    .contentTransition(.symbolEffect(.replace))
            }
            .notchArrival(order: 5)
            NotchTile(title: "What happened", caption: "Copy for support", action: model.copyWhatHappened) {
                NotchSymbol(name: Symbol.copy)
            }
            .notchArrival(order: 6)
            NotchTile(title: "Phones", caption: "Pair or revoke", action: { model.openSettings(.phones) }) {
                NotchSymbol(name: Symbol.phones)
            }
            .notchArrival(order: 7)
            NotchTile(title: "Dictation", caption: "Settings", action: { model.openSettings(.dictation) }) {
                NotchSymbol(name: Symbol.dictation)
            }
            .notchArrival(order: 8)
            NotchTile(title: "Settings", caption: "Everything else", action: { model.openSettings(nil) }) {
                NotchSymbol(name: Symbol.settings)
            }
            .notchArrival(order: 9)
        }
    }

    /// The agents first, then the apps signed in to, each a tile with its own logo and how it stands.
    private var toolsGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: NotchMetrics.tileSpacing) {
                ForEach(Array(tools.agents.enumerated()), id: \.element.id) { index, agent in
                    NotchTile(title: agent.label, caption: ToolStatus.agent(agent), action: { model.openSettings(.tools) }) {
                        AgentMark(kind: agent.kind, name: agent.label, side: NotchMetrics.tileSymbolFrame)
                    }
                    .notchArrival(order: index)
                }
                ForEach(Array(tools.connections.enumerated()), id: \.element.id) { index, connection in
                    NotchTile(title: ToolkitName.of(connection.toolkit), caption: ToolStatus.connection(connection),
                              action: { withAnimation(.snappy) { model.pickedTool = connection } }) {
                        ToolMark(toolkit: connection.toolkit, side: NotchMetrics.tileSymbolFrame)
                    }
                    .notchArrival(order: tools.agents.count + index)
                }
            }
            if let note = tools.connectionsNote ?? emptyNote {
                Text(note)
                    .font(Memnox.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Color.white.opacity(NotchMetrics.captionInk))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, NotchMetrics.tileSpacing)
                    .padding(.horizontal, Memnox.Spacing.xSmall)
            }
        }
        .scrollIndicators(.hidden)
    }

    private var emptyNote: String? {
        guard !tools.loading, tools.connections.isEmpty else { return nil }
        return "No apps connected yet. Ask Memnox to do something in Gmail, Slack or GitHub and it opens the sign in for you."
    }

    private var toolsCaption: String {
        let agents = tools.agents.count
        let apps = tools.connectedCount
        if agents == 0 && apps == 0 { return tools.loading ? "Reading" : "None yet" }
        return "\(agents + apps) connected"
    }

    private func showSessions() {
        model.launcher = false
        model.settle()
    }

    /// The grid steps aside so the conversation has the island, then the words go whole to ask.
    private func ask(_ words: String) {
        model.launcher = false
        model.launcherTools = false
        model.pickedTool = nil
        model.settle()
        model.ask(words)
    }

    private func showTools() {
        withAnimation(.snappy) { model.launcherTools = true }
        tools.refresh()
    }
}

/// The round buttons either side of the open island, as Vorssaint hangs its own beside the notch: the grid and the
/// history on the left, Settings and the voice on the right.
struct IslandSatellites: View {
    @ObservedObject var model: IslandModel
    @ObservedObject private var mute = VoiceMute.shared
    let islandWidth: CGFloat
    /// False for the first moment, so each column starts tucked behind the island's edge and slides out of it.
    @State private var out = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Tucked in this far, a column sits just behind the island's side.
    private static let tucked: CGFloat = NotchMetrics.satelliteGap + NotchMetrics.satelliteDiameter
    /// Each button in a column follows the one above it by this much.
    private static let stagger: TimeInterval = 0.05

    private enum Symbol {
        static let grid = "square.grid.2x2"
        static let history = "clock.arrow.circlepath"
        static let settings = "gearshape"
        static let mute = "speaker.slash"
        static let unmute = "speaker.wave.2"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: NotchMetrics.satelliteStep - NotchMetrics.satelliteDiameter) {
                satellite(Symbol.grid, "Everything Memnox does", on: model.mode == .launcher, action: toggleLauncher)
                    .slidingOut(out, from: Self.tucked, after: 0, reduceMotion: reduceMotion)
                satellite(Symbol.history, "History, sessions and what needs you", on: model.sideOpen, action: model.toggleSide)
                    .slidingOut(out, from: Self.tucked, after: Self.stagger, reduceMotion: reduceMotion)
            }
            Spacer().frame(width: islandWidth + 2 * NotchMetrics.satelliteGap)
            VStack(spacing: NotchMetrics.satelliteStep - NotchMetrics.satelliteDiameter) {
                satellite(Symbol.settings, "Settings", on: false) { model.openSettings(nil) }
                    .slidingOut(out, from: -Self.tucked, after: 0, reduceMotion: reduceMotion)
                satellite(mute.on ? Symbol.mute : Symbol.unmute, mute.on ? "Unmute the voice" : "Mute the voice", on: mute.on, action: mute.toggle)
                    .slidingOut(out, from: -Self.tucked, after: Self.stagger, reduceMotion: reduceMotion)
            }
        }
        .onAppear { out = true }
    }

    private func toggleLauncher() {
        model.launcher.toggle()
        model.launcherTools = false
        model.detail = false
        model.picked = nil
        model.settle()
    }

    private func satellite(_ symbol: String, _ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: NotchMetrics.satelliteSymbol, weight: .medium))
                .foregroundStyle(Color.white)
                // Mute and unmute morph one speaker into the other rather than swapping pictures.
                .contentTransition(.symbolEffect(.replace))
                .frame(width: NotchMetrics.satelliteDiameter, height: NotchMetrics.satelliteDiameter)
                .background(Color.black, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(on ? NotchMetrics.tileLitRim : NotchMetrics.satelliteRim),
                                               lineWidth: NotchMetrics.satelliteRimWidth))
                .contentShape(Circle())
        }
        .buttonStyle(NotchPressStyle(cornerRadius: NotchMetrics.satelliteDiameter / 2))
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Tiles arriving one after another, each rising a little and growing to its size, as the grid opens.
private struct NotchArrival: ViewModifier {
    let order: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let rise: CGFloat = 10
    private static let startScale: CGFloat = 0.92
    /// Each tile waits this much longer than the one before it, and the grid waits for the island to open first.
    private static let stagger: TimeInterval = 0.025
    private static let wait: TimeInterval = 0.08
    private static let spring = Animation.spring(response: 0.38, dampingFraction: 0.78)

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : Self.rise)
            .scaleEffect(shown || reduceMotion ? 1 : Self.startScale)
            .onAppear {
                withAnimation(Self.spring.delay(Self.wait + Double(order) * Self.stagger)) { shown = true }
            }
    }
}

/// How a round button slides out from behind the island.
private let satelliteSlide = Animation.spring(response: 0.42, dampingFraction: 0.72)

extension View {
    func notchArrival(order: Int) -> some View { modifier(NotchArrival(order: order)) }

    /// A round button slides out sideways from behind the island, or only fades in with Reduce Motion.
    fileprivate func slidingOut(_ out: Bool, from distance: CGFloat, after delay: TimeInterval, reduceMotion: Bool) -> some View {
        offset(x: out || reduceMotion ? 0 : distance)
            .opacity(out ? 1 : 0)
            .animation(satelliteSlide.delay(delay), value: out)
    }
}
