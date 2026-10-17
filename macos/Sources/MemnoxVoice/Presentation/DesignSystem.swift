import AppKit
import SwiftUI

/// The Memnox design system on the Mac, set in the Mac's own neutral colours the way Vorssaint sets its windows: a
/// graphite page with no colour cast, cards one step lighter than it, and the system blue for what is chosen or on.
/// The ordinary windows follow the Appearance the person chose; the notch is pinned dark, as the hardware is.
enum Memnox {
    /// Sampled from Vorssaint's own Settings window, in the light and in the dark, so every value here is one it draws.
    enum Palette {
        /// The window behind the sidebar and the page.
        static let background = Color(light: 0xFAFAFA, dark: 0x1E1E1E)
        /// A card on the page, solid and with no rim, a step off the page as Vorssaint's are.
        static let card = Color(light: 0xF1F1F1, dark: 0x262626)
        /// A control set on a card: a button, a menu's pill. White in the light, a step up from the card in the dark.
        static let secondary = Color(light: 0xFFFFFF, dark: 0x383838)
        /// A control's hairline, which only the white controls of the light look need.
        static let controlEdge = Color(darkWhite: 0, lightBlack: 0.12)
        /// The rule between two rows of a card.
        static let border = Color(light: 0xD9D9D9, dark: 0x3B3B3B)
        static let foreground = Color(light: 0x222222, dark: 0xE1E1E1)
        static let muted = Color(light: 0x797979, dark: 0x9E9E9F)
        /// Text that is there but not asked about, such as a hint under a card or a control that cannot be used yet.
        static let faint = Color(light: 0xB2B2B2, dark: 0x5E5E5F)
        /// The colour text, symbols and hairlines are drawn in: white on the dark page, near black on the light one.
        static let ink = Color(light: 0x0D0D0D, dark: 0xFFFFFF)
        /// Vorssaint's blue, for what is chosen, switched on, or the one thing a page asks to be done.
        static let primary = Color(hex: 0x3B82F7)
        /// The status hues deepen on the light page, so a status said in words keeps 4.5 to 1 on white and on its own tint.
        static let success = Color(light: 0x1F7A35, dark: 0x30D158)
        static let warm = Color(light: 0xB25000, dark: 0xFF9F0A)
        static let destructive = Color(light: 0xC4001A, dark: 0xFF453A)
        /// The sidebar's own panel.
        static let surface = Color(light: 0xEDEDF0, dark: 0x28282B)
        /// A lit edge, which an unticked checkbox draws around itself.
        static let rim = Color(light: 0xFAFAFB, dark: 0x4B4B4D)
        /// The page panel's one even edge, a soft grey that sets it off the sidebar without lighting its top.
        static let panelEdge = Color(light: 0xD6D6DA, dark: 0x3A3A3D)
        /// Back and Forward's capsule and its edge.
        static let capsule = Color(light: 0xFFFFFF, dark: 0x262626)
        static let capsuleEdge = Color(light: 0xE0E0E0, dark: 0x3B3B3B)
        /// A row or a button under the pointer.
        static let hover = Color(darkWhite: 0.07, lightBlack: 0.05)
        /// The search field's fill, and its edge.
        static let field = Color(darkWhite: 0.16, lightBlack: 0.07)
        static let fieldEdge = Color(darkWhite: 0.08, lightBlack: 0.06)
        /// A key printed inside a shortcut's field.
        static let keycap = Color(light: 0xFFFFFF, dark: 0x454545)
        /// A shortcut's field, a text field, a disc or pill set on a card.
        static let raised = Color(light: 0xFFFFFF, dark: 0x2F2F2F)
        /// The history at the side of the screen, the island's own dark so the two read as one surface.
        static let panel = Color(light: 0xFFFFFF, dark: 0x141518)
        /// The orb's own two blues, the primary and a lighter sky over it; the sky deepens on white to stay readable.
        static let sky = Color(light: 0x1E6FD0, dark: 0x8CC8FF)
        static let deep = Color(hex: 0x1E86EE)
    }

