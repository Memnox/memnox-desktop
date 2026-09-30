import AppKit
import AVFoundation
import MemnoxVoiceCore
import Speech
import SwiftUI

/// Where each step of setup stands, shown as a tick, a question or what to do next.
enum StepState: Equatable {
    case waiting
    case done
    case needs(String)
}

/// The first run, and whenever the person opens it again from the menu bar: who they are,
/// what the Mac lets Memnox hear, whether the daemon is there, the key, and the voice.
@MainActor
final class SetupModel: ObservableObject {
    @Published var name: String
    @Published var listening: StepState = .waiting
    @Published var daemon: StepState = .waiting
    @Published var key: StepState = .waiting
    @Published var voiceId: String
    @Published var catchUp: Bool
    let voices: [AVSpeechSynthesisVoice]

    private let owner: OwnerStore
    private let conversation: Conversation
    private let voice: Voice
    private let finished: () -> Void

    init(owner: OwnerStore, conversation: Conversation, voice: Voice, finished: @escaping () -> Void) {
        self.owner = owner
        self.conversation = conversation
        self.voice = voice
        self.finished = finished
        name = owner.name ?? suggestedName()
        voices = Voice.englishVoices()
        voiceId = voice.identifier ?? voices.first?.identifier ?? ""
        catchUp = UserDefaults.standard.object(forKey: SetupModel.catchUpKey) as? Bool ?? true
    }

    /// Everything that can be checked without asking the person, checked as the card opens.
    func check() async {
        listening = hearingState()
        switch await conversation.daemonVoice() {
        case .ready: daemon = .done
        case .tooOld: daemon = .needs("This Memnox is older than the app. Update it, then check again")
        case .unreachable: daemon = .needs("Start it in a terminal: memnox daemon --install")
        }
        key = await keyState()
    }

    func allowListening() async {
        listening = await Ears.askPermission()
            ? .done
            : .needs("Turn on Memnox in System Settings, Privacy and Security, Microphone and Speech Recognition")
    }

    func hear() async {
        voice.choose(voiceId)
        let first = name.trimmingCharacters(in: .whitespaces)
        await voice.preview("Hi \(first.isEmpty ? "there" : first), I'm Memnox. Press Option Space whenever you want me.")
    }

    func finish() {
        let chosen = name.trimmingCharacters(in: .whitespaces)
        owner.name = chosen.isEmpty ? nil : chosen
        voice.choose(voiceId)
        UserDefaults.standard.set(catchUp, forKey: SetupModel.catchUpKey)
        UserDefaults.standard.set(true, forKey: SetupModel.doneKey)
        finished()
    }

    static let doneKey = "setupDone"
    static let catchUpKey = "catchUp"

    private func hearingState() -> StepState {
        let microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let speech = SFSpeechRecognizer.authorizationStatus() == .authorized
        return microphone && speech ? .done : .waiting
    }

    private func keyState() async -> StepState {
        switch await conversation.registerKey() {
        case .registered: return .done
        case .anotherKey: return .needs("Another key is trusted. Run memnox voice forget-key, then check again")
        case .unreachable: return .needs("Waiting for the daemon")
        case .tooOld: return .needs("Waiting for a Memnox that knows voice")
        }
    }
}

struct SetupView: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        ZStack {
            Glass(material: .hudWindow)
            Memnox.Palette.background.opacity(0.55)
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 22)
                VStack(spacing: 10) {
                    step("What should I call you?", state: model.name.trimmingCharacters(in: .whitespaces).isEmpty ? .waiting : .done) {
                        NameField(text: $model.name)
                    }
                    step("Hear you", detail: "Microphone and speech recognition, on this Mac only.", state: model.listening) {
                        if model.listening != .done {
                            Button("Allow") { Task { await model.allowListening() } }.buttonStyle(QuietButton())
                        }
                    }
                    step("Memnox on this Mac", detail: "The daemon your agents already talk to.", state: model.daemon) {
                        if model.daemon != .done {
                            Button("Check again") { Task { await model.check() } }.buttonStyle(QuietButton())
                        }
                    }
                    step("Touch ID for anything you allow", detail: "A deny needs only your voice. An allow needs your finger.", state: model.key) {
                        EmptyView()
                    }
                    step("Voice", state: .done) {
                        HStack(spacing: 8) {
                            VoicePicker(model: model)
                            Button("Hear it") { Task { await model.hear() } }.buttonStyle(QuietButton())
                        }
                    }
                    step("When you come back", state: .done) {
                        Toggle(isOn: $model.catchUp) {
                            Text("Catch me up on what my agents did while I was away")
                                .font(Memnox.sans(12))
                                .foregroundStyle(Memnox.Palette.muted)
                        }
                        .toggleStyle(.switch)
                        .tint(Memnox.Palette.primary)
                        .controlSize(.small)
                    }
                }
                footer
                    .padding(.top, 22)
            }
            .padding(.horizontal, 28)
            .padding(.top, 40)
            .padding(.bottom, 24)
        }
        .frame(width: 540)
        .environment(\.colorScheme, .dark)
        .task { await model.check() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            OrbMark()
            VStack(alignment: .leading, spacing: 4) {
                Text("MEMNOX")
                    .font(Memnox.sans(10, .semibold))
                    .tracking(1.6)
                    .foregroundStyle(Memnox.Palette.muted)
                Text("Set up your voice")
                    .font(Memnox.display(30))
                    .foregroundStyle(Memnox.Palette.foreground)
                Text("Talk to your agents, and let them do more on their own, safely.")
                    .font(Memnox.sans(13))
                    .foregroundStyle(Memnox.Palette.muted)
            }
        }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                Keycap(label: "⌥")
                Keycap(label: "Space")
                Text("to talk, from anywhere")
                    .font(Memnox.sans(12))
                    .foregroundStyle(Memnox.Palette.muted)
            }
            Spacer()
            Button("Done") { model.finish() }
                .buttonStyle(PrimaryButton())
                .keyboardShortcut(.defaultAction)
                .disabled(model.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func step<Control: View>(
        _ title: String,
        detail: String? = nil,
        state: StepState,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            StatusMark(state: state).padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(Memnox.sans(13, .semibold))
                    .foregroundStyle(Memnox.Palette.foreground)
                if let detail {
                    Text(detail).font(Memnox.sans(12)).foregroundStyle(Memnox.Palette.muted)
                }
                control()
                if case .needs(let hint) = state {
                    Text(hint).font(Memnox.sans(12)).foregroundStyle(Memnox.Palette.warm)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Memnox.cardRadius)
                .fill(Memnox.Palette.card.opacity(0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Memnox.cardRadius)
                .strokeBorder(Memnox.Palette.border.opacity(0.7), lineWidth: 1)
        )
    }
}

