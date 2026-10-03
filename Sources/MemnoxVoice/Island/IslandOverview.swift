import AppKit
import MemnoxVoiceCore
import SwiftUI

/// Every session at a glance: the one in focus on the left with what it is doing, the rest as pills.
struct IslandOverview: View {
    @ObservedObject var model: IslandModel

    private enum Layout {
        static let titleDotSpacing: CGFloat = 7
        static let focusDotSide: CGFloat = 8
        /// Lines the subtitle up under the title, past the dot and its gap.
        static let subtitleIndent: CGFloat = focusDotSide + titleDotSpacing
        /// Clears the orb, which sits over the focus card's left side.
        static let focusTextLeading: CGFloat = 102
        static let focusTextTrailing: CGFloat = 14
        static let focusCardWidth: CGFloat = 322
        /// Matches the corners `IslandCard` draws.
        static let cardRadius: CGFloat = 20
        /// As many rows as the list card holds at the overview's height.
        static let listedSessions = 4
        /// How far each row rises as it fades in.
        static let rowRise: CGFloat = 6
    }

    private enum Timing {
        static let rowSpring = Animation.spring(response: 0.42, dampingFraction: 0.8)
        /// The rows wait for the island to open, then arrive one after another.
        static let rowDelay: TimeInterval = 0.22
        static let rowStagger: TimeInterval = 0.035
    }

    /// Amber while a call waits on you, and the agent's own colour fainter while it works.
    private static let heldVeilOpacity = 0.42
    private static let workingVeilOpacity = 0.32

    var body: some View {
        HStack(spacing: Memnox.Spacing.regular) {
            IslandCard(veil: veil) {
                VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                    if let card = model.focusCard {
                        HStack(spacing: Layout.titleDotSpacing) {
                            Circle().fill(IslandPalette.color(card.agent)).frame(width: Layout.focusDotSide, height: Layout.focusDotSide)
                            Text(card.title)
                                .font(Memnox.sans(Memnox.TextSize.callout, .semibold))
                                .foregroundStyle(Color.white)
                                .lineLimit(1)
                        }
                        Text(card.subtitle(now: Date()))
                            .font(Memnox.sans(Memnox.TextSize.footnote))
                            .foregroundStyle(Color.white.opacity(Memnox.Ink.tertiary))
                            .lineLimit(1)
                            .padding(.leading, Layout.subtitleIndent)
                        IslandStepRoll(steps: SessionText.meaningful(model.focused?.steps ?? []), thinking: card.thinking)
                    }
                }
                .padding(.leading, Layout.focusTextLeading)
                .padding(.trailing, Layout.focusTextTrailing)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(width: Layout.focusCardWidth)
            .contentShape(RoundedRectangle(cornerRadius: Layout.cardRadius))
            .onTapGesture {
                model.detail = true
                model.settle()
            }
            .help("See what it is changing")
            IslandCard(veil: nil) {
                VStack(spacing: Memnox.Spacing.xxSmall) {
                    ForEach(Array(model.cards.prefix(Layout.listedSessions).enumerated()), id: \.element.sessionId) { index, card in
                        IslandSessionRow(
                            card: card,
                            focused: card.sessionId == model.focusCard?.sessionId,
                            preview: { model.focus(card.sessionId) },
                            open: { model.openWindow(card.sessionId, card.host) }
                        )
                        .opacity(model.revealed ? 1 : 0)
                        .offset(y: model.revealed ? 0 : Layout.rowRise)
                        .animation(
                            Timing.rowSpring.delay(Timing.rowDelay + Double(index) * Timing.rowStagger),
                            value: model.revealed
                        )
                    }
                    Spacer(minLength: 0)
                }
                .padding(Memnox.Spacing.medium)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .islandContentInset(model.notch)
    }

    private var veil: Color? {
        guard let card = model.focusCard else { return nil }
        if (model.focused?.waitingOnYou ?? 0) > 0 { return IslandPalette.amber.opacity(Self.heldVeilOpacity) }
        return card.status.isActive ? IslandPalette.color(card.agent).opacity(Self.workingVeilOpacity) : nil
    }
}

/// The last few things a session did, the newest bright and shimmering while it works, rolling up as more arrive.
struct IslandStepRoll: View {
    let steps: [SessionViewStep]
    let thinking: Bool

    private enum Layout {
        static let shownSteps = 3
        static let iconSpacing: CGFloat = 9
        static let iconColumnWidth: CGFloat = 14
        static let lineHeight: CGFloat = 30
        /// Three lines high, with a little room above them for the oldest to fade through.
        static let rollHeight: CGFloat = 96
        /// Where the fade at the top gives way to full strength.
        static let fadeEnd = 0.28
    }

    private static let roll = Animation.timingCurve(0.3, 0.9, 0.3, 1, duration: 0.45)

    var body: some View {
        let shown = Array(steps.suffix(Layout.shownSteps))
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.at) { index, step in
                let current = index == shown.count - 1
                HStack(spacing: Layout.iconSpacing) {
                    Image(systemName: stepIcon(step))
                        .font(.system(size: Memnox.TextSize.footnote, weight: .medium))
                        .foregroundStyle(stepTint(step, current: current))
                        .frame(width: Layout.iconColumnWidth)
                    if current && thinking {
                        ShimmerText(text: SessionText.line(for: step))
                    } else {
                        Text(SessionText.line(for: step))
                            .font(Memnox.sans(current ? Memnox.TextSize.callout : Memnox.TextSize.body, current ? .medium : .regular))
                            .foregroundStyle(current ? IslandPalette.soft : IslandPalette.quiet)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(height: Layout.lineHeight)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if shown.isEmpty {
                Text(thinking ? "Thinking" : "Nothing done yet")
                    .font(Memnox.sans(Memnox.TextSize.body))
                    .foregroundStyle(IslandPalette.quiet)
                    .frame(height: Layout.lineHeight)
            }
        }
        .frame(height: Layout.rollHeight, alignment: .bottom)
        .clipped()
        .mask(
            LinearGradient(
                stops: [.init(color: .clear, location: 0), .init(color: .black, location: Layout.fadeEnd), .init(color: .black, location: 1)],
                startPoint: .top, endPoint: .bottom
            )
        )
        .animation(Self.roll, value: shown.map(\.at))
    }
}

/// A line whose brightness sweeps across it, the way a task in progress reads at a glance.
struct ShimmerText: View {
    let text: String

    /// One sweep across the line takes this long.
    private static let period: TimeInterval = 2.2
    /// How far either side of the bright point the light fades back to dim.
    private static let halfWidth = 0.25

    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period) / Self.period
            Text(text)
                .font(Memnox.sans(Memnox.TextSize.callout, .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(Memnox.Ink.tertiary), location: max(0, phase - Self.halfWidth)),
                            .init(color: Color.white, location: phase),
                            .init(color: Color.white.opacity(Memnox.Ink.tertiary), location: min(1, phase + Self.halfWidth)),
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
        }
    }
}

/// One session in the list: its logo, what it is on, which agent and how lately, and whether it is working.
/// Resting the pointer on it shows it on the left; clicking it goes to its own window.
struct IslandSessionRow: View {
    let card: SessionCard
    let focused: Bool
    let preview: () -> Void
    let open: () -> Void

