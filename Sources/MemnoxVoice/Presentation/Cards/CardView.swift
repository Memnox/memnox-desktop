import AppKit
import MemnoxVoiceCore
import SwiftUI

struct CardView: View {
    let summary: SummaryCard
    let close: () -> Void
    /// Goes straight to the session's own window, where it is known.
    let open: (() -> Void)?
    /// Opens the live window on the session, in the middle of the screen.
    let watch: (() -> Void)?
    let hovering: (Bool) -> Void
    @StateObject private var entrance = CardEntrance()

    private enum Layout {
        static let logoSize: CGFloat = 16
        static let titleSize: CGFloat = 22
        static let titleLineLimit = 2
    }

    private enum Symbol {
        static let watch = "play.circle"
        static let open = "arrow.up.forward.app"
    }

    private var openLabel: String {
        guard let app = summary.host?.app else { return "Open session" }
        return "Open in \(app)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
            HStack(alignment: .firstTextBaseline) {
                LogoMark(size: Layout.logoSize)
                Text(summary.title)
                    .font(Memnox.display(Layout.titleSize))
                    .foregroundStyle(Memnox.Palette.foreground)
                    .lineLimit(Layout.titleLineLimit)
                Spacer()
                CloseButton(action: close)
            }
            MarkdownText(source: summary.text)
            if !summary.files.isEmpty { FileList(files: summary.files, counting: entrance.shown) }
            if let excerpt = summary.excerpt { CodeExcerpt(excerpt: excerpt) }
            if open != nil || watch != nil {
                HStack(spacing: Memnox.Spacing.medium) {
                    Spacer()
                    if let watch { CardButton(title: "Watch live", icon: Symbol.watch, primary: false, action: watch) }
                    if let open { CardButton(title: openLabel, icon: Symbol.open, primary: true, action: open) }
                }
            }
        }
        .modifier(CardFace(entrance: entrance, hovering: hovering))
    }
}

/// What a card sits on and how it moves, in the island's own language: solid black with a hairline
/// edge and a faint blue light rising from the bottom, settling into place with the island's spring.
/// It stays flat, so every button is drawn exactly where it takes a click.
struct CardFace: ViewModifier {
    @ObservedObject var entrance: CardEntrance
    let hovering: (Bool) -> Void

    private enum Layout {
        static let cornerRadius: CGFloat = 26
        /// The glow's centre sits below the card, so only its upper reach lights the bottom edge.
        static let glowCenter = UnitPoint(x: 0.5, y: 1.3)
        static let glowFacing = 0.26
        static let glowResting = 0.18
        static let edgeFacing = 0.12
        static let edgeResting = 0.06
        static let shadowOpacity = 0.5
        static let shadowRadius: CGFloat = 30
        static let shadowDrop: CGFloat = 12
        static let hoverDuration: TimeInterval = 0.25
        /// Before it swings in, the card sits a little small, raised and soft, so it settles into focus.
        static let restingScale: CGFloat = 0.96
        static let restingLift: CGFloat = -10
        static let restingBlur: CGFloat = 8
        /// The island's own spring.
        static let springResponse = 0.5
        static let springDamping = 0.72
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
        content
            .padding(Memnox.Spacing.xxLarge)
            .frame(width: CardPanel.width, alignment: .leading)
            .background(
                shape.fill(Color.black)
                    .overlay(
                        RadialGradient(
                            colors: [Memnox.Palette.primary.opacity(entrance.facing ? Layout.glowFacing : Layout.glowResting), .clear],
                            center: Layout.glowCenter,
                            startRadius: 0,
                            endRadius: CardPanel.width
                        )
                    )
                    .clipShape(shape)
            )
            .overlay(shape.strokeBorder(Color.white.opacity(entrance.facing ? Layout.edgeFacing : Layout.edgeResting), lineWidth: Memnox.Stroke.hairline))
            .shadow(color: .black.opacity(Layout.shadowOpacity), radius: Layout.shadowRadius, y: Layout.shadowDrop)
            .contentShape(shape)
            .onHover { inside in
                withAnimation(.easeOut(duration: Layout.hoverDuration)) { entrance.facing = inside }
                hovering(inside)
            }
            .scaleEffect(entrance.shown ? 1 : Layout.restingScale, anchor: .topLeading)
            .offset(y: entrance.shown ? 0 : Layout.restingLift)
            .blur(radius: entrance.shown ? 0 : Layout.restingBlur)
            .opacity(entrance.shown ? 1 : 0)
            .onAppear { withAnimation(.spring(response: Layout.springResponse, dampingFraction: Layout.springDamping)) { entrance.shown = true } }
    }
}
