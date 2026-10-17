import AppKit
import MemnoxVoiceCore
import SwiftUI

/// What the switcher shows: the sessions as cards, which one is in front, and how far along it is.
@MainActor
final class SwitcherModel: ObservableObject {
    @Published var cards: [SessionCard] = []
    /// Fractional while it turns, so the cards swing smoothly between places.
    @Published var selected: Double = 0
    @Published var shown = false
    /// The chosen card coming forward before it becomes the window it opens into.
    @Published var chosen = false
    var picked: ((SessionCard) -> Void)?
}

/// A card counts as the one in front while the turn is within half a place of it.
private let frontReach = 0.5

private let nanosecondsPerSecond: TimeInterval = 1_000_000_000

/// The sleep API takes nanoseconds, so every wait is written in seconds and converted once.
private func nanoseconds(_ seconds: TimeInterval) -> UInt64 {
    UInt64((seconds * nanosecondsPerSecond).rounded())
}

/// The sessions as cards standing in a row in 3D, turned at an angle like records on a shelf,
/// which turn past until the one asked for faces the person, then comes forward and opens.
@MainActor
final class SwitcherPanel {
    private let panel: KeyablePanel
    private let model = SwitcherModel()
    /// A beat per card, quick enough that several pass in about a second.
    private static let stepSeconds = 0.16
    private static let holdSeconds = 0.45

    private enum Timing {
        /// Lets the row fade in before it starts to turn.
        static let settleBeforeTurn: TimeInterval = 0.28
        /// Added to the turn's response so even a one card turn eases rather than snaps.
        static let turnBaseResponse = 0.35
        static let turnDamping = 0.82
        static let chooseResponse = 0.45
        static let chooseDamping = 0.7
        /// Long enough to see the chosen card come forward before the row leaves.
        static let chosenHold: TimeInterval = 0.38
        static let exitDuration: TimeInterval = 0.25
        /// Just past the exit animation, so the panel leaves only once it has faded.
        static let orderOutDelay: TimeInterval = 0.26
    }

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
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
    }

    /// Turns through the cards to the session asked for, and returns once it has come forward.
    func turn(to sessionId: String, among cards: [SessionCard]) async {
        guard let target = cards.firstIndex(where: { $0.sessionId == sessionId }), cards.count > 1,
              let screen = NSScreen.main
        else { return }
        model.cards = cards
        model.chosen = false
        // Starts across the row from the one asked for, so the turn has somewhere to travel.
        let start = target < cards.count / 2 ? cards.count - 1 : 0
        model.selected = Double(start)
        panel.setFrame(screen.frame, display: false)
        panel.contentView = NSHostingView(rootView: SwitcherView(model: model))
        panel.orderFrontRegardless()
        withAnimation(.easeOut(duration: Memnox.Motion.standard)) { model.shown = true }
        try? await Task.sleep(nanoseconds: nanoseconds(Timing.settleBeforeTurn))
        let steps = abs(target - start)
        withAnimation(.spring(response: Self.stepSeconds * Double(steps) + Timing.turnBaseResponse, dampingFraction: Timing.turnDamping)) {
            model.selected = Double(target)
        }
        try? await Task.sleep(nanoseconds: UInt64((Self.stepSeconds * Double(steps) + Self.holdSeconds) * nanosecondsPerSecond))
        withAnimation(.spring(response: Timing.chooseResponse, dampingFraction: Timing.chooseDamping)) { model.chosen = true }
        try? await Task.sleep(nanoseconds: nanoseconds(Timing.chosenHold))
        withAnimation(.easeIn(duration: Timing.exitDuration)) { model.shown = false }
        Task { [panel] in
            try? await Task.sleep(nanoseconds: nanoseconds(Timing.orderOutDelay))
            panel.orderOut(nil)
            panel.contentView = nil
        }
    }
}

private struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel

    private enum Layout {
        static let backdropOpacity = 0.38
        static let shownLift: CGFloat = -30
        static let hiddenDrop: CGFloat = 40
    }

    var body: some View {
        ZStack {
            // The rest of the screen falls back, so the row is the only thing to look at.
            Color.black.opacity(model.shown ? Layout.backdropOpacity : 0).ignoresSafeArea()
            ZStack {
                ForEach(Array(model.cards.enumerated()), id: \.element.id) { index, card in
                    let offset = Double(index) - model.selected
                    SessionTile(card: card, front: abs(offset) < frontReach)
                        .modifier(Shelf(offset: offset, chosen: model.chosen && abs(offset) < frontReach))
                }
            }
            .offset(y: model.shown ? Layout.shownLift : Layout.hiddenDrop)
            .opacity(model.shown ? 1 : 0)
        }
    }
}