    private enum Layout {
        static let logoSide: CGFloat = 26
        static let lineSpacing: CGFloat = 1
        static let titleSize: CGFloat = 12.5
        static let workingDotSide: CGFloat = 7
        static let rowHeight: CGFloat = 32
        static let rowRadius: CGFloat = 11
        /// The arrow grows in from this scale as the row takes focus.
        static let arrowAppearScale: CGFloat = 0.6
    }

    private enum Shade {
        /// Rows not in focus step back a little, so the focused one leads.
        static let unfocusedTitle = 0.85
        static let subtitle = 0.4
        static let arrow = 0.6
    }

    private static let openSymbol = "arrow.up.forward"
    private static let focusFade = Animation.easeOut(duration: 0.15)

    var body: some View {
        Button(action: open) {
            HStack(spacing: Memnox.Spacing.regular) {
                SessionLogo(card: card, size: Layout.logoSide)
                VStack(alignment: .leading, spacing: Layout.lineSpacing) {
                    Text(card.title)
                        .font(Memnox.sans(Layout.titleSize, .semibold))
                        .foregroundStyle(Color.white.opacity(focused ? 1 : Shade.unfocusedTitle))
                        .lineLimit(1)
                    Text(card.subtitle(now: Date()))
                        .font(Memnox.sans(Memnox.TextSize.caption))
                        .foregroundStyle(Color.white.opacity(Shade.subtitle))
                        .lineLimit(1)
                }
                Spacer(minLength: Memnox.Spacing.small)
                if focused {
                    Image(systemName: Self.openSymbol)
                        .font(.system(size: Memnox.TextSize.caption, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(Shade.arrow))
                        .transition(.opacity.combined(with: .scale(scale: Layout.arrowAppearScale)))
                } else if card.status.isActive {
                    Circle().fill(Memnox.Palette.sky).frame(width: Layout.workingDotSide, height: Layout.workingDotSide).modifier(PulseEffect())
                }
            }
            .padding(.horizontal, Memnox.Spacing.medium)
            .frame(height: Layout.rowHeight)
            .background(RoundedRectangle(cornerRadius: Layout.rowRadius, style: .continuous).fill(Color.white.opacity(focused ? Memnox.Ink.fill : 0)))
            .contentShape(RoundedRectangle(cornerRadius: Layout.rowRadius))
            .animation(Self.focusFade, value: focused)
        }
        .buttonStyle(PressableStyle())
        .onHover { inside in if inside { preview() } }
        .help("Go to this session")
    }
}

/// An agent's logo in a disc of its own colour.
struct SessionLogo: View {
    let card: SessionCard
    let size: CGFloat

    /// The logo fills a little over half the disc, leaving a ring of colour around it.
    private static let logoScale: CGFloat = 0.56

    var body: some View {
        AgentLogo(kind: IslandPalette.kind(card.agent), name: card.agentName)
            .frame(width: size * Self.logoScale, height: size * Self.logoScale)
            .frame(width: size, height: size)
            .background(Circle().fill(IslandPalette.color(card.agent)))
    }
}
