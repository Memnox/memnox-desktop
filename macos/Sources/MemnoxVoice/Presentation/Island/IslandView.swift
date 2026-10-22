import AppKit
import MetalKit
import MemnoxVoiceCore
import SwiftUI

/// The island: a black shape that flows out of the screen's top edge, the orb, and the content of the mode.
struct IslandView: View {
    @ObservedObject var model: IslandModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let orb: MTKView
    let loudness: () -> Float

    private enum Layout {
        /// The orb fills this share of its canvas, leaving the rest for its glow.
        static let orbCanvasShare: CGFloat = 0.62
        static let openBottomRadius: CGFloat = 30
        static let closedBottomRadius: CGFloat = 14
        static let shadowRadius: CGFloat = 18
        static let shadowDrop: CGFloat = 8
        /// The line that counts down the last seconds before the island puts itself away.
        static let countdownWidth: CGFloat = 160
        static let countdownThickness: CGFloat = 2
        static let countdownLift: CGFloat = 4
        /// The space between the island and the drive state under it.
        static let drivenGap: CGFloat = 6
    }

    private enum Shade {
        /// An open island casts a deeper shadow, so it reads as lifted over the window below.
        static let openShadow = 0.45
        static let closedShadow = 0.2
        static let countdown = 0.35
    }

    private enum Timing {
        /// The header fades in once the island has mostly opened.
        static let headerIn = Animation.easeOut(duration: 0.25).delay(0.3)
        static let shake = Animation.linear(duration: 0.42)
    }

