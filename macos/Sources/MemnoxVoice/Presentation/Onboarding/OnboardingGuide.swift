import SwiftUI

/// The first run spoken as well as shown: Memnox says what each step is for, what it will do on this Mac, and what
/// to do in System Settings when a grant waits on the person. The words never decide anything; they only follow the
/// step, the part the notch plays and the grants, and the person's mute silences all of it.
struct OnboardingNarration: ViewModifier {
    @ObservedObject var flow: OnboardingFlow
    @ObservedObject var setup: SetupModel
    @ObservedObject private var mute = VoiceMute.shared

    func body(content: Content) -> some View {
        content
            .onChange(of: flow.page, initial: true) { _, page in introduce(page) }
            .onChange(of: flow.highlight) { _, part in follow(part) }
            .onChange(of: setup.typing) { _, state in
                if case .needs = state { setup.guide(GuideLines.typing(SettingsPane.typing.title)) }
            }
            .onChange(of: setup.seeing) { _, state in
                guard case .needs = state else { return }
                setup.guide(setup.seeingStale ? GuideLines.seeingStale : GuideLines.seeing(SettingsPane.seeing.title))
            }
            .onChange(of: mute.on) { _, muted in if muted { setup.stopGuide() } }
    }

    /// A page's own line, once in the first run; the first step then names the part the notch is already playing.
    private func introduce(_ page: Int) {
        guard flow.firstVisit(page) else { return }
        if flow.optional {
            setup.guide(GuideLines.optional)
            return
        }
        switch flow.step {
        case .connect:
            setup.guide(GuideLines.welcome(name: setup.name))
            setup.guide(GuideLines.setup, interrupting: false)
            if let part = flow.highlight { follow(part) }
        case .workspace: setup.guide(GuideLines.workspace)
        case .boundaries: setup.guide(GuideLines.boundaries)
        }
    }

    /// The part the notch moved on to, said once and only while the first step is the page on screen.
    private func follow(_ part: Highlight?) {
        guard flow.step == .connect, !flow.optional, let part, flow.narrated.insert(part).inserted else { return }
        setup.guide(part.spoken, interrupting: false)
    }
}

/// What the guide says at each step, written to be heard.
enum GuideLines {
    /// Said over the opening, with the same words it shows.
    static let askName = "Welcome to Memnox. I'm the voice over your agents. So, what should I call you?"

    static func welcome(name: String) -> String {
        "Hi\(greeting(name)), I'm Memnox. I live in your notch and watch over your AI agents, so they can work on their own and stay inside the boundaries you set. No account needed."
    }

    /// What Memnox puts on this Mac and the one thing it asks for now, said before any of it happens.
    static let setup = "Here is what I will do on this Mac. I install the Memnox service in your home folder and keep it running and up to date, and I connect it to the agents I find, like Claude Code, Codex and Cursor, so what they do passes your rules first. From you I need one thing now: Touch ID so only you approve."

    /// Said over the second step, before anything is brought in.
    static let workspace = "Your agents already have servers and skills of their own. Bring them in with one tap, so each is set up once and given to the agents you choose."

    /// Said over the third step: a pack is only proposed, and each rule waits for the person.
    static let boundaries = "Last, choose your boundaries. Pick a pack of rules to start from, and confirm each rule with Touch ID on the island. You can change any of them later."

    /// Said once the three steps are done, over what is left and optional.
    static let optional = "That is everything your agents need. The rest is optional: the microphone so you can talk to me, a voice to answer, and your phone for when you are away."

    static func typing(_ pane: String) -> String {
        "System Settings is opening. Find Memnox under \(pane) and switch it on. If Memnox is not in the list, press the plus button and choose it from Applications."
    }

    static func seeing(_ pane: String) -> String {
        "Now find Memnox in the top list under \(pane) and switch it on. Then press Restart Memnox, because macOS hands this one over only when I start again."
    }

    static let seeingStale = "macOS still says no, so the switch that shows on is an old one. Press Start over, and I will ask for it fresh."

    private static func greeting(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "" : " \(trimmed)"
    }
}

/// Mutes and unmutes Memnox, in the first run's footer, the one place a new person reaches for it.
/// The calm bed under setup, on or off, remembered for the next time setup opens.
struct AmbienceButton: View {
    @ObservedObject private var ambience = SetupAmbience.shared

    var body: some View {
        Button("Music", systemImage: ambience.on ? "music.note" : "music.note.slash") { ambience.toggle() }
            .buttonStyle(KitButton(kind: .secondary))
            .help(ambience.on ? "Turn the calm music off" : "Play calm music while you set up")
            .accessibilityLabel(ambience.on ? "Turn music off" : "Turn music on")
    }
}

struct MuteButton: View {
    @ObservedObject private var mute = VoiceMute.shared

    var body: some View {
        Button(mute.on ? "Unmute" : "Mute", systemImage: mute.on ? MenuSymbol.mute : MenuSymbol.unmute) { mute.toggle() }
            .buttonStyle(KitButton(kind: .secondary))
            .help(mute.on ? "Let Memnox speak again" : "Keep Memnox quiet; everything still shows on screen")
            .accessibilityLabel(mute.on ? "Unmute Memnox" : "Mute Memnox")
    }
}
