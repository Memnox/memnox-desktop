import SwiftUI

/// The one flat card every window and panel stands its content on: one step off the page in either appearance,
/// rounded, with a hairline rim. Only the notch's own cards carry a glow; everything else is this.
struct Surface: ViewModifier {
    var radius: CGFloat = SurfaceStyle.radius
    /// An edge in a colour of its own, for a card that must be found first, such as a call waiting.
    var accent: Color?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(shape.fill(Memnox.Palette.surface))
            .overlay(shape.strokeBorder(accent ?? Memnox.ink(Memnox.Ink.rim), lineWidth: Memnox.Stroke.hairline))
    }
}

/// The surface's measurements, shared by every card that stands on one.
enum SurfaceStyle {
    static let radius: CGFloat = 14
    static let padding: CGFloat = 12
}

extension View {
    /// Sets the view on the shared flat surface, so every card outside the notch reads as the same material.
    func surface(radius: CGFloat = SurfaceStyle.radius, accent: Color? = nil) -> some View {
        modifier(Surface(radius: radius, accent: accent))
    }
}
