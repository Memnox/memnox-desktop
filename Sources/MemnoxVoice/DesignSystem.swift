import AppKit
import SwiftUI

/// The Memnox design system on the Mac: the tokens `memnox-client/packages/ui` defines for the
/// dark theme, so the app and the console read as one product. Change them there first.
enum Memnox {
    enum Palette {
        static let background = Color(hex: 0x030303)
        static let card = Color(hex: 0x0F0F0F)
        static let secondary = Color(hex: 0x1D1D1D)
        static let border = Color(hex: 0x313131)
        static let foreground = Color(hex: 0xFDFDFD)
        static let muted = Color(hex: 0xADADAD)
        static let primary = Color(hex: 0x1E86EE)
        static let ring = Color(hex: 0x1E86EE).opacity(0.45)
        static let success = Color(hex: 0x37CD8F)
        static let warm = Color(hex: 0xDD815D)
        static let destructive = Color(hex: 0xE31957)
        /// The orb's own two blues, the primary and a lighter sky over it, for the small mark in the header.
        static let sky = Color(hex: 0x8CC8FF)
        static let deep = Color(hex: 0x1E86EE)
    }

    /// `--radius`, 0.375rem.
    static let radius: CGFloat = 6
    static let cardRadius: CGFloat = 12
    /// A keycap's corners, tighter than a button's so it reads as a key.
    static let keycapRadius: CGFloat = 4

    /// Type sizes named for their role, so the same kind of text is the same size on every surface.
    enum TextSize {
        static let micro: CGFloat = 10
        static let caption: CGFloat = 11
        static let footnote: CGFloat = 12
        static let body: CGFloat = 13
        static let callout: CGFloat = 14
        static let headline: CGFloat = 15
        static let title: CGFloat = 17
    }

    /// The spacing scale the surfaces share, for stacks and padding alike.
    enum Spacing {
        static let xxSmall: CGFloat = 2
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 6
        static let medium: CGFloat = 8
        static let regular: CGFloat = 10
        static let large: CGFloat = 12
        static let xLarge: CGFloat = 16
        static let xxLarge: CGFloat = 20
    }

    /// Line widths for borders and rings.
    enum Stroke {
        /// The one point border every card and button has.
        static let hairline: CGFloat = 1
        /// A ring that marks the thing in front.
        static let emphasis: CGFloat = 1.5
    }

    /// How strongly white shows over the dark glass, by role, so text and fills keep one hierarchy.
    enum Ink {
        static let primary = 0.92
        static let secondary = 0.5
        static let tertiary = 0.45
        static let fill = 0.08
        static let faintFill = 0.06
        static let edge = 0.14
    }

    /// Animation lengths the surfaces share, so things that move together move at one pace.
    enum Motion {
        static let quick: TimeInterval = 0.2
        static let standard: TimeInterval = 0.3
        static let slow: TimeInterval = 0.5
    }

    /// The installed font families and faces, checked by name because a missing one falls back to the system face.
    private enum FontName {
        static let interFamily = "Inter"
        static let instrumentSerifFamily = "Instrument Serif"
        static let interRegular = "Inter-Regular"
        static let interSemiBold = "Inter-SemiBold"
    }

    /// Inter for the interface, as the console uses it, and the system face where it is not installed.
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        installed(FontName.interFamily)
            ? .custom(FontName.interFamily, size: size).weight(weight)
            : .system(size: size, weight: weight)
    }

    /// Instrument Serif for display lines, as the console's headings, or the system serif.
    static func display(_ size: CGFloat) -> Font {
        installed(FontName.instrumentSerifFamily)
            ? .custom(FontName.instrumentSerifFamily, size: size)
            : .system(size: size, design: .serif)
    }

    /// Inter for AppKit drawing, such as the pill under the orb, or the system face.
    static func nsSans(_ size: CGFloat, semibold: Bool = false) -> NSFont {
        NSFont(name: semibold ? FontName.interSemiBold : FontName.interRegular, size: size)
            ?? .systemFont(ofSize: size, weight: semibold ? .semibold : .regular)
    }

    private static func installed(_ family: String) -> Bool {
        NSFontManager.shared.availableFontFamilies.contains(family)
    }
}

extension Color {
    /// A colour from a 0xRRGGBB value, the way the console's tokens write it.
    init(hex: UInt32) {
        self.init(
            red: Self.channel(hex, shift: Self.redShift),
            green: Self.channel(hex, shift: Self.greenShift),
            blue: Self.channel(hex, shift: Self.blueShift)
        )
    }

    private static let redShift: UInt32 = 16
    private static let greenShift: UInt32 = 8
    private static let blueShift: UInt32 = 0
    private static let channelMask: UInt32 = 0xFF

    private static func channel(_ hex: UInt32, shift: UInt32) -> Double {
        Double((hex >> shift) & channelMask) / Double(channelMask)
    }
}

/// The glass behind every Memnox surface: Liquid Glass from macOS 26, the frosted material before it.
struct Glass: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> NSView {
        glassView(cornerRadius: cornerRadius, material: material)
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

/// A faint blue in the glass, so every surface reads as Memnox rather than as a system panel.
let glassTint = NSColor(Memnox.Palette.primary).withAlphaComponent(glassTintAlpha)

/// Faint enough that the desktop still shows through the glass.
private let glassTintAlpha = 0.10

/// One pane of glass, rounded to `cornerRadius`, in whichever kind this Mac has.
func glassView(cornerRadius: CGFloat, material: NSVisualEffectView.Material = .hudWindow) -> NSView {
    // Liquid Glass arrived in macOS 26; #available only takes a literal version.
    if #available(macOS 26, *) {
        let glass = NSGlassEffectView()
        glass.cornerRadius = cornerRadius
        glass.tintColor = glassTint
        glass.appearance = NSAppearance(named: .darkAqua)
        return glass
    }
    let view = NSVisualEffectView()
    view.material = material
    view.blendingMode = .behindWindow
    view.state = .active
    view.appearance = NSAppearance(named: .darkAqua)
    view.wantsLayer = true
    view.layer?.cornerRadius = cornerRadius
    view.layer?.masksToBounds = true
    // The edge light glass has, which the frosted material alone does not draw.
    view.layer?.borderWidth = Memnox.Stroke.hairline
    view.layer?.borderColor = NSColor.white.withAlphaComponent(Memnox.Ink.edge).cgColor
    return view
}

