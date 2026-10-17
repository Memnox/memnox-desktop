import AppKit

/// Light, Dark or the Mac's own setting, for every Memnox window at once. The notch island is the one surface that
/// ignores it, because it grows out of the black hardware notch and is pinned dark in `IslandPanel`.
enum Appearance: String, CaseIterable {
    case system
    case light
    case dark

    /// The defaults key the choice is remembered under.
    static let key = "appearance"

    /// The order the picker shows them in, the two fixed looks before the one that follows the Mac.
    static let picked: [Appearance] = [.light, .dark, .system]

    /// The one saved, or System when nothing or something unknown was saved.
    static var chosen: Appearance {
        UserDefaults.standard.string(forKey: key).flatMap(Appearance.init(rawValue:)) ?? .system
    }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// The appearance to force on the app, nil to follow the Mac.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    /// Saves the choice and applies it at once, so every open window turns without a restart.
    @MainActor
    static func choose(_ look: Appearance) {
        UserDefaults.standard.set(look.rawValue, forKey: key)
        apply()
    }

    /// Puts the saved choice on the whole app; windows pinned dark keep their own appearance over it.
    @MainActor
    static func apply() {
        NSApp.appearance = chosen.nsAppearance
    }
}
