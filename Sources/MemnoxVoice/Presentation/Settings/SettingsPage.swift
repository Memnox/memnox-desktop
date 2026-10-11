/// The pages of the one Memnox window, grouped the way the console groups its own: the overview first, then the
/// person, this Mac, the voice, and help.
enum SettingsPage: String, CaseIterable, Identifiable {
    case overview
    case profile
    case team
    case connection
    case phones
    case voice
    case listening
    case help

    var id: String { rawValue }

    /// The sidebar's groups in order, each with the pages under it; the overview stands alone at the top.
    static let groups: [(title: String?, pages: [SettingsPage])] = [
        (nil, [.overview]),
        ("You", [.profile, .team]),
        ("This Mac", [.connection, .phones]),
        ("Voice", [.voice, .listening]),
        ("Support", [.help]),
    ]

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .profile: return "Profile"
        case .team: return "Team"
        case .connection: return "Connection"
        case .phones: return "Phones"
        case .voice: return "Voice"
        case .listening: return "Listening"
        case .help: return "Help"
        }
    }

    /// One line under the page's title saying what the page is for.
    var subtitle: String {
        switch self {
        case .overview: return "What your agents are doing, and what is left to set up."
        case .profile: return "Who you are, and what this Mac lets Memnox hear and see."
        case .team: return "Your Memnox Cloud workspace, and the calls it routes to you."
        case .connection: return "The daemon your agents talk to, and the key Touch ID signs with."
        case .phones: return "Phones paired with this Mac and what each may do."
        case .voice: return "Who thinks for the voice, and the voice it answers in."
        case .listening: return "When Memnox listens and how it speaks up."
        case .help: return "Rules, a quick test, and what happened for support."
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "house"
        case .profile: return "person.crop.circle"
        case .team: return "person.3"
        case .connection: return "bolt.horizontal.circle"
        case .phones: return "iphone"
        case .voice: return "person.wave.2"
        case .listening: return "ear"
        case .help: return "questionmark.circle"
        }
    }
}
