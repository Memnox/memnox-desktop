import AppKit
import SwiftUI

/// The one flat card every window and panel stands its content on, in Vorssaint's card: one step off the page,
/// rounded, and on a floating panel a hairline rim. A Settings page drops the rim, as Vorssaint's pages do.
struct Surface: ViewModifier {
    var radius: CGFloat = SurfaceStyle.radius
    /// An edge in a colour of its own, for a card that must be found first, such as a call waiting.
    var accent: Color?
    @Environment(\.rimlessCards) private var rimless

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: rimless ? SettingsMetrics.cardRadius : radius, style: .continuous)
        content
            .background(shape.fill(rimless ? Memnox.Palette.card : Memnox.Palette.surface))
            .overlay {
                if let accent {
                    shape.strokeBorder(accent, lineWidth: Memnox.Stroke.hairline)
                } else if !rimless {
                    shape.strokeBorder(SurfaceStyle.border, lineWidth: SurfaceStyle.borderWidth)
                }
            }
    }
}

/// The surface's measurements, shared by every card that stands on one.
enum SurfaceStyle {
    static let radius: CGFloat = 16
    static let padding: CGFloat = 12
    static let borderWidth: CGFloat = 0.7
    /// Vorssaint's card outline, stronger when the Mac asks for more contrast, since that is who needs to see it.
    static var border: Color {
        let raised = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        return Memnox.ink(raised ? raisedBorderInk : borderInk)
    }

    private static let borderInk = 0.11
    private static let raisedBorderInk = 0.28
}

extension View {
    /// Sets the view on the shared flat surface, so every card outside the notch reads as the same material.
    func surface(radius: CGFloat = SurfaceStyle.radius, accent: Color? = nil) -> some View {
        modifier(Surface(radius: radius, accent: accent))
    }
}
