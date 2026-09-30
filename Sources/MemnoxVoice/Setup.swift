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
        daemon = await conversation.daemonAnswers()
            ? .done
            : .needs("Start it in a terminal: memnox daemon")
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
        }
    }
}

struct SetupView: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Set up Memnox").font(.title2.weight(.semibold))
            Text("Talk to your agents, and let them do more on their own, safely.")
                .foregroundStyle(.secondary)

            row("What should I call you?", state: model.name.isEmpty ? .waiting : .done) {
                TextField("Your name", text: $model.name).textFieldStyle(.roundedBorder).frame(width: 220)
            }
            row("Hear you", state: model.listening) {
                Button("Allow") { Task { await model.allowListening() } }
                    .disabled(model.listening == .done)
            }
            row("Memnox on this Mac", state: model.daemon) {
                Button("Check again") { Task { await model.check() } }
            }
            row("Touch ID for anything you allow", state: model.key) { EmptyView() }
            row("Voice", state: .done) {
                HStack {
                    Picker("", selection: $model.voiceId) {
                        ForEach(model.voices, id: \.identifier) { voice in
                            Text(label(voice)).tag(voice.identifier)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                    Button("Hear it") { Task { await model.hear() } }
                }
            }
            row("When you come back", state: .done) {
                Toggle("Catch me up on what my agents did while I was away", isOn: $model.catchUp)
            }
            row("Talk", state: .done) {
                Text("Press ⌥ Space, or say \"Hey Siri, talk to Memnox\" once Siri is set up.")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Done") { model.finish() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(28)
        .frame(width: 560)
        .task { await model.check() }
    }

    private func row<Control: View>(_ title: String, state: StepState, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .top, spacing: 12) {
            mark(state).frame(width: 18)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                control()
                if case .needs(let hint) = state {
                    Text(hint).font(.callout).foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private func mark(_ state: StepState) -> some View {
        switch state {
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .waiting: Image(systemName: "circle").foregroundStyle(.secondary)
        case .needs: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        }
    }

    private func label(_ voice: AVSpeechSynthesisVoice) -> String {
        let quality: String
        switch voice.quality {
        case .premium: quality = "Premium"
        case .enhanced: quality = "Enhanced"
        default: quality = "Standard"
        }
        return "\(voice.name) (\(quality))"
    }
}

/// The one ordinary window Memnox ever opens: setup, closed when it is done.
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
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Memnox"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SetupView(model: model))
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
