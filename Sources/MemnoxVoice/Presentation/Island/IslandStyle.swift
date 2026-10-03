import AppKit
import MemnoxVoiceCore
import SwiftUI

extension View {
    /// The content area of an open island: below the header, ten in from the other three sides.
    func islandContentInset(_ notch: NotchGeometry) -> some View {
        padding(.top, Island.top(notch))
            .padding([.horizontal, .bottom], Island.contentInset)
    }
}

extension Color {
    /// The colour lifted a quarter of the way to white, so a label reads on its own tint.
    var liftedTowardWhite: Color {
        let base = NSColor(self).usingColorSpace(.sRGB) ?? .white
        let lift = Self.liftTowardWhite
        return Color(
            red: base.redComponent + (1 - base.redComponent) * lift,
            green: base.greenComponent + (1 - base.greenComponent) * lift,
            blue: base.blueComponent + (1 - base.blueComponent) * lift
        )
    }

    /// A quarter of the way, which keeps the hue while lifting the label clear of its tint.
    private static let liftTowardWhite = 0.25
}

/// The SF Symbol for a step: what stopped it if something did, or else where it happened.
func stepIcon(_ step: SessionViewStep) -> String { stepSymbol(step).rawValue }

private func stepSymbol(_ step: SessionViewStep) -> StepSymbol {
    if step.refused == true { return .refused }
    if step.failed == true { return .failed }
    switch step.stepSurface {
    case .filesystem: return step.text.hasPrefix(readStepPrefix) ? .read : .written
    case .shell: return .shell
    case .git: return .git
    case .network: return .network
    case .mcp: return .mcp
    case .question, .config, nil: return .other
    }
}

/// The SF Symbols a step can be drawn with.
private enum StepSymbol: String {
    case refused = "hand.raised"
    case failed = "xmark.circle"
    case read = "doc.text"
    case written = "pencil"
    case shell = "apple.terminal"
    case git = "arrow.triangle.branch"
    case network = "globe"
    case mcp = "puzzlepiece"
    case other = "circle"
}

/// How the runtime starts a filesystem step that only read, which earns a page rather than a pencil.
private let readStepPrefix = "Read"

/// A refused step in amber, a failed one in red, and the current one brighter than the rest.
func stepTint(_ step: SessionViewStep, current: Bool) -> Color {
    if step.refused == true { return IslandPalette.amber }
    if step.failed == true { return IslandPalette.red }
    return current ? Color.white : IslandPalette.quiet
}

/// A pill button: white for the answer that lets something happen, a faint fill for the rest; it gives a little when pressed.
struct IslandButton: ButtonStyle {
    let primary: Bool

    private static let labelSize: CGFloat = 12.5
    private static let horizontalPadding: CGFloat = 14
    private static let verticalPadding: CGFloat = 7
    /// The faint fill behind a secondary button, a little stronger while it is held down.
    private static let restingFill = 0.09
    private static let pressedFill = 0.15

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Memnox.sans(Self.labelSize, .medium))
            .foregroundStyle(primary ? IslandPalette.primaryText : Color.white)
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, Self.verticalPadding)
            .background(Capsule().fill(primary ? IslandPalette.primaryFill : Color.white.opacity(configuration.isPressed ? Self.pressedFill : Self.restingFill)))
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(.spring(response: pressResponse, dampingFraction: pressDamping), value: configuration.isPressed)
    }
}

/// How far anything clickable gives when pressed, and the quick spring it gives and returns with.
private let pressedScale: CGFloat = 0.94
private let pressResponse = 0.2
private let pressDamping = 0.6

/// The press for anything clickable that is not a labelled button.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(.spring(response: pressResponse, dampingFraction: pressDamping), value: configuration.isPressed)
    }
}

/// The notch's own outline grown downward: square along the top, flowing out into the screen edge at
/// either side with a concave curve, and rounded at the bottom.
struct NotchShape: Shape {
    var flare: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(flare, bottomRadius) }
        set {
            flare = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let r = min(bottomRadius, max(0, (rect.height - flare) / 2), max(0, (rect.width - 2 * flare) / 2))
        let left = rect.minX + flare
        let right = rect.maxX - flare
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: left, y: rect.minY + flare), control: CGPoint(x: left, y: rect.minY))
        path.addLine(to: CGPoint(x: left, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: left + r, y: rect.maxY), control: CGPoint(x: left, y: rect.maxY))
        path.addLine(to: CGPoint(x: right - r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: right, y: rect.maxY - r), control: CGPoint(x: right, y: rect.maxY))
        path.addLine(to: CGPoint(x: right, y: rect.minY + flare))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: right, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