    var body: some View {
        let notch = model.notch
        let size = model.size(of: model.mode)
        let orbAt = Island.orb(model.mode, notch, hovering: model.hovering)
        let canvas = orbAt.diameter / Layout.orbCanvasShare
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                NotchShape(flare: Island.flare, bottomRadius: model.mode.isOpen ? Layout.openBottomRadius : Layout.closedBottomRadius)
                    .fill(Color.black)
                    .shadow(color: .black.opacity(model.mode.isOpen ? Shade.openShadow : Shade.closedShadow), radius: Layout.shadowRadius, y: Layout.shadowDrop)
                ZStack(alignment: .topLeading) {
                    if model.showsHeader {
                        IslandHeader(model: model)
                            .transition(.opacity.animation(Timing.headerIn))
                    }
                    content
                        .id(contentId)
                        .transition(.islandContent)
                    // One orb throughout, positioned rather than swapped, so it travels and grows with the island.
                    IslandOrbSurface(view: orb)
                        .frame(width: canvas, height: canvas)
                        .position(orbAt.center)
                        .allowsHitTesting(false)
                    if let countdown = model.countdown {
                        Capsule()
                            .fill(Color.white.opacity(Shade.countdown))
                            .frame(width: Layout.countdownWidth * countdown, height: Layout.countdownThickness)
                            .position(x: size.width / 2, y: size.height - Layout.countdownLift)
                            .animation(.linear(duration: Memnox.Motion.quick), value: countdown)
                    }
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .padding(.leading, Island.flare)
            }
            .frame(width: size.width + 2 * Island.flare, height: size.height, alignment: .topLeading)
            .overlay(alignment: .top) {
                if model.showsSatellites {
                    IslandSatellites(model: model, islandWidth: size.width)
                        .padding(.top, Island.satelliteTop(model.notch))
                        // They slide out from behind the island on their own; leaving, they only fade.
                        .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.36, dampingFraction: 0.8), value: model.showsSatellites)
            .modifier(ShakeEffect(times: CGFloat(model.shakes)))
            .modifier(HopEffect(times: CGFloat(model.hops)))
            // With Reduce Motion the hop and the shake are skipped; the card and the sound still say what happened.
            .animation(reduceMotion ? nil : .easeInOut(duration: Memnox.Motion.slow), value: model.hops)
            .animation(reduceMotion ? nil : Timing.shake, value: model.shakes)
            // Under the island in every mode, so somebody at the Mac always knows a phone is driving it.
            if let driving = model.driving {
                IslandPhonePill(label: driving.label, symbol: IslandPhonePill.driving)
                    .padding(.top, Layout.drivenGap)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .allowsHitTesting(false)
            }
            VStack(spacing: 0) {
                // Under the island in every mode, so a newer Memnox is one press away whatever the island is doing.
                if let update = model.update {
                    IslandUpdatePill(model: model, card: update)
                        .padding(.top, Layout.drivenGap)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                // Under the island in every mode, so whose account a sign in reached is seen the moment it finishes.
                if let signedIn = model.signedIn {
                    IslandSignedInPill(model: model, card: signedIn)
                        .padding(.top, Layout.drivenGap)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                // Under the island in every mode, so a tool they asked for and cannot use yet is one tap from working.
                if !model.signIns.isEmpty {
                    IslandSignInRow(model: model)
                        .padding(.top, Layout.drivenGap)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            // Measured, since the window lets clicks through everywhere but where something takes them.
            .background(GeometryReader { proxy in
                Color.clear.preference(key: ClickableBelow.self, value: proxy.frame(in: .named(Self.space)))
            })
            // Under the island in every mode, so somebody at the Mac knows why it stays silent.
            if let voiceOn = model.voiceOn {
                IslandPhonePill(label: voiceOn.label, symbol: IslandPhonePill.talking)
                    .padding(.top, Layout.drivenGap)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .allowsHitTesting(false)
            }
            Spacer(minLength: 0)
        }
        .frame(width: Island.window.width, height: Island.window.height, alignment: .top)
        .coordinateSpace(name: Self.space)
        .onPreferenceChange(ClickableBelow.self) { model.clickableBelow = $0 }
    }

    /// The window's own space, top left origin, which the panel maps onto the screen.
    private static let space = "island"

    /// The talking modes share one content, so the island grows around the words instead of fading them out and in.
    private var contentId: IslandMode {
        switch model.mode {
        case .conversation, .draft, .rule: return .conversation
        case .answer: return model.active ? .conversation : .answer
        case .peek, .compact, .voice, .hearing, .overview, .session, .empty, .held, .question, .finished, .launcher: return model.mode
        }
    }

    @ViewBuilder private var content: some View {
        switch model.mode {
        case .peek:
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { model.tapped() }
        case .compact:
            IslandCompact(model: model, loudness: loudness)
        case .voice:
            IslandVoiceCard(model: model)
        case .overview:
            IslandOverview(model: model)
        case .session:
            if let session = model.focused { IslandSessionDetail(model: model, session: session) }
        case .empty:
            IslandEmpty(model: model)
        case .held:
            if let held = model.held { IslandHeldCall(model: model, card: held) }
        case .question:
            if let question = model.question { IslandQuestion(model: model, card: question) }
        case .finished:
            if let finished = model.finished { IslandFinished(model: model, card: finished) }
        case .launcher:
            IslandLauncher(model: model, tools: model.tools)
        case .hearing:
            IslandHearing(model: model)
        case .conversation, .draft, .rule:
            if let phone = model.phoneTurn {
                IslandConversation(model: model, exchange: phone.exchange, live: false, from: phone.label)
            } else {
                IslandConversation(model: model, exchange: model.turn, live: model.active)
            }
        case .answer:
            if model.active {
                IslandConversation(model: model, exchange: model.turn, live: true)
            } else if let picked = model.pickedExchange {
                IslandConversation(model: model, exchange: picked, live: false)
            }
        }
    }
}

/// The pill under the island while a phone drives this Mac or holds its voice: which phone, for as long as it lasts.
struct IslandPhonePill: View {
    let label: String
    let symbol: String

    static let driving = "iphone.radiowaves.left.and.right"
    static let talking = "iphone"
    private static let horizontalPadding: CGFloat = 12
    private static let verticalPadding: CGFloat = 5

    var body: some View {
        HStack(spacing: Memnox.Spacing.xSmall) {
            Image(systemName: symbol)
                .font(.system(size: Memnox.TextSize.caption, weight: .semibold))
                .foregroundStyle(IslandPalette.amber)
            Text(label)
                .font(Memnox.sans(Memnox.TextSize.caption, .medium))
                .foregroundStyle(Color.white)
                .lineLimit(1)
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, Self.verticalPadding)
        .background(Capsule().fill(Color.black))
        .overlay(Capsule().strokeBorder(IslandPalette.amber.opacity(Memnox.Ink.tertiary)))
        .accessibilityElement(children: .combine)
    }
}

/// The row along the notch while the island is open, as Vorssaint heads its notch: the page's title on the left and how
/// many are working on the right; the grid, the history and Settings hang beside the island as round buttons.
struct IslandHeader: View {
    @ObservedObject var model: IslandModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Symbol {
        static let back = "chevron.left"
    }

    private enum Layout {
        static let countSize: CGFloat = 12.5
        static let countTrailing: CGFloat = 18
        /// Clears the small orb that sits at the start of the header row on an opened answer.
        static let pastOrb: CGFloat = 46
        static let titleLeading: CGFloat = 18
    }

    private static let countOpacity = 0.55

    var body: some View {
        let count = model.working.count
        HStack(spacing: Memnox.Spacing.small) {
            if showsBack {
                IslandTab(symbol: Symbol.back, label: "Back", on: false, action: back)
            }
            // One page's name blurs into the next, so moving between pages is seen as well as read.
            Text(model.title)
                .font(.system(size: NotchMetrics.titleSize, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .id(model.title)
                .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace))
                .animation(.snappy, value: model.title)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: model.notch.width + Memnox.Spacing.xLarge)
            // Nothing at all when nothing works, since "0 working" reads like a fault.
            Text(count == 1 ? "1 working" : "\(count) working")
                .font(Memnox.sans(Layout.countSize, .medium))
                .foregroundStyle(Color.white.opacity(Self.countOpacity))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: count)
                .padding(.trailing, Layout.countTrailing)
                .opacity(count == 0 ? 0 : 1)
                .accessibilityHidden(count == 0)
        }
        .padding(.leading, pastOrb ? Layout.pastOrb : Layout.titleLeading)
        .frame(height: model.notch.height)
    }

    /// The small orb sits at the start of the header in these modes, so the title starts past it.
    private var pastOrb: Bool { model.mode == .answer || model.mode == .session || model.mode == .launcher || model.mode == .question }

    private var showsBack: Bool {
        model.mode == .session || model.mode == .answer || (model.mode == .launcher && (model.launcherTools || model.launcherPanel != nil))
    }

    private func back() {
        if model.mode == .launcher {
            // One app steps back to the tools, and the tools step back to the grid.
            withAnimation(.snappy) {
                if model.pickedTool != nil {
                    model.pickedTool = nil
                } else if model.launcherPanel != nil {
                    model.launcherPanel = nil
                } else {
                    model.launcherTools = false
                }
            }
            return
        }
        model.detail = false
        model.picked = nil
        model.settle()
    }
}

/// A round icon tab in the header, filled when it is where you are.
struct IslandTab: View {
    let symbol: String
    /// Said by VoiceOver and shown on hover, since the tab is an icon alone.
    let label: String
    let on: Bool
    let action: () -> Void

