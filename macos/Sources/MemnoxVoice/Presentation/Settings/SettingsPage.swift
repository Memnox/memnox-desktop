/// The pages of the one Memnox window, grouped the way the console groups its own: the overview first, then the
/// person as one page, this Mac, the voice, and help. The person is one page because a name, a sign in and the row at
/// the sidebar's foot are all the same person, and three places for one person read as three accounts.
enum SettingsPage: String, CaseIterable, Identifiable {
    case overview
    case account
    case permissions
    case connection
    case phones
    case tools
    case apps
    case appearance
    case voice
    case listening
    case dictation
    case help

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .account: return "Account"
        case .permissions: return "Permissions"
        case .connection: return "This Mac"
        case .phones: return "Phones"
        case .tools: return "Agents"
        case .apps: return "Connectors"
        case .appearance: return "Appearance"
        case .voice: return "Voice"
        case .listening: return "Listening"
        case .dictation: return "Dictation"
        case .help: return "Help"
        }
    }

    /// One line under the page's title saying what the page is for.
    var subtitle: String {
        switch self {
        case .overview: return "What your agents are doing, and what is left to set up."
        case .account: return "Your name, who you are in Memnox Cloud, and what that lets Memnox do on this Mac."
        case .permissions: return "What this Mac lets Memnox hear, type and see."
        case .connection: return "The Memnox service your agents talk to, and the key Touch ID signs with."
        case .phones: return "Phones paired with this Mac and what each may do."
        case .tools: return "The agents on this Mac and where they run."
        case .apps: return "The apps your agents use as you, already on this Mac or connected here."
        case .appearance: return "Light, dark, or the same as this Mac."
        case .voice: return "Who thinks for the voice, and the voice it answers in."
        case .listening: return "When Memnox listens and how it speaks up."
        case .dictation: return "Speak instead of typing, in any app, written the way you would have typed it."
        case .help: return "Rules, a quick test, and what happened for support."
        }
    }
}
