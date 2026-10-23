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
            CardHeader(title: summary.title, subtitle: summary.host?.app, close: close) {
                LogoMark(size: FloatingCard.markSize)
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

/// What a card sits on and how it moves: the shared flat surface with a hairline edge that brightens
/// under the pointer, settling into place with the island's spring. It stays flat, so every button is
/// drawn exactly where it takes a click.
struct CardFace: ViewModifier {
    @ObservedObject var entrance: CardEntrance
    let hovering: (Bool) -> Void

    private enum Layout {
        /// The edge lifts a little under the pointer, so the card in hand reads apart from its neighbours.
        static let edgeFacing = 0.16
        static let edgeResting = 0.07
        /// The live window's corner, so a card and the live window sit side by side as one family.
        static let radius: CGFloat = 28
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
        let shape = RoundedRectangle(cornerRadius: Layout.radius, style: .continuous)
        content
            .padding(FloatingCard.padding)
            .frame(width: CardPanel.width, alignment: .leading)
            // The live window's own page and rim, so every window Memnox puts up reads as one family.
            .background(shape.fill(LiveStyle.page))
            .overlay(shape.strokeBorder(Memnox.ink(entrance.facing ? Layout.edgeFacing : Layout.edgeResting), lineWidth: Memnox.Stroke.hairline))
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
