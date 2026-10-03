import AppKit
import AVFoundation
import Combine
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
    /// Kokoro installing itself, watched so the voice row shows where it stands.
    let kokoro: KokoroInstaller
    private var watchingKokoro: AnyCancellable?
    /// Installs Kokoro if need be and makes it the voice, for the row's Try again.
    var useKokoro: (() async -> Void)?

    private let owner: OwnerStore
    private let conversation: Conversation
    private let voice: Voice
    private let finished: () -> Void

    init(owner: OwnerStore, conversation: Conversation, voice: Voice, kokoro: KokoroInstaller, finished: @escaping () -> Void) {
        self.kokoro = kokoro
        self.owner = owner
        self.conversation = conversation
        self.voice = voice
        self.finished = finished
        name = owner.name ?? suggestedName()
        voices = Voice.englishVoices()
        voiceId = voice.identifier ?? voices.first?.identifier ?? ""
        catchUp = UserDefaults.standard.object(forKey: SetupModel.catchUpKey) as? Bool ?? true
        // A nested object's changes do not reach the view on their own, so they are passed on.
        watchingKokoro = kokoro.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
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
        await voice.preview("Hi \(first.isEmpty ? "there" : first), I am Memnox. Press Option Space whenever you want me.")
    }

    /// Premium and Enhanced voices sound like a person; Standard ones sound like reading.
    var naturalVoice: Bool {
        guard let chosen = voices.first(where: { $0.identifier == voiceId }) else { return false }
        return chosen.quality == .premium || chosen.quality == .enhanced
    }

    /// How the voice row reads: Kokoro ready, on its way, or what went wrong with a way to try again.
    var voiceState: StepState {
        switch kokoro.state {
        case .done: return .done
        case .installing: return .waiting
        case .failed(let why): return naturalVoice ? .done : .needs(why)
        case .idle: return naturalVoice ? .done : .waiting
        }
    }

    var voiceDetail: String {
        switch kokoro.state {
        case .done:
            return "Kokoro, a natural voice that runs on this Mac for free. The Mac voice below steps in if it ever stops."
        case .installing(let step):
            return "Installing Kokoro, a natural voice that runs on this Mac for free: \(step.lowercased()). About 340 MB, once. The Mac voice below speaks until it is ready."
        case .idle, .failed:
            return "Kokoro, a natural voice that runs on this Mac for free, installs itself the first time. The Mac voice below speaks until then."
        }
    }

    /// Where macOS keeps the voices to download, since an app cannot fetch them itself.
    func openVoiceSettings() {
        let spoken = URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?SpokenContent")
        if let spoken { NSWorkspace.shared.open(spoken) }
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
            // Solid black lit faintly from below, the same ground as the island and its cards.
            Color.black
            RadialGradient(
                colors: [Memnox.Palette.primary.opacity(0.18), .clear],
                center: UnitPoint(x: 0.5, y: 1.1),
                startRadius: 0,
                endRadius: 520
            )
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 22)
                VStack(spacing: 10) {
                    step("What should I call you?", state: model.name.trimmingCharacters(in: .whitespaces).isEmpty ? .waiting : .done) {
                        NameField(text: $model.name)
                    }
                    step("Hear you", detail: "Microphone and speech recognition, on this Mac only.", state: model.listening) {
                        if model.listening != .done {
                            Button("Allow") { Task { await model.allowListening() } }.buttonStyle(IslandButton(primary: true))
                        }
                    }
                    step("Memnox on this Mac", detail: "The daemon your agents already talk to.", state: model.daemon) {
                        if model.daemon != .done {
                            Button("Check again") { Task { await model.check() } }.buttonStyle(IslandButton(primary: false))
                        }
                    }
                    step("Touch ID for anything you allow", detail: "A deny needs only your voice. An allow needs your finger.", state: model.key) {
                        EmptyView()
                    }
                    step("Voice", detail: model.voiceDetail, state: model.voiceState) {
                        if case .installing = model.kokoro.state {
                            ProgressView().controlSize(.small)
                        }
                        HStack(spacing: 8) {
                            VoicePicker(model: model)
                            Button {
                                Task { await model.hear() }
                            } label: {
                                Label("Hear it", systemImage: "play.fill")
                            }
                            .buttonStyle(IslandButton(primary: false))
                        }
                        if case .failed = model.kokoro.state {
                            HStack(spacing: 8) {
                                Button("Try again") { Task { await model.useKokoro?() } }.buttonStyle(IslandButton(primary: false))
                                if !model.naturalVoice {
                                    Button("Get a Mac voice instead") { model.openVoiceSettings() }.buttonStyle(IslandButton(primary: false))
                                }
                            }
                        }
                    }
                    step("When you come back", state: .done) {
                        HStack(spacing: 12) {
                            Text("Catch me up on what my agents did while I was away")
                                .font(Memnox.sans(12))
                                .foregroundStyle(Color.white.opacity(0.5))
                            Spacer(minLength: 8)
                            Toggle("", isOn: $model.catchUp)
                                .toggleStyle(MemnoxSwitch())
                                .labelsHidden()
                        }
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
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            Spacer()
            Button("Done") { model.finish() }
                .buttonStyle(IslandButton(primary: true))
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
        IslandCard(veil: veil(state)) {
            HStack(alignment: .top, spacing: 12) {
                StatusMark(state: state).padding(.top, 1)
                VStack(alignment: .leading, spacing: 7) {
                    Text(title)
                        .font(Memnox.sans(13.5, .semibold))
                        .foregroundStyle(Color.white)
                    if let detail {
                        Text(detail)
                            .font(Memnox.sans(12))
                            .foregroundStyle(Color.white.opacity(0.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    control()
                    if case .needs(let hint) = state {
                        Text(hint).font(Memnox.sans(12)).foregroundStyle(IslandPalette.amber)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .animation(.easeInOut(duration: 0.35), value: state)
    }

    /// Amber light under a step that needs them, and none under one that is done, so the eye goes to what is left.
    private func veil(_ state: StepState) -> Color? {
        if case .needs = state { return IslandPalette.amber.opacity(0.3) }
        return nil
    }
}

/// Done in green, waiting as an outline, and anything that needs you in the warm colour.
private struct StatusMark: View {
    let state: StepState

    var body: some View {
        switch state {
        case .done:
            Circle().fill(IslandPalette.green)
                .frame(width: 18, height: 18)
                .overlay(Image(systemName: "checkmark").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(Color.black))
                .transition(.scale.combined(with: .opacity))
        case .waiting:
            Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1.5).frame(width: 18, height: 18)
        case .needs:
            Circle().fill(IslandPalette.amber)
                .frame(width: 18, height: 18)
                .overlay(Text("!").font(.system(size: 10, weight: .heavy)).foregroundStyle(Color.black))
        }
    }
}

/// The Memnox mark, so setup is plainly the same product as the console.
private struct OrbMark: View {
    var body: some View {
        LogoMark(size: 34)
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
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: 260)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(focused ? Memnox.Palette.primary : Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: focused ? Memnox.Palette.ring : .clear, radius: 6)
            .animation(.easeOut(duration: 0.15), value: focused)
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
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: 260)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
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
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        // An ordinary window the system rounds itself, so its close and minimize buttons stay on top
        // and take clicks; painted black like the island rather than frosted.
        window.backgroundColor = .black
        let host = NSHostingView(rootView: SetupView(model: model))
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
