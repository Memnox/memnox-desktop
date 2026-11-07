import MemnoxVoiceCore
import SwiftUI

/// The first run spoken as well as shown: Memnox walks the person through every step until setup is finished, says
/// what each feature is for as the step that turns it on opens, and what to do in System Settings when a grant waits on
/// the person. The words never decide anything; they only follow the page, the part the notch plays and the grants, and
/// the person's mute silences all of it. Every line it says lives in `FirstRunGuide`, so it is tested headless.
struct OnboardingNarration: ViewModifier {
    @ObservedObject var flow: OnboardingFlow
    @ObservedObject var setup: SetupModel
    @ObservedObject private var mute = VoiceMute.shared

    func body(content: Content) -> some View {
        content
            .onChange(of: flow.page, initial: true) { _, _ in introduce(flow.guidePage) }
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

    /// A page's own lines, once in the first run, said as one so a voice still starting holds all of it; the first step
    /// opens with the greeting, then names the part the notch is already playing.
    private func introduce(_ page: FirstRunPage) {
        guard flow.firstVisit(page.rawValue) else { return }
        let greeting = page == .connect ? [FirstRunGuide.welcome(name: setup.name)] : []
        setup.guide((greeting + FirstRunGuide.lines(page)).joined(separator: " "))
        if page == .connect, let part = flow.highlight { follow(part) }
    }

    /// The part the notch moved on to, said once and only while the first step is the page on screen.
    private func follow(_ part: Highlight?) {
        guard flow.guidePage == .connect, let part, flow.narrated.insert(part).inserted else { return }
        setup.guide(part.spoken, interrupting: false)
    }
}

/// What the guide says about System Settings, which names the panes as this Mac shows them.
enum GuideLines {
    /// Said over the opening, with the same words it shows.
    static let askName = FirstRunGuide.askName

    static func typing(_ pane: String) -> String {
        "System Settings is opening. Find Memnox under \(pane) and switch it on. If Memnox is not in the list, press the plus button and choose it from Applications."
    }

    static func seeing(_ pane: String) -> String {
        "Now find Memnox in the top list under \(pane) and switch it on. Then press Restart Memnox, because macOS hands this one over only when I start again."
    }

    static let seeingStale = "macOS still says no, so the switch that shows on is an old one. Press Start over, and I will ask for it fresh."
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
