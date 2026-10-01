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

    /// Inter for the interface, as the console uses it, and the system face where it is not installed.
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        installed("Inter") ? .custom("Inter", size: size).weight(weight) : .system(size: size, weight: weight)
    }

    /// Instrument Serif for display lines, as the console's headings, or the system serif.
    static func display(_ size: CGFloat) -> Font {
        installed("Instrument Serif") ? .custom("Instrument Serif", size: size) : .system(size: size, design: .serif)
    }

    /// Inter for AppKit drawing, such as the pill under the orb, or the system face.
    static func nsSans(_ size: CGFloat, semibold: Bool = false) -> NSFont {
        NSFont(name: semibold ? "Inter-SemiBold" : "Inter-Regular", size: size)
            ?? .systemFont(ofSize: size, weight: semibold ? .semibold : .regular)
    }

    private static func installed(_ family: String) -> Bool {
        NSFontManager.shared.availableFontFamilies.contains(family)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
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
let glassTint = NSColor(srgbRed: 0x1E / 255, green: 0x86 / 255, blue: 0xEE / 255, alpha: 0.10)

/// One pane of glass, rounded to `cornerRadius`, in whichever kind this Mac has.
func glassView(cornerRadius: CGFloat, material: NSVisualEffectView.Material = .hudWindow) -> NSView {
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
    view.layer?.borderWidth = 1
    view.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
    return view
}

/// The filled blue button, for the one thing a screen asks you to do.
struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Memnox.sans(13, .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: Memnox.radius)
                    .fill(Memnox.Palette.primary.opacity(configuration.isPressed ? 0.8 : 1))
            )
    }
}

/// The quiet button: a border and no fill, for everything that is not the main action.
struct QuietButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Memnox.sans(12, .medium))
            .foregroundStyle(Memnox.Palette.foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Memnox.radius)
                    .fill(Memnox.Palette.secondary.opacity(configuration.isPressed ? 0.9 : 0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Memnox.radius)
                    .strokeBorder(Memnox.Palette.border, lineWidth: 1)
            )
    }
}

/// A key as it is printed on the keyboard, for ⌥ Space.
struct Keycap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(Memnox.sans(11, .semibold))
            .foregroundStyle(Memnox.Palette.foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4).fill(Memnox.Palette.secondary))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Memnox.Palette.border, lineWidth: 1))
    }
}