/// Done in green, waiting as an outline, and anything that needs you in the warm colour.
private struct StatusMark: View {
    let state: StepState

    var body: some View {
        switch state {
        case .done:
            Circle().fill(Memnox.Palette.success)
                .frame(width: 16, height: 16)
                .overlay(Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Memnox.Palette.background))
        case .waiting:
            Circle().strokeBorder(Memnox.Palette.border, lineWidth: 1.5).frame(width: 16, height: 16)
        case .needs:
            Circle().fill(Memnox.Palette.warm)
                .frame(width: 16, height: 16)
                .overlay(Text("!").font(.system(size: 10, weight: .bold)).foregroundStyle(Memnox.Palette.background))
        }
    }
}

/// The orb, small and still, so setup is visibly the same thing that will talk to you.
private struct OrbMark: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Memnox.Palette.ember, Memnox.Palette.rose, .clear], center: .center, startRadius: 2, endRadius: 30))
                .blur(radius: 6)
            Circle()
                .fill(LinearGradient(colors: [Memnox.Palette.ember, Memnox.Palette.rose], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 22, height: 22)
        }
        .frame(width: 52, height: 52)
    }
}

/// A text field in the console's input style: dark, bordered, a blue ring when focused.
private struct NameField: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text, prompt: Text("Your name").foregroundStyle(Memnox.Palette.muted))
            .textFieldStyle(.plain)
            .font(Memnox.sans(13))
            .foregroundStyle(Memnox.Palette.foreground)
            .focused($focused)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(width: 240)
            .background(RoundedRectangle(cornerRadius: Memnox.radius).fill(Memnox.Palette.card))
            .overlay(
                RoundedRectangle(cornerRadius: Memnox.radius)
                    .strokeBorder(focused ? Memnox.Palette.primary : Memnox.Palette.border, lineWidth: 1)
            )
            .shadow(color: focused ? Memnox.Palette.ring : .clear, radius: 4)
    }
}

/// The installed voices, best first, as a quiet menu rather than a system pop up button.
private struct VoicePicker: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        Menu {
            ForEach(model.voices, id: \.identifier) { voice in
                Button(label(voice)) { model.voiceId = voice.identifier }
            }
        } label: {
            HStack {
                Text(current).font(Memnox.sans(12)).foregroundStyle(Memnox.Palette.foreground)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9)).foregroundStyle(Memnox.Palette.muted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: 240)
            .background(RoundedRectangle(cornerRadius: Memnox.radius).fill(Memnox.Palette.card))
            .overlay(RoundedRectangle(cornerRadius: Memnox.radius).strokeBorder(Memnox.Palette.border, lineWidth: 1))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    private var current: String {
        model.voices.first { $0.identifier == model.voiceId }.map(label) ?? "Choose a voice"
    }

    private func label(_ voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: return "\(voice.name) · Premium"
        case .enhanced: return "\(voice.name) · Enhanced"
        default: return voice.name
        }
    }
}

/// The one ordinary window Memnox ever opens: setup, on glass, closed when it is done.
@MainActor
final class SetupWindow {
    private var window: NSWindow?

    func show(_ model: SetupModel) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 640),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: SetupView(model: model))
        host.wantsLayer = true
        host.layer?.cornerRadius = 16
        host.layer?.masksToBounds = true
        window.contentView = host
        window.setContentSize(host.fittingSize)
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
        window = nil
    }
}