    private static let width: CGFloat = 30
    private static let height: CGFloat = 24
    private static let onFillOpacity = 0.12

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: Memnox.TextSize.footnote, weight: .semibold))
                .foregroundStyle(on ? Color.white : Color.white.opacity(Memnox.Ink.secondary))
                .frame(width: Self.width, height: Self.height)
                .background(Capsule().fill(Color.white.opacity(on ? Self.onFillOpacity : 0)))
        }
        .buttonStyle(PressableStyle())
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Beside the notch with sessions working or the voice listening: the orb left, and on the right
/// a waveform for the voice or the grid of working agents.
struct IslandCompact: View {
    @ObservedObject var model: IslandModel
    let loudness: () -> Float

    private enum Layout {
        static let waveformWidth: CGFloat = 36
        static let waveformHeight: CGFloat = 16
        static let waveformTrailing: CGFloat = 14
        static let gridTrailing: CGFloat = 12
    }

    var body: some View {
        let height = model.notch.height
        ZStack(alignment: .trailing) {
            Color.clear
            if model.active {
                IslandWaveform(loudness: loudness, state: model.state)
                    .frame(width: Layout.waveformWidth, height: Layout.waveformHeight)
                    .padding(.trailing, Layout.waveformTrailing)
            } else {
                IslandWorkforce(
                    cards: model.working,
                    waiting: model.held?.sessionId,
                    stumbling: model.stumbling,
                    rowHeight: height
                )
                    .padding(.trailing, Layout.gridTrailing)
            }
        }
        .frame(height: height)
        .contentShape(Rectangle())
        .onTapGesture { model.tapped() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.tapped() }
    }

