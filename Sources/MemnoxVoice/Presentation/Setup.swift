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
    /// The agents the voice can think with, as the daemon last checked them.
    @Published var agents: [VoiceAgentStatus] = []
    @Published var agentsState: StepState = .waiting
    /// Asking every agent takes a while, so the row says it is still asking.
    @Published var checkingAgents = false
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
        name = owner.name ?? suggestedName(fullName: NSFullUserName())
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
        // Last, since the first time it asks every agent a question and that takes a while.
        await loadAgents()
    }

    /// The agents from the daemon's last check, or every one asked again when the person says so.
    func loadAgents(recheck: Bool = false) async {
        checkingAgents = true
        defer { checkingAgents = false }
        apply(await conversation.voiceAgents(recheck: recheck))
    }

    func useAgent(_ kind: String) async {
        apply(await conversation.chooseVoiceAgent(kind))
    }

    /// What the step under the voice agents says: which one thinks, and whether it is kept to reading.
    var agentsDetail: String {
        guard let chosen = agents.first(where: \.chosen) else {
            return checkingAgents
                ? "Asking each of your agents one question to see which answers."
                : "The agent you already use thinks for the voice."
        }
        if chosen.sealed { return "\(chosen.label), kept to reading, so it never edits a file or runs a command." }
        return "\(chosen.label) can run shell commands without asking, used because no agent kept to reading answered."
    }

    private func apply(_ answer: VoiceAgentsAnswer) {
        switch answer {
        case .agents(let found):
            agents = found
            agentsState = agentsState(found)
        case .refused(let why): agentsState = .needs(why)
        case .unreachable: agentsState = .needs("Waiting for the daemon")
        }
    }

    private func agentsState(_ found: [VoiceAgentStatus]) -> StepState {
        let installed = found.filter(\.installed)
        if installed.isEmpty {
            return .needs("Install and log in to one of Claude Code, Codex, Cursor, Hermes or OpenClaw, then check again")
        }
        if let chosen = found.first(where: \.chosen), chosen.works == true { return .done }
        if installed.allSatisfy({ $0.works == nil }) { return .waiting }
        if installed.contains(where: { $0.works == true }) { return .needs("Choose the agent that answers for you") }
        return .needs("None of your agents answered. Fix one below, then check again")
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
            return "Kokoro, a natural voice running on this Mac."
        case .installing(let step):
            return "Installing Kokoro, about 340 MB once: \(step.lowercased()). The Mac voice speaks until then."
        case .idle, .failed:
            return "Kokoro installs itself the first time. The Mac voice speaks until then."
        }
    }

    /// The Spoken Content pane of Accessibility in System Settings.
    private static let spokenContentSettings = "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?SpokenContent"

    /// Where macOS keeps the voices to download, since an app cannot fetch them itself.
    func openVoiceSettings() {
        let spoken = URL(string: Self.spokenContentSettings)
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
    /// Whether the agent rows show once an agent already answers, since then they are detail.
    @State private var showingAgents = false

    private enum Layout {
        static let glowOpacity = 0.14
        static let glowCenter = UnitPoint(x: 0.5, y: 1.1)
        static let glowRadius: CGFloat = 420
        /// The room between the header, the checklist and the footer.
        static let sectionGap: CGFloat = 16
        static let horizontalPadding: CGFloat = 22
        /// Taller at the top, to clear the window's close and minimize buttons.
        static let topPadding: CGFloat = 34
        static let bottomPadding: CGFloat = 18
        static let headerSpacing: CGFloat = 12
        static let titleSize: CGFloat = 24
        static let logoSize: CGFloat = 28
        static let stepChange: TimeInterval = 0.25
        static let playSymbol = "play.fill"
        static let dividerInk = 0.06
        /// Lines a divider up with the titles rather than the marks, as System Settings does.
        static let dividerInset: CGFloat = 44
    }

    var body: some View {
        ZStack {
            // Solid black lit faintly from below, the same ground as the island and its cards.
            Color.black
            RadialGradient(
                colors: [Memnox.Palette.primary.opacity(Layout.glowOpacity), .clear],
                center: Layout.glowCenter,
                startRadius: 0,
                endRadius: Layout.glowRadius
            )
            VStack(alignment: .leading, spacing: Layout.sectionGap) {
                header
                checklist
                catchUpRow
                footer
            }
            .padding(.horizontal, Layout.horizontalPadding)
            .padding(.top, Layout.topPadding)
            .padding(.bottom, Layout.bottomPadding)
        }
        .frame(width: SetupLayout.width)
        .environment(\.colorScheme, .dark)
        .task { await model.check() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Layout.headerSpacing) {
            LogoMark(size: Layout.logoSize)
            VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                Text("Set up your voice")
                    .font(Memnox.display(Layout.titleSize))
                    .foregroundStyle(Memnox.Palette.foreground)
                Text("Talk to your agents, and let them do more on their own, safely.")
                    .font(Memnox.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Palette.muted)
            }
            Spacer(minLength: Memnox.Spacing.medium)
            ProgressPill(ready: readyCount, total: steps.count)
        }
    }

    /// Every step as one grouped list, so the window stays short enough to fit any screen.
    private var checklist: some View {
        IslandCard(veil: nil) {
            VStack(spacing: 0) {
                SetupStep("Your name", detail: "What I call you.", state: steps[0]) {
                    NameField(text: $model.name)
                }
                divider
                SetupStep("Hear you", detail: "Microphone and speech recognition, on this Mac only.", state: model.listening) {
                    if model.listening != .done {
                        Button("Allow") { Task { await model.allowListening() } }.buttonStyle(IslandButton(primary: true))
                    }
                }
                divider
                SetupStep("Memnox daemon", detail: "What your agents already talk to.", state: model.daemon) {
                    if model.daemon != .done { checkAgainButton }
                }
                divider
                SetupStep("Touch ID", detail: "Your finger approves anything outside a session's repository. Saying no needs only your voice.", state: model.key) {
                    if model.key != .done { checkAgainButton }
                }
                divider
                SetupStep("Who answers for you", detail: model.agentsDetail, state: model.agentsState) {
                    if model.agentsState == .done {
                        Button(showingAgents ? "Hide" : "Details") { showingAgents.toggle() }
                            .buttonStyle(IslandButton(primary: false))
                    }
                } extra: {
                    if model.agentsState != .done || showingAgents { AgentRows(model: model) }
                }
                divider
                SetupStep("Voice", detail: model.voiceDetail, state: model.voiceState) {
                    HStack(spacing: Memnox.Spacing.small) {
                        VoicePicker(model: model)
                        Button { Task { await model.hear() } } label: {
                            Image(systemName: Layout.playSymbol)
                        }
                        .buttonStyle(IslandButton(primary: false))
                        .help("Hear it")
                    }
                } extra: {
                    voiceExtra
                }
            }
            .animation(.easeInOut(duration: Layout.stepChange), value: showingAgents)
        }
    }

    @ViewBuilder private var voiceExtra: some View {
        switch model.kokoro.state {
        case .installing:
            ProgressView().controlSize(.small)
        case .failed:
            HStack(spacing: Memnox.Spacing.medium) {
                Button("Try again") { Task { await model.useKokoro?() } }.buttonStyle(IslandButton(primary: false))
                if !model.naturalVoice {
                    Button("Get a Mac voice instead") { model.openVoiceSettings() }.buttonStyle(IslandButton(primary: false))
                }
            }
        case .idle, .done:
            EmptyView()
        }
    }

    private var checkAgainButton: some View {
        Button("Check again") { Task { await model.check() } }.buttonStyle(IslandButton(primary: false))
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(Layout.dividerInk))
            .frame(height: Memnox.Stroke.hairline)
            .padding(.leading, Layout.dividerInset)
    }

    private var catchUpRow: some View {
        HStack(spacing: Memnox.Spacing.large) {
            Text("Catch me up on what my agents did while I was away")
                .font(Memnox.sans(Memnox.TextSize.footnote))
                .foregroundStyle(Color.white.opacity(Memnox.Ink.primary))
            Spacer(minLength: Memnox.Spacing.medium)
            Toggle("", isOn: $model.catchUp)
                .toggleStyle(MemnoxSwitch())
                .labelsHidden()
        }
        .padding(.horizontal, Memnox.Spacing.xSmall)
    }

    private var footer: some View {
        HStack {
            HStack(spacing: Memnox.Spacing.small) {
                Keycap(label: "⌥")
                Keycap(label: "Space")
                Text("to talk, from anywhere")
                    .font(Memnox.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
            }
            Spacer()
            Button("Done") { model.finish() }
                .buttonStyle(IslandButton(primary: true))
                .keyboardShortcut(.defaultAction)
                .disabled(model.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    /// The name first, then each check in the order the list shows them.
    private var steps: [StepState] {
        let named: StepState = model.name.trimmingCharacters(in: .whitespaces).isEmpty ? .waiting : .done
        return [named, model.listening, model.daemon, model.key, model.agentsState, model.voiceState]
    }

    private var readyCount: Int { steps.filter { $0 == .done }.count }
}

/// One row of the checklist: its mark, its title and a line on what it is, the control on the right,
/// anything longer underneath, and what to do in amber when it needs the person.
private struct SetupStep<Trailing: View, Extra: View>: View {
    let title: String
    let detail: String
    let state: StepState
    let trailing: Trailing
    let extra: Extra

    private typealias Layout = SetupStepLayout

    init(_ title: String, detail: String, state: StepState, @ViewBuilder trailing: () -> Trailing, @ViewBuilder extra: () -> Extra) {
        self.title = title
        self.detail = detail
        self.state = state
        self.trailing = trailing()
        self.extra = extra()
    }

    var body: some View {
        HStack(alignment: .top, spacing: Memnox.Spacing.large) {
            StatusMark(state: state).padding(.top, Layout.markTopInset)
            VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
                HStack(alignment: .center, spacing: Memnox.Spacing.large) {
                    VStack(alignment: .leading, spacing: Layout.lineSpacing) {
                        Text(title)
                            .font(Memnox.sans(Layout.titleSize, .semibold))
                            .foregroundStyle(Color.white)
                        Text(detail)
                            .font(Memnox.sans(Memnox.TextSize.caption))
                            .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    trailing
                }
                extra
                if case .needs(let hint) = state {
                    Text(hint)
                        .font(Memnox.sans(Memnox.TextSize.caption))
                        .foregroundStyle(IslandPalette.amber)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.horizontal, Memnox.Spacing.xLarge)
        .padding(.vertical, Memnox.Spacing.large)
        .background(tint)
    }

    /// A faint amber wash behind a step that needs the person, so the eye goes to what is left.
    private var tint: Color {
        if case .needs = state { return IslandPalette.amber.opacity(Layout.needsTint) }
        return .clear
    }
}

/// A step row's measures, kept outside it because a generic type cannot hold static ones.
private enum SetupStepLayout {
    static let titleSize: CGFloat = 13
    static let lineSpacing: CGFloat = 3
    /// Lines the mark up with the title beside it.
    static let markTopInset: CGFloat = 1
    static let needsTint = 0.07
}

extension SetupStep where Extra == EmptyView {
    init(_ title: String, detail: String, state: StepState, @ViewBuilder trailing: () -> Trailing) {
        self.init(title, detail: detail, state: state, trailing: trailing) { EmptyView() }
    }
}

/// How many steps are ready, or a green All set once every one is.
private struct ProgressPill: View {
    let ready: Int
    let total: Int

    private static let fillInk = 0.08

    var body: some View {
        let done = ready == total
        Text(done ? "All set" : "\(ready) of \(total) ready")
            .font(Memnox.sans(Memnox.TextSize.caption, .semibold))
            .foregroundStyle(done ? IslandPalette.green : Memnox.Palette.muted)
            .padding(.horizontal, Memnox.Spacing.regular)
            .padding(.vertical, Memnox.Spacing.xSmall)
            .background(Capsule().fill((done ? IslandPalette.green : Color.white).opacity(Self.fillInk)))
            .fixedSize()
    }
}

/// Done in green, waiting as an outline, and anything that needs you in the warm colour.
private struct StatusMark: View {
    let state: StepState

    private enum Layout {
        static let size: CGFloat = 16
        /// Small enough for the tick to sit well inside the mark.
        static let checkSize: CGFloat = 7.5
        static let checkSymbol = "checkmark"
        static let waitingRingInk = 0.25
    }

    var body: some View {
        switch state {
        case .done:
            Circle().fill(IslandPalette.green)
                .frame(width: Layout.size, height: Layout.size)
                .overlay(Image(systemName: Layout.checkSymbol).font(.system(size: Layout.checkSize, weight: .heavy)).foregroundStyle(Color.black))
                .transition(.scale.combined(with: .opacity))
        case .waiting:
            Circle().strokeBorder(Color.white.opacity(Layout.waitingRingInk), lineWidth: Memnox.Stroke.emphasis).frame(width: Layout.size, height: Layout.size)
        case .needs:
            Circle().fill(IslandPalette.amber)
                .frame(width: Layout.size, height: Layout.size)
                .overlay(Text("!").font(.system(size: Memnox.TextSize.micro, weight: .heavy)).foregroundStyle(Color.black))
        }
    }
}

/// A text field in the console's input style: dark, bordered, a blue ring when focused.
private struct NameField: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    private static let focusGlowRadius: CGFloat = 6
    private static let focusFade: TimeInterval = 0.15

    var body: some View {
        TextField("", text: $text, prompt: Text("Your name").foregroundStyle(Memnox.Palette.muted))
            .textFieldStyle(.plain)
            .font(Memnox.sans(Memnox.TextSize.body))
            .foregroundStyle(Memnox.Palette.foreground)
            .focused($focused)
            .padding(.horizontal, Memnox.Spacing.regular)
            .padding(.vertical, Memnox.Spacing.small)
            .frame(width: SetupLayout.fieldWidth)
            .background(RoundedRectangle(cornerRadius: SetupLayout.fieldCornerRadius, style: .continuous).fill(Color.white.opacity(Memnox.Ink.faintFill)))
            .overlay(
                RoundedRectangle(cornerRadius: SetupLayout.fieldCornerRadius, style: .continuous)
                    .strokeBorder(focused ? Memnox.Palette.primary : Color.white.opacity(SetupLayout.fieldEdgeInk), lineWidth: Memnox.Stroke.hairline)
            )
            .shadow(color: focused ? Memnox.Palette.ring : .clear, radius: Self.focusGlowRadius)
            .animation(.easeOut(duration: Self.focusFade), value: focused)
    }
}

/// Each agent on this Mac with what it said when asked, and a way to make another one the voice.
private struct AgentRows: View {
    @ObservedObject var model: SetupModel

    private enum Layout {
        static let rowSpacing: CGFloat = 6
        static let labelWidth: CGFloat = 84
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.rowSpacing) {
            ForEach(model.agents.filter(\.installed)) { agent in
                HStack(alignment: .firstTextBaseline, spacing: Memnox.Spacing.medium) {
                    Text(agent.label)
                        .font(Memnox.sans(Memnox.TextSize.caption, .semibold))
                        .foregroundStyle(Memnox.Palette.foreground)
                        .frame(width: Layout.labelWidth, alignment: .leading)
                    // One line each, so a long failure cannot stretch the window; the whole of it shows on hover.
                    Text(status(agent))
                        .font(Memnox.sans(Memnox.TextSize.caption))
                        .foregroundStyle(agent.works == false ? IslandPalette.amber : Color.white.opacity(Memnox.Ink.secondary))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(status(agent))
                    Spacer(minLength: Memnox.Spacing.small)
                    if agent.chosen {
                        Text("In use").font(Memnox.sans(Memnox.TextSize.caption, .semibold)).foregroundStyle(IslandPalette.green)
                    } else if agent.works == true {
                        Button("Use") { Task { await model.useAgent(agent.kind) } }.buttonStyle(IslandButton(primary: false))
                    }
                }
            }
            if !missing.isEmpty {
                Text("Also answers through \(missing) once installed and logged in.")
                    .font(Memnox.sans(Memnox.TextSize.caption))
                    .foregroundStyle(Memnox.Palette.muted)
            }
            HStack(spacing: Memnox.Spacing.medium) {
                Button("Check again") { Task { await model.loadAgents(recheck: true) } }
                    .buttonStyle(IslandButton(primary: false))
                    .disabled(model.checkingAgents)
                if model.checkingAgents { ProgressView().controlSize(.small) }
            }
        }
    }

    private func status(_ agent: VoiceAgentStatus) -> String {
        guard let works = agent.works else { return model.checkingAgents ? "Asking" : "Not asked yet" }
        if !works { return agent.because ?? "Did not answer" }
        return agent.sealed ? "Answers, kept to reading" : "Answers, but can run ordinary shell commands"
    }

    /// The agents the voice knows that are not on this Mac, named in one line rather than a row each.
    private var missing: String {
        let names = model.agents.filter { !$0.installed }.map(\.label)
        guard let last = names.last else { return "" }
        return names.count == 1 ? last : names.dropLast().joined(separator: ", ") + " or " + last
    }
}

/// The installed voices, best first, as a quiet menu rather than a system pop up button.
private struct VoicePicker: View {
    @ObservedObject var model: SetupModel

    private static let chevronSymbol = "chevron.up.chevron.down"
    private static let chevronSize: CGFloat = 9

    var body: some View {
        Menu {
            ForEach(model.voices, id: \.identifier) { voice in
                Button(label(voice)) { model.voiceId = voice.identifier }
            }
        } label: {
            HStack {
                Text(current).font(Memnox.sans(Memnox.TextSize.footnote)).foregroundStyle(Memnox.Palette.foreground)
                Spacer()
                Image(systemName: Self.chevronSymbol).font(.system(size: Self.chevronSize)).foregroundStyle(Memnox.Palette.muted)
            }
            .padding(.horizontal, Memnox.Spacing.regular)
            .padding(.vertical, Memnox.Spacing.small)
            .frame(width: SetupLayout.fieldWidth)
            .background(RoundedRectangle(cornerRadius: SetupLayout.fieldCornerRadius, style: .continuous).fill(Color.white.opacity(Memnox.Ink.faintFill)))
            .overlay(RoundedRectangle(cornerRadius: SetupLayout.fieldCornerRadius, style: .continuous).strokeBorder(Color.white.opacity(SetupLayout.fieldEdgeInk), lineWidth: Memnox.Stroke.hairline))
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
    /// A first height only, since the window is sized to its content once it is built.
    private static let initialHeight: CGFloat = 640

    func show(_ model: SetupModel) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: SetupLayout.width, height: Self.initialHeight),
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

/// Measures the setup card's pieces share, so the window, its fields and its pickers line up.
private enum SetupLayout {
    static let width: CGFloat = 460
    /// The name field and the voice picker are one width, so they read as one column.
    static let fieldWidth: CGFloat = 180
    static let fieldCornerRadius: CGFloat = 9
    static let fieldEdgeInk = 0.08
}
