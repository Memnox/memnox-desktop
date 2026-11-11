import AppKit
import SwiftUI

/// The Memnox design system on the Mac, the console's own: one palette, Inter for words, and the Memnox blue for what
/// is chosen or on. The ordinary windows follow the Appearance the person chose; the notch is pinned dark, as the
/// hardware is.
enum Memnox {
    /// Every surface of this app wears the Memnox Cloud console's palette, value for value from memnox-client's
    /// globals.css, so the window, the island, the menu, the cards and setup read as one product with the console: a
    /// neutral ground under bordered cards, its blue the one hue, and status in the console's pill colours.
    enum Console {
        static let background = Color(light: 0xFBFBFB, dark: 0x030303)
        /// The sidebar sits flat on the ground, read by its border rather than a fill.
        static let surface = background
        static let card = Color(light: 0xFFFFFF, dark: 0x0F0F0F)
        static let secondary = card
        static let field = card
        static let raised = card
        static let panel = card
        static let capsule = card
        static let border = Color(light: 0xE2E2E2, dark: 0x313131)
        static let controlEdge = border
        static let panelEdge = border
        static let fieldEdge = border
        static let capsuleEdge = border
        static let foreground = Color(light: 0x0F0F0F, dark: 0xFDFDFD)
        static let ink = foreground
        static let muted = Color(light: 0x333333, dark: 0xADADAD)
        static let faint = Color(light: 0x8A8A8A, dark: 0x6B6B6B)
        static let hover = Color(light: 0xF2F2F2, dark: 0x191919)
        /// The row that is chosen, a step past the hover so the two never read as one.
        static let active = Color(light: 0xEAEAEA, dark: 0x1D1D1D)
        static let keycap = hover
        static let rim = card
        static let primary = Color(hex: 0x1E86EE)
        static let deep = primary
        static let sky = Color(light: 0x1E86EE, dark: 0x3D97F3)
        /// The soft ring a focused field or button wears outside its border.
        static let ring = Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(Color(hex: 0x1E86EE)).withAlphaComponent(dark ? Ring.dark : Ring.light)
        })
        /// A switch's knob while on: white in the light, a tint of the blue in the dark.
        static let switchKnob = Color(light: 0xFFFFFF, dark: 0x9CD1FD)
        static let success = Color(hex: 0x37CD8F)
        static let warm = Color(hex: 0xDD815D)
        static let destructive = Color(hex: 0xE31957)
        /// The console's sixth chart hue, which the memory map gives a restatement's line.
        static let violet = Color(light: 0x7C5CF0, dark: 0xA78BFA)

        private enum Ring {
            static let light = 0.35
            static let dark = 0.45
        }

        /// The memory brain's colours: one hue to each source group, bright enough to glow on the console's dark ground
        /// and far enough apart on the wheel that eight read apart, and the grey of the brain's outline.
        enum Brain {
            /// The console's dark ground and its dark ink, card and border, fixed so the brain is drawn on the dark
            /// console in either appearance.
            static let ground = Color(hex: 0x030303)
            static let ink = Color(hex: 0xFDFDFD)
            static let quiet = Color(hex: 0xADADAD)
            static let faint = Color(hex: 0x6B6B6B)
            static let card = Color(hex: 0x0F0F0F)
            static let edge = Color(hex: 0x313131)
            static let outline = Color(hex: 0x8A8F98)
            static let notes = Color(hex: 0x4C8DFF)
            static let instructions = Color(hex: 0xF5C542)
            static let servers = Color(hex: 0x2DD4BF)
            static let conversations = Color(hex: 0xFF8A3D)
            static let projects = Color(hex: 0x4ADE80)
            static let apps = Color(hex: 0xF472B6)
            static let team = Color(hex: 0xA78BFA)
            static let unsourced = Color(hex: 0x9CA3AF)
            /// The backing behind a name on the brain, dark enough that white reads over any dot.
            static let labelBacking = Color(hex: 0x05070C)
            /// The headline's two lines and the stats' numerals, sized past the console's page title.
            static let headline: CGFloat = 34
            static let numeral: CGFloat = 26
            /// The mono overlines and captions, the console's smallest step and one under it.
            static let overline: CGFloat = 11
            static let caption: CGFloat = 10
        }

        /// The console's ink at one of the `Ink` strengths, near black on the light ground and near white on the dark.
        static func ink(_ strength: Double) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return NSColor(Color(hex: dark ? Hex.lightInk : Hex.darkInk)).withAlphaComponent(min(1, strength))
            })
        }

        private enum Hex {
            static let darkInk: UInt32 = 0x0F0F0F
            static let lightInk: UInt32 = 0xFDFDFD
        }

        /// Two shapes, as the console folds them: 6 for controls and tiles, 12 for cards and panels.
        static let controlRadius: CGFloat = 6
        static let cardRadius: CGFloat = 12
        /// A button, a select and a chip, as the console sizes them at their small size.
        static let controlHeight: CGFloat = 32
        /// A text field, a little taller than a button as the console's are.
        static let fieldHeight: CGFloat = 36
        /// The soft ring's width outside a focused field.
        static let ringWidth: CGFloat = 3
        /// A panel lifted over the page: a dialog, the palette, a floating inspector.
        static let liftShadow = 0.18
        static let liftRadius: CGFloat = 30
        static let liftDrop: CGFloat = 12

        /// The console's type steps: label 11, meta 12, body-sm 13, a section's heading 16 and a page's title 24.
        enum TextSize {
            static let label: CGFloat = 11
            static let meta: CGFloat = 12
            static let bodySmall: CGFloat = 13
            static let base: CGFloat = 16
            static let large: CGFloat = 18
            static let title: CGFloat = 24
        }

        /// The console draws its titles one step tight, since Inter is drawn loose for the web.
        static let titleTracking: CGFloat = -0.48
        /// An uppercase heading is spaced out, as the console's group headings are.
        static let headingTracking: CGFloat = 1.98

        /// Inter, as the console sets everything; the system face where the bundled Inter could not be registered.
        static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
            BundledFonts.inter ? .custom(BundledFonts.interFamily, size: size).weight(weight) : .system(size: size, weight: weight)
        }

        /// A real monospace, kept for code and raw TOML: DM Mono where it was registered, else the system's own.
        static func code(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
            BundledFonts.dmMono ? .custom(BundledFonts.monoFamily, size: size).weight(weight) : .system(size: size, weight: weight, design: .monospaced)
        }
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

    private static func installed(_ family: String) -> Bool {
        NSFontManager.shared.availableFontFamilies.contains(family)
    }
}

