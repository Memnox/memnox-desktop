import AppKit
import MemnoxVoiceCore
import SwiftUI

/// How quickly a control lights under the pointer.
private let hoverDuration: TimeInterval = 0.12

/// A button on a card or the live window: a generous target, a pointing hand, and a lift on hover,
/// so it is plain it can be clicked and plain when it was.
struct CardButton: View {
    let title: String
    let icon: String
    let primary: Bool
    let action: () -> Void
    @State private var hovered = false

    private enum Layout {
        static let textSize: CGFloat = 12.5
        static let horizontalPadding: CGFloat = 14
        static let primaryResting = 0.92
        static let plainHovered = 0.15
        static let plainResting = 0.09
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(Memnox.sans(Layout.textSize, .medium))
                .foregroundStyle(primary ? IslandPalette.primaryText : Color.white)
                .padding(.horizontal, Layout.horizontalPadding)
                .padding(.vertical, Memnox.Spacing.medium)
                .background(Capsule().fill(fill))
                .contentShape(Capsule())
        }
        .buttonStyle(PressDown())
        .onHover { inside in
            withAnimation(.easeOut(duration: hoverDuration)) { hovered = inside }
            pointing(inside)
        }
    }

    private var fill: Color {
        primary
            ? IslandPalette.primaryFill.opacity(hovered ? 1 : Layout.primaryResting)
            : Color.white.opacity(hovered ? Layout.plainHovered : Layout.plainResting)
    }
}

/// The close cross, with a target a finger's width across rather than the glyph's.
struct CloseButton: View {
    let action: () -> Void
    @State private var hovered = false

    private enum Layout {
        static let symbol = "xmark"
        /// A finger's width across, wider than the glyph.
        static let target: CGFloat = 26
        static let hoveredFill = 0.12
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: Layout.symbol)
                .font(.system(size: Memnox.TextSize.caption, weight: .semibold))
                .foregroundStyle(hovered ? Memnox.Palette.foreground : Memnox.Palette.muted)
                .frame(width: Layout.target, height: Layout.target)
                .background(Circle().fill(Color.white.opacity(hovered ? Layout.hoveredFill : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(PressDown())
        .onHover { inside in
            withAnimation(.easeOut(duration: hoverDuration)) { hovered = inside }
            pointing(inside)
        }
    }
}

/// Sinks a little while held, which is the only sign a borderless panel gives that a click landed.
struct PressDown: ButtonStyle {
    private static let pressedScale: CGFloat = 0.94
    private static let springResponse = 0.2
    private static let springDamping = 0.6

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Self.pressedScale : 1)
            .animation(.spring(response: Self.springResponse, dampingFraction: Self.springDamping), value: configuration.isPressed)
    }
}

/// The pointing hand over anything clickable, set and undone in pairs so it never sticks.
@MainActor
func pointing(_ inside: Bool) {
    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
}