    /// What the bar beside the notch means, for someone who cannot see the orb or the grid.
    private var spoken: String {
        if model.active { return model.dictating == nil ? "Memnox is listening" : "Dictating" }
        if model.held != nil || model.question != nil { return "An agent is waiting for you" }
        let count = model.working.count
        return count == 1 ? "1 agent working" : "\(count) agents working"
    }
}

/// The working agents as a two by two grid of faces beside the notch, like desks in a small office: a glance
/// says who is busy, the one waiting on the person hops with an amber edge, and a fifth agent turns the last
/// desk into a count of the rest.
struct IslandWorkforce: View {
    let cards: [SessionCard]
    /// The session a held call is waiting on, whose face hops until it is answered.
    var waiting: String?
    var stumbling: Set<String> = []
    /// The notch row's height, which the grid fills less its inset.
    let rowHeight: CGFloat

    private static let columns = 2
    private static let desks = 4
    private static let gap: CGFloat = 2
    /// Clear of the notch's top and bottom edge, so the grid never touches the bezel.
    private static let inset: CGFloat = 4
    /// Large enough to tell one agent from another, small enough that four fit a notch.
    private static let largestFace: CGFloat = 14
    private static let corner: CGFloat = 4
    private static let logoScale: CGFloat = 0.62
    private static let waitingEdge: CGFloat = 1.2
    private static let emptyDesk = Color.white.opacity(0.08)
    private static let countDesk = Color.white.opacity(0.18)
    /// The count of agents left over reads at the size of a face's logo.
    private static let countScale: CGFloat = 0.6
    private static let arrival = Animation.spring(response: 0.4, dampingFraction: 0.7)

    private var face: CGFloat { min(Self.largestFace, (rowHeight - 2 * Self.inset - Self.gap) / 2) }

    /// Four desks when four or fewer agents work; past that the last one counts the agents who do not fit.
    private var seated: [SessionCard] { Array(cards.prefix(cards.count > Self.desks ? Self.desks - 1 : Self.desks)) }
    private var unseated: Int { cards.count - seated.count }

    var body: some View {
        let grid = [GridItem](repeating: GridItem(.fixed(face), spacing: Self.gap), count: Self.columns)
        LazyVGrid(columns: grid, spacing: Self.gap) {
            ForEach(0..<Self.desks, id: \.self) { index in desk(at: index) }
        }
        .frame(width: 2 * face + Self.gap)
        .animation(Self.arrival, value: cards.map(\.sessionId))
    }

    @ViewBuilder private func desk(at index: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
        if index < seated.count {
            let card = seated[index]
            AgentLogo(kind: IslandPalette.kind(card.agent), name: card.agentName)
                .frame(width: face * Self.logoScale, height: face * Self.logoScale)
                .frame(width: face, height: face)
                .background(shape.fill(IslandPalette.color(card.agent)))
                .overlay(shape.strokeBorder(Memnox.Palette.warm, lineWidth: card.sessionId == waiting ? Self.waitingEdge : 0))
                .modifier(LogoMood(bouncing: card.sessionId == waiting, stumbling: stumbling.contains(card.sessionId)))
                .transition(.scale.combined(with: .opacity))
        } else if index == Self.desks - 1, unseated > 0 {
            Text("+\(unseated)")
                .font(.system(size: face * Self.countScale, weight: .bold).monospacedDigit())
                .minimumScaleFactor(Self.countScale)
                .foregroundStyle(.white)
                .frame(width: face, height: face)
                .background(shape.fill(Self.countDesk))
        } else {
            shape.fill(Self.emptyDesk).frame(width: face, height: face)
        }
    }
}

/// Talking: the big orb alone on the black, until words are heard. With live words on the island turns
/// to `IslandHearing` as the first word lands; with them off it stays the orb alone.
struct IslandVoiceCard: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        // No pool of light behind the orb, since a flat disc there spilled past the notch; the orb is its own light.
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
            .onTapGesture { model.tapped() }
    }
}

/// Where the clickable pills under the island sit, in the island's space.
private struct ClickableBelow: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