/// Inter and DM Mono, bundled under the OFL and registered with this process the first time a font asks, so nothing has
/// to be installed on the Mac. `scripts/bundle.sh` copies them into the app; a build run from the package has none, and
/// the window falls back to the system face rather than failing.
enum BundledFonts {
    static let interFamily = "Inter"
    static let monoFamily = "DM Mono"
    private static let folder = "Fonts"
    /// The Latin cut only: the extended one carries the same names and CoreText refuses the second registration.
    private static let interFile = "inter-latin-opsz-normal"
    private static let monoFiles = ["dm-mono-latin-400-normal", "dm-mono-latin-500-normal"]
    private static let kind = "woff2"

    static let inter: Bool = register([interFile]) || installed(interFamily)
    static let dmMono: Bool = register(monoFiles) || installed(monoFamily)

    private static func register(_ names: [String]) -> Bool {
        let urls = names.compactMap { Bundle.main.url(forResource: $0, withExtension: kind, subdirectory: folder) }
        guard urls.count == names.count else { return false }
        var failed = false
        for url in urls {
            var error: Unmanaged<CFError>?
            // Already registered by an earlier call counts as there, since the face is usable either way.
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error), let error {
                let code = CFErrorGetCode(error.takeRetainedValue())
                if code != CTFontManagerError.alreadyRegistered.rawValue { failed = true }
            }
        }
        return !failed
    }

    private static func installed(_ family: String) -> Bool {
        NSFontManager.shared.availableFontFamilies.contains(family)
    }
}

extension View {
    /// Wears the console's type and tint from here down: the Memnox window, its popped out details and its sheets.
    func consoleLook() -> some View {
        font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
            .tint(Memnox.Console.primary)
    }
}

/// The tokens the shared controls pick from, the console's on every surface.
struct LookTokens {
    let background: Color
    let card: Color
    let secondary: Color
    let controlEdge: Color
    let border: Color
    let panelEdge: Color
    let foreground: Color
    let muted: Color
    let faint: Color
    let hover: Color
    let active: Color
    let field: Color
    let fieldEdge: Color
    let raised: Color
    let keycap: Color
    let rim: Color
    let primary: Color

    /// The one set every surface draws with, the console's.
    static let console = LookTokens(
        background: Memnox.Console.background, card: Memnox.Console.card, secondary: Memnox.Console.secondary,
        controlEdge: Memnox.Console.controlEdge, border: Memnox.Console.border, panelEdge: Memnox.Console.panelEdge,
        foreground: Memnox.Console.foreground, muted: Memnox.Console.muted, faint: Memnox.Console.faint,
        hover: Memnox.Console.hover, active: Memnox.Console.active, field: Memnox.Console.field,
        fieldEdge: Memnox.Console.fieldEdge, raised: Memnox.Console.raised, keycap: Memnox.Console.keycap,
        rim: Memnox.Console.border, primary: Memnox.Console.primary
    )
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
let glassTint = NSColor(Memnox.Console.primary).withAlphaComponent(glassTintAlpha)

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
        let tokens = LookTokens.console
        let shape = RoundedRectangle(cornerRadius: Memnox.Console.controlRadius, style: .continuous)
        Text(label)
            .font(Memnox.Console.sans(Memnox.TextSize.caption, .medium))
            .foregroundStyle(tokens.muted)
            .padding(.horizontal, Self.horizontalPadding)
            .frame(minWidth: Self.minimumWidth, minHeight: Self.height)
            .background(shape.fill(tokens.keycap))
            .overlay(shape.strokeBorder(tokens.controlEdge, lineWidth: Memnox.Stroke.hairline))
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
                    .foregroundStyle(Memnox.Console.ink)
            } else {
                Circle()
                    .fill(Memnox.Console.primary)
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
                .foregroundStyle(Memnox.Console.ink)
                .frame(height: height)
                .accessibilityLabel("Memnox")
        } else {
            Text("memnox")
                .font(Memnox.display(height, .bold))
                .foregroundStyle(Memnox.Console.ink)
        }
    }
}