    /// Ink at one of the `Ink` strengths. Dark text on white needs more than white on black to read as well, so the
    /// light side is stronger by a fixed share, which keeps secondary text above 4.5 to 1 on the page.
    static func ink(_ strength: Double) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return dark
                ? NSColor(white: 1, alpha: strength)
                : NSColor(white: Ink.lightInk, alpha: min(1, strength * Ink.lightBoost))
        })
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
        /// Strong enough that a line under a title reads as crisply as Vorssaint's grey, rather than as a blur.
        static let secondary = 0.62
        static let tertiary = 0.5
        static let fill = 0.08
        static let faintFill = 0.06
        static let edge = 0.14
        /// The rim of a card, enough to separate one dark surface from another.
        static let rim = 0.07
        /// How much stronger each strength is drawn on the light page.
        static let lightBoost = 1.35
        /// The near black of ink on the light page, as a white level.
        static let lightInk: CGFloat = 0.05
    }

    /// Animation lengths the surfaces share, so things that move together move at one pace.
    enum Motion {
        static let quick: TimeInterval = 0.2
        static let standard: TimeInterval = 0.3
        static let slow: TimeInterval = 0.5
    }

    /// The website's own faces: the system's SF Pro for text and headings, as `--font-sans` and `--font-display`
    /// resolve on a Mac, and DM Mono for commands, where it is installed.
    private enum FontName {
        static let monoFamily = "DM Mono"
    }

    /// SF Pro Text for the interface, as the website sets its text.
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// SF Pro Display for headings, as the website sets them; the system picks the display cut at large sizes.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }

    /// DM Mono for commands and codes, as the website sets them, or the system's monospaced face.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        installed(FontName.monoFamily)
            ? .custom(FontName.monoFamily, size: size).weight(weight)
            : .system(size: size, weight: weight, design: .monospaced)
    }

    /// SF Pro for AppKit drawing, such as the pill under the orb.
    static func nsSans(_ size: CGFloat, semibold: Bool = false) -> NSFont {
        .systemFont(ofSize: size, weight: semibold ? .semibold : .regular)
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

    /// White over the dark glass and black over the light, each at its own strength, so a fill takes on whatever tint
    /// the glass under it has.
    init(darkWhite: Double, lightBlack: Double) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1, alpha: darkWhite) : NSColor(white: 0, alpha: lightBlack)
        })
    }

    /// White over the dark glass at its strength, and a solid colour in the light, as Vorssaint's white controls are.
    init(darkWhite: Double, light: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1, alpha: darkWhite) : NSColor(Color(hex: light))
        })
    }

    /// One colour for each appearance, resolved by the system as the Mac switches between them.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            NSColor(Color(hex: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light))
        })
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
    /// Dark glass for the surfaces that stay dark in every look; false lets the glass follow its window's appearance.
    var alwaysDark = true

    func makeNSView(context: Context) -> NSView {
        glassView(cornerRadius: cornerRadius, material: material, alwaysDark: alwaysDark)
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

/// The window's own glass, the material a Mac window's sidebar or page is made of, following the window's look, so
/// the desktop shows through as it does in Finder and Vorssaint.
struct WindowGlass: NSViewRepresentable {
    var material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// A faint blue in the glass, so every surface reads as Memnox rather than as a system panel.
let glassTint = NSColor(Memnox.Palette.primary).withAlphaComponent(glassTintAlpha)

/// Faint enough that the desktop still shows through the glass.
private let glassTintAlpha = 0.10

/// One pane of glass, rounded to `cornerRadius`, in whichever kind this Mac has.
func glassView(cornerRadius: CGFloat, material: NSVisualEffectView.Material = .hudWindow, alwaysDark: Bool = true) -> NSView {
    let pinned = alwaysDark ? NSAppearance(named: .darkAqua) : nil
    // Liquid Glass arrived in macOS 26; #available only takes a literal version.
    if #available(macOS 26, *) {
        let glass = NSGlassEffectView()
        glass.cornerRadius = cornerRadius
        glass.tintColor = glassTint
        glass.appearance = pinned
        return glass
    }
    let view = FrostedGlass()
    view.material = material
    view.blendingMode = .behindWindow
    view.state = .active
    view.appearance = pinned
    view.wantsLayer = true
    view.layer?.cornerRadius = cornerRadius
    view.layer?.masksToBounds = true
    view.layer?.borderWidth = Memnox.Stroke.hairline
    view.drawEdge()
    return view
}

/// The frosted material before Liquid Glass, with the edge light glass has, which the material alone does not draw.
private final class FrostedGlass: NSVisualEffectView {
    // A layer colour is fixed when it is set, so the edge is drawn again whenever the appearance turns.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        drawEdge()
    }

    /// The edge in the label colour, white on dark glass and near black on light, resolved for this view's appearance.
    func drawEdge() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = NSColor.labelColor.withAlphaComponent(Memnox.Ink.edge).cgColor
        }
    }
}