/// Where a card stands on the shelf: the one in front faces the person, the rest turn away
/// at an angle and step back, and the chosen one comes forward out of the row.
private struct Shelf: ViewModifier {
    let offset: Double
    let chosen: Bool

    private enum Layout {
        static let turnDegrees = 52.0
        static let perspective: CGFloat = 0.55
        static let chosenScale = 1.18
        /// Cards further than this stop shrinking and dimming, so the far end of the row stays legible.
        static let farthestStep = 3.0
        static let shrinkPerStep = 0.1
        static let spacing = 150.0
        /// Extra room each side of the front card, so the turned ones clear it.
        static let sideGap = 70.0
        static let chosenLift: CGFloat = -20
        /// Past this a card is off the shelf and hidden.
        static let hiddenBeyond = 3.4
        static let chosenBrightness = 0.06
        static let dimPerStep = 0.08
    }

    func body(content: Content) -> some View {
        let side = max(-1, min(1, offset))
        let distance = abs(offset)
        content
            .rotation3DEffect(.degrees(-side * Layout.turnDegrees), axis: (x: 0, y: 1, z: 0), perspective: Layout.perspective)
            .scaleEffect(chosen ? Layout.chosenScale : 1 - min(distance, Layout.farthestStep) * Layout.shrinkPerStep)
            .offset(x: offset * Layout.spacing + side * Layout.sideGap, y: chosen ? Layout.chosenLift : 0)
            .opacity(distance > Layout.hiddenBeyond ? 0 : 1)
            .brightness(chosen ? Layout.chosenBrightness : -min(distance, Layout.farthestStep) * Layout.dimPerStep)
            .zIndex(-distance)
    }
}

/// One session as a card: where it runs, who it is, what it is on and how it stands.
private struct SessionTile: View {
    let card: SessionCard
    let front: Bool

    private enum Layout {
        static let reflectionOpacity = 0.16
        static let reflectionHeight: CGFloat = 90
        static let reflectionGap: CGFloat = 4
        static let nameSize: CGFloat = 20
        static let taskOpacity = 0.9
        static let taskLineLimit = 4
        static let dotSize: CGFloat = 7
        static let padding: CGFloat = 18
        static let width: CGFloat = 240
        static let height: CGFloat = 300
        static let logoSize: CGFloat = 36
        /// The card in front takes its status colour on its edge, the one cue that marks it apart.
        static let frontEdgeOpacity = 0.8
        static let shadowOpacity = 0.4
        static let frontShadowRadius: CGFloat = 22
        static let shadowRadius: CGFloat = 14
        static let shadowDrop: CGFloat = 10
    }

    var body: some View {
        VStack(spacing: 0) {
            face
            // The card reflected in the glass it stands on.
            face
                .scaleEffect(x: 1, y: -1, anchor: .center)
                .opacity(Layout.reflectionOpacity)
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .center))
                .frame(height: Layout.reflectionHeight, alignment: .top)
                .clipped()
                .offset(y: Layout.reflectionGap)
        }
    }

    private var face: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
            HStack(spacing: Memnox.Spacing.regular) {
                BrandLogo(agent: card.agent, name: card.agentName, size: Layout.logoSize)
                VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                    Text(card.agentName)
                        .font(Memnox.display(Layout.nameSize))
                        .foregroundStyle(Memnox.Palette.foreground)
                    Text(card.runningIn ?? "Somewhere unknown")
                        .font(Memnox.sans(Memnox.TextSize.caption))
                        .foregroundStyle(Memnox.Palette.muted)
                }
            }
            Text(card.task ?? "No task recorded")
                .font(Memnox.sans(Memnox.TextSize.body))
                .foregroundStyle(Memnox.Palette.foreground.opacity(Layout.taskOpacity))
                .lineLimit(Layout.taskLineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            HStack {
                Circle().fill(colour).frame(width: Layout.dotSize, height: Layout.dotSize)
                Text(label).font(Memnox.sans(Memnox.TextSize.caption, .medium)).foregroundStyle(colour)
                Spacer()
                if let repository = card.repository {
                    Text(repository).font(Memnox.sans(Memnox.TextSize.caption)).foregroundStyle(Memnox.Palette.muted).lineLimit(1)
                }
            }
        }
        .padding(Layout.padding)
        .frame(width: Layout.width, height: Layout.height)
        .surface(accent: front ? colour.opacity(Layout.frontEdgeOpacity) : nil)
        .shadow(
            color: .black.opacity(Layout.shadowOpacity),
            radius: front ? Layout.frontShadowRadius : Layout.shadowRadius,
            y: Layout.shadowDrop
        )
    }

    private var label: String { card.status.label }

    private var colour: Color { card.status.tint }
}
