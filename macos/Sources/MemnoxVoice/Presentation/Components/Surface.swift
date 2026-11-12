import AppKit
import SwiftUI

/// The one flat card every window and panel stands its content on, the console's: white or the dark card, radius 12,
/// read by its border.
struct Surface: ViewModifier {
    /// An edge in a colour of its own, for a card that must be found first, such as a call waiting.
    var accent: Color?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Memnox.Console.cardRadius, style: .continuous)
        content
            .background(shape.fill(Memnox.Console.card))
            .overlay(shape.strokeBorder(accent ?? Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
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
    func surface(accent: Color? = nil) -> some View {
        modifier(Surface(accent: accent))
    }
}
