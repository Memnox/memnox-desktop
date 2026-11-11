import AppKit
import SwiftUI

/// The phones: pairing one, then the ones already paired with what each may do.
struct PhonesPage: View {
    @ObservedObject var menu: MenuModel
    @ObservedObject var setup: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.pageSpacing) {
            SetupPhoneCard(model: setup)
            if !menu.devices.isEmpty {
                SettingsCard(title: "Paired phones") {
                    ForEach(menu.devices) { device in
                        if device.id != menu.devices.first?.id { Divider() }
                        DeviceRow(device: device, revoke: { menu.revoke(device) }, letDrive: { on in menu.letDrive(device, on) })
                    }
                }
            }
            if setup.serverPairing != nil { SetupServerCard(model: setup) }
        }
    }
}

/// Who thinks for the voice and which voice speaks, the Mac's own or a Kokoro one, in one row.
struct VoicePage: View {
    @ObservedObject var menu: MenuModel
    @ObservedObject var setup: SetupModel

    var body: some View {
        SetupVoiceCard(model: setup, menu: menu)
    }
}

/// The switches for when Memnox listens and speaks up, with catching up after time away, in two cards as Vorssaint
/// groups its own: hearing the person, then speaking to them.
struct ListeningPage: View {
    @ObservedObject var menu: MenuModel
    @ObservedObject private var mute = VoiceMute.shared
    @ObservedObject var setup: SetupModel
    /// Off unless turned on here, since Apple's voice processing reshapes the whole Mac's audio while it runs.
    @AppStorage(AudioIO.echoCancellationKey) private var cancelsEcho = false

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.pageSpacing) {
            SettingsCard(title: "Hearing you") {
                SwitchRow(symbol: MenuSymbol.wake, title: "Wake when I say \u{201C}Memnox\u{201D}", detail: "On this Mac only",
                          isOn: Binding(get: { menu.wakeOn }, set: { menu.setWake($0) }))
                SettingsDivider()
                SwitchRow(symbol: MenuSymbol.talkOver, title: "Talk over it", detail: "Cut in just by speaking",
                          isOn: Binding(get: { menu.talkOverOn }, set: { menu.talkOverOn = $0; menu.setTalkOver($0) }))
                SettingsDivider()
                SwitchRow(symbol: MenuSymbol.echo, title: "Cancel echo", detail: "Talk over it on speakers, though macOS changes other sound while it listens",
                          isOn: $cancelsEcho)
                SettingsDivider()
                SwitchRow(symbol: MenuSymbol.liveWords, title: "Live words", detail: "See what you say in the notch",
                          isOn: Binding(get: { menu.liveWordsOn }, set: { menu.liveWordsOn = $0; menu.setLiveWords($0) }))
                SettingsDivider()
                SwitchRow(symbol: MenuSymbol.stayPut, title: "Stay where I am", detail: "Agents get your words without taking your window",
                          isOn: Binding(get: { menu.stayPutOn }, set: { menu.stayPutOn = $0; menu.setStayPut($0) }))
            }
            SettingsCard(title: "Speaking to you") {
                SwitchRow(symbol: MenuSymbol.mute, title: "Mute the voice", detail: "Answers still show in the notch",
                          isOn: Binding(get: { mute.on }, set: { mute.set($0) }))
                SettingsDivider()
                SwitchRow(symbol: MenuSymbol.sayFinished, title: "Say when a session finishes", detail: "Which agent, where and what you asked it",
                          isOn: Binding(get: { menu.sayFinishedOn }, set: { menu.sayFinishedOn = $0; menu.setSayFinished($0) }))
                SettingsDivider()
                SwitchRow(symbol: MenuSymbol.speakUp, title: "Speak up on its own", detail: "Commits, pushes and other news",
                          isOn: Binding(get: { menu.speakUpOn }, set: { menu.speakUpOn = $0; menu.setSpeakUp($0) }))
                SettingsDivider()
                SwitchRow(symbol: MenuSymbol.sounds, title: "Sounds", detail: "A chime when something happens",
                          isOn: Binding(get: { menu.chimesOn }, set: { menu.chimesOn = $0; menu.setChimes($0) }))
                SettingsDivider()
                ChimeVolumeRow(preview: menu.previewChime)
                    .disabled(!menu.chimesOn)
                SettingsDivider()
                SetupCatchUpRow(model: setup)
            }
        }
    }
}

/// How loud the chimes are, played once at the new level when the slider is let go so it is heard rather than guessed.
private struct ChimeVolumeRow: View {
    let preview: () -> Void
    @AppStorage(CueChimes.volumeKey) private var volume = CueChimes.defaultVolume

    private static let sliderWidth: CGFloat = 140

    var body: some View {
        SettingsRow(symbol: MenuSymbol.volume, title: "Volume", caption: "How loud the chimes are") {
            Slider(value: $volume, in: CueChimes.quietest...1) { editing in
                if !editing { preview() }
            }
            .controlSize(.small)
            .frame(width: Self.sliderWidth)
            .accessibilityLabel("Chime volume")
            .accessibilityValue("\(Int((volume * 100).rounded())) percent")
        }
    }
}

/// Saying a rule or a line, and copying what happened for support, each a row with its button at the end.
struct HelpPage: View {
    @ObservedObject var menu: MenuModel
    let setup: SetupModel

    var body: some View {
        SettingsCard {
            SettingsRow(symbol: "arrow.counterclockwise", title: "Run setup again",
                        caption: "The five steps from the start, with what you answered before already chosen.") {
                Button("Run setup") { OnboardingWindow.shared.show(setup, again: true) }
            }
            SettingsDivider()
            SettingsRow(symbol: MenuSymbol.rule, title: "Say a rule",
                        caption: "Turns a sentence like \u{201C}never deploy on Fridays\u{201D} into a rule.") {
                Button("Say a rule", action: menu.sayRule)
            }
            SettingsDivider()
            SettingsRow(symbol: MenuSymbol.saySomething, title: "Say something",
                        caption: "Checks that Memnox hears and answers you.") {
                Button("Try it", action: menu.saySomething)
            }
            SettingsDivider()
            SettingsRow(symbol: MenuSymbol.copy, title: "Copy what happened",
                        caption: "Puts the recent steps on your clipboard to send to support.") {
                Button("Copy", action: menu.copyWhatHappened)
            }
            SettingsDivider()
            SettingsRow(symbol: "trash", title: "Uninstall Memnox",
                        caption: "Removes the service, its hooks in your agents, your history here, its sign ins and the app.",
                        tint: Memnox.Console.warm) {
                Button("Uninstall", action: menu.uninstall)
            }
        }
    }
}
