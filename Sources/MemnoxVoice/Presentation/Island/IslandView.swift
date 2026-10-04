import AppKit
import MetalKit
import MemnoxVoiceCore
import SwiftUI

/// The island: a black shape that flows out of the screen's top edge, the orb, and the content of the mode.
struct IslandView: View {
    @ObservedObject var model: IslandModel
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
            .modifier(ShakeEffect(times: CGFloat(model.shakes)))
            .modifier(HopEffect(times: CGFloat(model.hops)))
            .animation(.easeInOut(duration: Memnox.Motion.slow), value: model.hops)
            .animation(Timing.shake, value: model.shakes)
            Spacer(minLength: 0)
        }
        .frame(width: Island.window.width, height: Island.window.height, alignment: .top)
    }

    /// The talking modes share one content, so the island grows around the words instead of fading them out and in.
    private var contentId: IslandMode {
        switch model.mode {
        case .conversation, .draft, .rule: return .conversation
        case .answer: return model.active ? .conversation : .answer
        case .peek, .compact, .voice, .hearing, .overview, .session, .empty, .held, .finished: return model.mode
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
        case .finished:
            if let finished = model.finished { IslandFinished(model: model, card: finished) }
        case .hearing:
            IslandHearing(model: model)
        case .conversation, .draft, .rule:
            IslandConversation(model: model, exchange: model.turn, live: model.active)
        case .answer:
            if model.active {
                IslandConversation(model: model, exchange: model.turn, live: true)
            } else if let picked = model.pickedExchange {
                IslandConversation(model: model, exchange: picked, live: false)
            }
        }
    }
}

/// The row along the notch while the island is open: where you are on the left, how many are working on the right.
struct IslandHeader: View {
    @ObservedObject var model: IslandModel

    private enum Symbol {
        static let overview = "square.grid.2x2"
        static let back = "chevron.left"
        static let voice = "waveform"
        static let history = "clock.arrow.circlepath"
    }

    private enum Layout {
        static let countSize: CGFloat = 12.5
        static let countTrailing: CGFloat = 18
        /// Clears the small orb that sits at the start of the header row on an opened answer.
        static let pastOrb: CGFloat = 46
    }

    private static let countOpacity = 0.55

    var body: some View {
        let count = model.working.count
        HStack(spacing: Memnox.Spacing.xSmall) {
            IslandTab(symbol: Symbol.overview, on: model.mode == .overview || model.mode == .empty) {
                model.detail = false
                model.picked = nil
                model.settle()
            }
            IslandTab(symbol: Symbol.history, on: model.sideOpen) { model.toggleSide() }
                .help("History, sessions and what needs you")
            if model.mode == .session || model.mode == .answer {
                IslandTab(symbol: Symbol.back, on: false) {
                    model.detail = false
                    model.picked = nil
                    model.settle()
                }
            }
            IslandTab(symbol: Symbol.voice, on: model.mode == .voice) { model.tapped() }
            Spacer(minLength: model.notch.width + Memnox.Spacing.xLarge)
            Text(count == 1 ? "1 working" : "\(count) working")
                .font(Memnox.sans(Layout.countSize, .medium))
                .foregroundStyle(Color.white.opacity(Self.countOpacity))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: count)
                .padding(.trailing, Layout.countTrailing)
        }
        .padding(.leading, model.mode == .answer ? Layout.pastOrb : Memnox.Spacing.large)
        .frame(height: model.notch.height)
    }
}

/// A round icon tab in the header, filled when it is where you are.
struct IslandTab: View {
    let symbol: String
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
    }
}

/// Beside the notch with sessions working or the voice listening: the orb left, and on the right
/// a waveform for the voice or one dot per working session.
struct IslandCompact: View {
    @ObservedObject var model: IslandModel
    let loudness: () -> Float

    private enum Layout {
        static let waveformWidth: CGFloat = 36
        static let waveformHeight: CGFloat = 16
        static let waveformTrailing: CGFloat = 14
        /// As many logos as fit beside the notch before they crowd it.
        static let shownLogos = 3
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
                IslandLogos(cards: Array(model.working.prefix(Layout.shownLogos)))
                    .frame(height: height)
                    .padding(.trailing, Memnox.Spacing.large)
            }
        }
        .frame(height: height)
        .contentShape(Rectangle())
        .onTapGesture { model.tapped() }
    }
}

/// The working agents' logos, overlapping like faces in a doorway, so a glance says who is busy.
struct IslandLogos: View {
    let cards: [SessionCard]

    /// Each logo tucks this far under the one before it.
    private static let overlap: CGFloat = -5
    private static let logoSide: CGFloat = 16
    /// A black ring the island's colour, so overlapping logos stay apart.
    private static let ringWidth: CGFloat = 1.5
    private static let arrival = Animation.spring(response: 0.4, dampingFraction: 0.7)

    var body: some View {
        HStack(spacing: Self.overlap) {
            ForEach(cards, id: \.sessionId) { card in
                SessionLogo(card: card, size: Self.logoSide)
                    .overlay(Circle().strokeBorder(Color.black, lineWidth: Self.ringWidth))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(Self.arrival, value: cards.map(\.sessionId))
    }
}

/// Talking: the big orb alone with a soft light behind it, until words are heard. With live words on
/// the island turns to `IslandHearing` as the first word lands; with them off it stays the orb alone.
struct IslandVoiceCard: View {
    @ObservedObject var model: IslandModel

    private enum Glow {
        /// Dim while idle, brighter once the voice is in use.
        static let idleOpacity = 0.12
        static let activeOpacity = 0.28
        /// The pool fades out just inside the orb's own reach.
        static let reach: CGFloat = 0.95
        /// Matches the voice orb's centre below the header in `Island.orb`.
        static let drop: CGFloat = 92
    }

    var body: some View {
        let top = Island.top(model.notch)
        ZStack(alignment: .top) {
            // The orb draws additively, so a dim pool of its own blue behind it reads as the glow off a light.
            RadialGradient(
                colors: [glow.opacity(model.state == .idle ? Glow.idleOpacity : Glow.activeOpacity), .clear],
                center: .center, startRadius: 0, endRadius: Island.voiceOrb * Glow.reach
            )
            .frame(width: Island.voiceOrb * 2, height: Island.voiceOrb * 2)
            .position(x: Island.voiceWidth / 2, y: top + Glow.drop)
            .animation(.easeInOut(duration: Memnox.Motion.slow), value: model.state)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { model.tapped() }
    }

    private var glow: Color { model.state == .needsYou ? Memnox.Palette.sky : Memnox.Palette.primary }
}