/// The filled blue capsule, for the one thing a screen asks you to do, as Vorssaint's Try it.
struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        KitButton(kind: .primary).makeBody(configuration: configuration)
    }
}

/// The grey capsule, for everything that is not the main action, as Vorssaint's Reset and Send feedback.
struct QuietButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        KitButton(kind: .secondary).makeBody(configuration: configuration)
    }
}

/// A key as it is printed on the keyboard, as Vorssaint prints one inside a shortcut's field.
struct Keycap: View {
    let label: String

    private static let horizontalPadding: CGFloat = 6
    private static let minimumWidth: CGFloat = 18
    private static let height: CGFloat = 18

    var body: some View {
        Text(label)
            .font(.system(size: Memnox.TextSize.caption, weight: .medium))
            .foregroundStyle(Memnox.Palette.foreground)
            .padding(.horizontal, Self.horizontalPadding)
            .frame(minWidth: Self.minimumWidth, minHeight: Self.height)
            .background(RoundedRectangle(cornerRadius: Memnox.keycapRadius, style: .continuous).fill(Memnox.Palette.keycap))
            .overlay(RoundedRectangle(cornerRadius: Memnox.keycapRadius, style: .continuous)
                .strokeBorder(Memnox.Palette.controlEdge, lineWidth: Memnox.Stroke.hairline))
    }
}

/// A card of dark glass: the desktop shows faintly through, with one even hairline edge.
struct GlassCard: View {
    var cornerRadius: CGFloat

    /// A whisper of white over the material, and an edge faint enough to frame without drawing the eye.
    private static let sheenOpacity = 0.04
    private static let edgeOpacity = 0.12

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(Color.white.opacity(Self.sheenOpacity)))
            .overlay(shape.strokeBorder(Color.white.opacity(Self.edgeOpacity), lineWidth: Memnox.Stroke.hairline))
            .environment(\.colorScheme, .dark)
    }
}

/// The Memnox mark from the console, white for the dark surfaces here and a template for the
/// menu bar. Copied into the app by `scripts/bundle.sh`; the orb's dot stands in without it.
enum MemnoxLogo {
    /// The image names `scripts/bundle.sh` copies into the app's resources.
    private static let whiteResource = "memnox-mark-white"
    private static let templateResource = "memnox-mark-template"
    private static let wordmarkResource = "memnox-wordmark-template"
    /// The height macOS draws a menu bar icon at; the mark is wider than tall, so its width follows.
    private static let menuBarHeight: CGFloat = 13

    static var white: NSImage? { Bundle.main.image(forResource: whiteResource) }

    /// The name set in the brand's own letters, drawn in whatever ink the surface asks for.
    static var wordmark: NSImage? { Bundle.main.image(forResource: wordmarkResource) }

    /// Drawn by macOS in the menu bar's own colour, light or dark, like every other icon there.
    static var menuBar: NSImage? {
        guard let image = Bundle.main.image(forResource: templateResource), image.size.height > 0 else { return nil }
        image.size = NSSize(width: menuBarHeight * image.size.width / image.size.height, height: menuBarHeight)
        image.isTemplate = true
        return image
    }
}

/// The mark in flat ink, white on dark and near black on light, with no glow, so it sits on every surface the same way.
struct LogoMark: View {
    var size: CGFloat

    /// The stand in dot is smaller than the mark so it does not read as a logo of its own.
    private static let fallbackScale: CGFloat = 0.6

    var body: some View {
        Group {
            if let logo = MemnoxLogo.white {
                Image(nsImage: logo)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(Memnox.Palette.ink)
            } else {
                Circle()
                    .fill(Memnox.Palette.primary)
                    .frame(width: size * Self.fallbackScale, height: size * Self.fallbackScale)
            }
        }
        .frame(width: size, height: size)
    }
}

/// The wordmark in flat ink, for where the name is shown rather than said: the sidebar's top and the first screen.
struct Wordmark: View {
    var height: CGFloat

    var body: some View {
        if let image = MemnoxLogo.wordmark {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(Memnox.Palette.ink)
                .frame(height: height)
                .accessibilityLabel("Memnox")
        } else {
            Text("memnox")
                .font(Memnox.display(height, .bold))
                .foregroundStyle(Memnox.Palette.ink)
        }
    }
}