/// The filled blue button, for the one thing a screen asks you to do.
struct PrimaryButton: ButtonStyle {
    /// Dimmed this far while pressed, so the press is felt without the button disappearing.
    private static let pressedOpacity = 0.8

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Memnox.sans(Memnox.TextSize.body, .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, Memnox.Spacing.xLarge)
            .padding(.vertical, Memnox.Spacing.medium)
            .background(
                RoundedRectangle(cornerRadius: Memnox.radius)
                    .fill(Memnox.Palette.primary.opacity(configuration.isPressed ? Self.pressedOpacity : 1))
            )
    }
}

/// The quiet button: a border and no fill, for everything that is not the main action.
struct QuietButton: ButtonStyle {
    /// The fill darkens when pressed and stays half seen at rest, so it never competes with the primary button.
    private static let pressedFillOpacity = 0.9
    private static let restingFillOpacity = 0.55

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Memnox.sans(Memnox.TextSize.footnote, .medium))
            .foregroundStyle(Memnox.Palette.foreground)
            .padding(.horizontal, Memnox.Spacing.large)
            .padding(.vertical, Memnox.Spacing.small)
            .background(
                RoundedRectangle(cornerRadius: Memnox.radius)
                    .fill(Memnox.Palette.secondary.opacity(configuration.isPressed ? Self.pressedFillOpacity : Self.restingFillOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Memnox.radius)
                    .strokeBorder(Memnox.Palette.border, lineWidth: Memnox.Stroke.hairline)
            )
    }
}

/// A key as it is printed on the keyboard, for ⌥ Space.
struct Keycap: View {
    let label: String

    /// A key's own proportions, a little wider than tall like the printed legend on a real key.
    private static let horizontalPadding: CGFloat = 7
    private static let verticalPadding: CGFloat = 3

    var body: some View {
        Text(label)
            .font(Memnox.sans(Memnox.TextSize.caption, .semibold))
            .foregroundStyle(Memnox.Palette.foreground)
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, Self.verticalPadding)
            .background(RoundedRectangle(cornerRadius: Memnox.keycapRadius).fill(Memnox.Palette.secondary))
            .overlay(RoundedRectangle(cornerRadius: Memnox.keycapRadius).strokeBorder(Memnox.Palette.border, lineWidth: Memnox.Stroke.hairline))
    }
}

/// A card of dark glass: the desktop shows faintly through, lit along its top edge like a pane.
struct GlassCard: View {
    var cornerRadius: CGFloat

    /// A whisper of white over the material, and an edge brighter at the top than the bottom, as light falls on a pane.
    private static let sheenOpacity = 0.04
    private static let topEdgeOpacity = 0.18
    private static let bottomEdgeOpacity = 0.05

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(Color.white.opacity(Self.sheenOpacity)))
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(Self.topEdgeOpacity), Color.white.opacity(Self.bottomEdgeOpacity)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: Memnox.Stroke.hairline
                )
            )
            .environment(\.colorScheme, .dark)
    }
}

/// The Memnox mark from the console, white for the dark surfaces here and a template for the
/// menu bar. Copied into the app by `scripts/bundle.sh`; the orb's dot stands in without it.
enum MemnoxLogo {
    /// The image names `scripts/bundle.sh` copies into the app's resources.
    private static let whiteResource = "memnox-mark-white"
    private static let templateResource = "memnox-mark-template"
    /// The size macOS draws a menu bar icon at.
    private static let menuBarSide: CGFloat = 18

    static var white: NSImage? { Bundle.main.image(forResource: whiteResource) }

    /// Drawn by macOS in the menu bar's own colour, light or dark, like every other icon there.
    static var menuBar: NSImage? {
        guard let image = Bundle.main.image(forResource: templateResource) else { return nil }
        image.size = NSSize(width: menuBarSide, height: menuBarSide)
        image.isTemplate = true
        return image
    }
}

/// The mark with a soft blue glow behind it, so it sits on the glass like the orb does.
struct LogoMark: View {
    var size: CGFloat

    /// The glow reaches past the mark on every side, and fades out before its own edge.
    private static let glowScale: CGFloat = 1.6
    private static let glowFadeScale: CGFloat = 0.8
    private static let glowOpacity = 0.55
    /// Where the glow's gradient starts, a point from the centre so it has no hard dot.
    private static let glowStartRadius: CGFloat = 1
    /// The stand in dot is smaller than the mark so it does not read as a logo of its own.
    private static let fallbackScale: CGFloat = 0.6

    var body: some View {
        let glowSide = size * Self.glowScale
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Memnox.Palette.deep.opacity(Self.glowOpacity), .clear],
                    center: .center,
                    startRadius: Self.glowStartRadius,
                    endRadius: size * Self.glowFadeScale
                ))
                .frame(width: glowSide, height: glowSide)
            if let logo = MemnoxLogo.white {
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size, height: size)
            } else {
                Circle()
                    .fill(LinearGradient(colors: [Memnox.Palette.sky, Memnox.Palette.deep], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: size * Self.fallbackScale, height: size * Self.fallbackScale)
            }
        }
        .frame(width: glowSide, height: glowSide)
    }
}
