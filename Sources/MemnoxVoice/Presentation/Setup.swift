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

/// Where pairing a phone stands in setup, from the QR to the digits the person checks to the result.
enum PhoneStep: Equatable {
    case idle
    case opening
    case showing(qr: String)
    /// A phone reached the pairing and its digits wait on the person.
    case checking(PairingPhone)
    /// Touch ID is up for the yes.
    case approving(PairingPhone)
    case paired(name: String)
    case failed(String)
}

/// Where connecting to a server stands, from the pasted link to the digits the person types there to the result.
enum ServerStep: Equatable {
    case idle
    /// The handshake is running over the relay.
    case pairing
    /// Both ends have the digits, and the server waits for the person to type them into memnox pair.
    case showingCode(String)
    case connected(name: String)
    case failed(String)
}

/// The first run, and whenever the person opens it again from the menu bar: who they are,
/// what the Mac lets Memnox hear, whether the daemon is there, the key, and the voice.
@MainActor
final class SetupModel: ObservableObject {
    @Published var name: String
    @Published var listening: StepState = .waiting
    @Published var seeing: StepState = .waiting
    @Published var daemon: StepState = .waiting
    @Published var key: StepState = .waiting
    @Published var catchUp: Bool
    /// The agents the voice can think with, as the daemon last checked them.
    @Published var agents: [VoiceAgentStatus] = []
    @Published var agentsState: StepState = .waiting
    /// Asking every agent takes a while, so the row says it is still asking.
    @Published var checkingAgents = false
    /// The Kokoro voice picked, which is the only kind setup offers.
    @Published var kokoroVoiceId = KokoroVoice.chosen().voice
    /// Kokoro installing itself, watched so the voice row shows where it stands.
    let kokoro: KokoroInstaller
    private var watchingKokoro: AnyCancellable?
    /// The runtime installing, starting or updating itself, watched so the daemon row says which.
    let runtime: RuntimeInstaller
    private var watchingRuntime: AnyCancellable?
    /// Installs Kokoro if need be and makes it the voice, for the row's Try again.
    var useKokoro: (() async -> Void)?
    /// Where pairing a phone stands; optional, so it never counts toward ready.
    @Published var phone: PhoneStep = .idle
    /// Says a line through the orb, for a phone paired or a pairing the daemon would not open.
    var say: ((String) -> Void)?
    /// Told when a phone is paired, so the menu's devices list catches up.
    var devicesChanged: (() -> Void)?
    /// Told the Kokoro voice picked, so the daemon can hand it to a paired phone.
    var voicePicked: ((String) -> Void)?
    private let pairing: Pairing
    /// The pairing open now; cleared once it ends so a late update from it is ignored.
    private var pairingId: String?
    private var watchingPairing: Task<Void, Never>?
    /// Pairs this Mac with servers over the relay; set by the app, and nil leaves the server row out.
    var serverPairing: ServerPairing?
    /// Where connecting to a server stands; optional, so it never counts toward ready.
    @Published var server: ServerStep = .idle
    /// The memnox://pair link pasted from the server's terminal.
    @Published var serverLink = ""
    @Published var servers: [PairedMachine] = []
    /// The machine the voice and the session views talk to, nil for this Mac.
    @Published var talkingTo: String?
    /// Told when a server is paired or forgotten, so the app opens or drops its relay link.
    var serversChanged: (() -> Void)?
    /// Told the machine picked, nil for this Mac.
    var chooseMachine: ((String?) -> Void)?

    private let owner: OwnerStore
    private let conversation: Conversation
    private let voice: Voice
    private let finished: () -> Void

    init(owner: OwnerStore, conversation: Conversation, pairing: Pairing, voice: Voice, kokoro: KokoroInstaller, runtime: RuntimeInstaller,
         finished: @escaping () -> Void) {
        self.pairing = pairing
        self.kokoro = kokoro
        self.runtime = runtime
        self.owner = owner
        self.conversation = conversation
        self.voice = voice
        self.finished = finished
        name = owner.name ?? suggestedName(fullName: NSFullUserName())
        catchUp = UserDefaults.standard.object(forKey: SetupModel.catchUpKey) as? Bool ?? true
        // A nested object's changes do not reach the view on their own, so they are passed on.
        watchingKokoro = kokoro.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        watchingRuntime = runtime.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    /// What the daemon row says under its name: what is being done for it, else what it is for.
    var daemonDetail: String {
        runtime.doing.map { "\($0)…" } ?? "What your agents already talk to. Installed, started and updated for you."
    }

    /// Everything that can be checked without asking the person, checked as the card opens.
    func check() async {
        listening = hearingState()
        seeing = seeingState()
        daemon = .waiting
        // Installed, started or updated here rather than told to the person, who only sees it if that fails.
        switch await runtime.ensure(conversation) {
        case .ready: daemon = .done
        case .tooOld, .unreachable, .refused: daemon = .needs(runtime.failed ?? "The daemon is not answering yet")
        }
        key = await keyState()
        await voiceChanged()
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

    /// Both grants are the person's alone: macOS shows its own sheet once and then only System Settings can.
    func allowSeeing() {
        _ = PromptTyping.allowed()
        if !ScreenSight.allowed { _ = CGRequestScreenCaptureAccess() }
        seeing = seeingState()
    }

    /// Typing and reading back need Accessibility; seeing the screen and the proof shots need Screen Recording.
    private func seeingState() -> StepState {
        switch (AXIsProcessTrusted(), ScreenSight.allowed) {
        case (true, true): return .done
        case (false, _): return .needs("Turn on Memnox in System Settings, Privacy and Security, Accessibility")
        case (true, false): return .needs("Turn on Memnox in System Settings, Privacy and Security, Screen Recording, then reopen Memnox")
        }
    }

    func allowListening() async {
        if await Ears.askPermission() {
            listening = .done
            return
        }
        // macOS shows its sheet once per app; after a no, only System Settings can change it, so that page is opened.
        if let page = URL(string: Self.microphoneSettings) { NSWorkspace.shared.open(page) }
        listening = .needs("Turn on Memnox in System Settings, Privacy and Security, Microphone and Speech Recognition")
    }

    private static let microphoneSettings = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"

    /// Whether Kokoro is the voice speaking, as the menu bar set it.
    var speaksWithKokoro: Bool { voice.engine is KokoroVoice }

    /// Set while a sample plays, so picking quickly never stacks one sample on another.
    private var sampling = false

    /// Keeps the voice picked and, once Kokoro speaks with it, says a short line so the person hears the choice.
    func pickVoice(_ id: String) async {
        kokoroVoiceId = id
        await usePicked()
        // Only Kokoro ready and nothing mid sentence, so a sample never talks over the voice or comes from another engine.
        guard case .done = kokoro.state, speaksWithKokoro, !sampling, voice.level == 0 else { return }
        sampling = true
        defer { sampling = false }
        await voice.preview(Self.voiceSample)
    }

    /// Short enough to hear the voice without waiting on it.
    private static let voiceSample = "This is how I will sound."

    /// Picks up a voice chosen elsewhere, so the picker matches what speaks.
    func voiceChanged() async {
        kokoroVoiceId = KokoroVoice.chosen().voice
    }

    /// Keeps the picked Kokoro voice and speaks with it, switching from the Mac's voice once Kokoro is
    /// installed; while it still installs, the pick is kept for when it is ready.
    private func usePicked() async {
        KokoroVoice.choose(kokoroVoiceId)
        voicePicked?(kokoroVoiceId)
        if speaksWithKokoro {
            voice.engine = KokoroVoice(voice: kokoroVoiceId)
        } else if KokoroServer.isInstalled {
            await useKokoro?()
        }
    }

    /// Opens a pairing and shows its QR, or shows and says the daemon's reason when it will not open one.
    func pairPhone() async {
        stopWatchingPairing()
        phone = .opening
        switch await pairing.begin() {
        case .started(let invite):
            guard let qr = invite.qr else { return failPairing(PairingLines.refused) }
            pairingId = invite.id
            phone = .showing(qr: qr)
            watchPairing(invite.id)
        case .refused(let why):
            failPairing(why)
        case .unreachable:
            failPairing(PairingLines.unreachable)
        }
    }

    /// The person's yes once the digits match; a cancelled Touch ID leaves the digits up to try again.
    func approvePhone() async {
        guard case .checking(let found) = phone, let id = pairingId else { return }
        phone = .approving(found)
        switch await pairing.accept(id, phone: found) {
        case .paired(let device): pairedPhone(device.name)
        case .cancelled: phone = .checking(found)
        case .refused(let why): failPairing(why)
        case .unreachable: failPairing(PairingLines.unreachable)
        }
    }

    /// The person's no, or Cancel while the QR is up: the pairing ends and the row goes back to Pair.
    func declinePhone() async {
        guard let id = pairingId else {
            phone = .idle
            return
        }
        stopWatchingPairing()
        phone = .idle
        _ = await pairing.decline(id)
    }

    private func watchPairing(_ id: String) {
        let updates = pairing.pending(id)
        watchingPairing = Task { [weak self] in
            do {
                for try await invite in updates { self?.pairingMoved(invite) }
            } catch {
                self?.pairingLost(id)
                return
            }
            self?.pairingLost(id)
        }
    }

    private func pairingMoved(_ invite: PairingInvite) {
        guard invite.id == pairingId, let state = invite.pairingState else { return }
        switch state {
        case .waiting:
            break
        case .answered:
            // Once Touch ID is up the row stays on it, whatever else arrives.
            if case .approving = phone { return }
            if let found = invite.phone { phone = .checking(found) }
        case .paired:
            pairedPhone(invite.phone?.name ?? "")
        case .declined:
            failPairing(PairingLines.declined, aloud: false)
        case .expired:
            failPairing(PairingLines.expired, aloud: false)
        }
    }

    /// The daemon stopped answering about a pairing that was still open, so the row offers to try again.
    private func pairingLost(_ id: String) {
        guard id == pairingId else { return }
        switch phone {
        case .showing, .checking: failPairing(PairingLines.unreachable, aloud: false)
        case .idle, .opening, .approving, .paired, .failed: break
        }
    }

    private func pairedPhone(_ name: String) {
        if case .paired = phone { return }
        stopWatchingPairing()
        phone = .paired(name: name)
        say?(PairingLines.paired(name))
        devicesChanged?()
    }

    private func failPairing(_ why: String, aloud: Bool = true) {
        stopWatchingPairing()
        phone = .failed(why)
        if aloud { say?(why) }
    }

    private func stopWatchingPairing() {
        watchingPairing?.cancel()
        watchingPairing = nil
        pairingId = nil
    }

    /// Pairs with the server in the pasted link, showing the six digits to type there the moment both ends have them.
    func connectServer() async {
        let link = serverLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let serverPairing, !link.isEmpty else { return }
        server = .pairing
        let name = Host.current().localizedName ?? ServerPairingLines.thisMac
        let result = await serverPairing.connect(link: link, name: name) { [weak self] code in
            Task { @MainActor [weak self] in
                guard let self, self.server == .pairing else { return }
                self.server = .showingCode(code)
            }
        }
        switch result {
        case .connected(let paired):
            server = .connected(name: paired.machine)
            serverLink = ""
            say?(ServerPairingLines.connected(paired.machine))
        case .refused(let why):
            server = .failed(why)
        }
        servers = serverPairing.servers()
        serversChanged?()
    }

    /// Forgets a server on this Mac; it keeps this Mac's device record until it is revoked there.
    func forgetServer(_ machineId: String) {
        serverPairing?.forget(machineId)
        servers = serverPairing?.servers() ?? []
        if talkingTo == machineId { talkTo(nil) }
        serversChanged?()
    }

    /// The machine the voice and the session views talk to from now on, nil for this Mac.
    func talkTo(_ machineId: String?) {
        talkingTo = machineId
        chooseMachine?(machineId)
    }

    /// The servers as kept, read each time the card shows, so one paired from elsewhere appears.
    func loadServers() {
        servers = serverPairing?.servers() ?? []
    }

    var serverState: StepState {
        switch server {
        case .connected: return .done
        case .failed(let why): return .needs(why)
        case .idle, .pairing, .showingCode: return servers.isEmpty ? .waiting : .done
        }
    }

    /// Whether a phone's digits wait on Approve, which then takes Return from Done.
    var phoneAwaitsApproval: Bool {
        if case .checking = phone { return true }
        return false
    }

    /// How the phone row's mark reads: paired, waiting on something, or what went wrong.
    var phoneState: StepState {
        switch phone {
        case .paired: return .done
        case .failed(let why): return .needs(why)
        case .idle, .opening, .showing, .checking, .approving: return .waiting
        }
    }

    func hear() async {
        await usePicked()
        let first = name.trimmingCharacters(in: .whitespaces)
        await voice.preview("Hi \(first.isEmpty ? "there" : first), I am Memnox. Press Option Space whenever you want me.")
    }

    /// Whether the Mac voice standing in for Kokoro is Premium or Enhanced, which sound like a person.
    var naturalVoice: Bool {
        guard let chosen = voice.identifier.flatMap(AVSpeechSynthesisVoice.init(identifier:)) else { return false }
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
            return speaksWithKokoro ? "Kokoro, a natural voice running on this Mac." : "The Mac's own voice, as picked in the menu bar."
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

    /// Keeps the name as it is typed once setup has been done, since Settings has no Done to press.
    func saveName() {
        let chosen = name.trimmingCharacters(in: .whitespaces)
        guard !chosen.isEmpty else { return }
        owner.name = chosen
    }

    /// Keeps catch up the moment it is switched, for the same reason.
    func saveCatchUp() {
        UserDefaults.standard.set(catchUp, forKey: SetupModel.catchUpKey)
    }

    /// Whether the first run has been finished, which is when Settings stops asking for Done.
    var isFinished: Bool { UserDefaults.standard.bool(forKey: SetupModel.doneKey) }

    /// The name as a step: done once there is one.
    var nameState: StepState { name.trimmingCharacters(in: .whitespaces).isEmpty ? .waiting : .done }

    func finish() {
        let chosen = name.trimmingCharacters(in: .whitespaces)
        owner.name = chosen.isEmpty ? nil : chosen
        UserDefaults.standard.set(catchUp, forKey: SetupModel.catchUpKey)
        UserDefaults.standard.set(true, forKey: SetupModel.doneKey)
        Task {
            await usePicked()
            finished()
        }
    }

    static let doneKey = "setupDone"
    static let catchUpKey = "catchUp"

    private func hearingState() -> StepState {
        let microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let speech = SFSpeechRecognizer.authorizationStatus() == .authorized
        return microphone && speech ? .done : .waiting
    }

    private func keyState() async -> StepState {
        // Made once at launch; a Mac that could not make it has nothing to register, whatever the daemon is.
        guard conversation.canSign else {
            return .needs("This Mac could not make a Touch ID key. Check Touch ID is set up in System Settings, then quit and reopen Memnox")
        }
        switch await conversation.registerKey() {
        case .registered: return .done
        case .anotherKey: return .needs("Another key is trusted. Run memnox voice forget-key, then check again")
        case .unreachable: return .needs("Waiting for the daemon")
        case .tooOld: return .needs("Waiting for a Memnox that knows voice")
        case .refused(let why): return .needs(why)
        }
    }
}

/// Setup's steps as cards the Settings window hosts on its pages, each a short group rather than one long sheet.
private enum SetupCardLayout {
    static let dividerInk = 0.06
    /// Lines a divider up with the titles rather than the marks, as System Settings does.
    static let dividerInset: CGFloat = 44
    static let stepChange: TimeInterval = 0.25
    static let playSymbol = "play.fill"
}

/// The hairline between two steps on a card.
private struct SetupDivider: View {
    var body: some View {
        Rectangle()
            .fill(Memnox.ink(SetupCardLayout.dividerInk))
            .frame(height: Memnox.Stroke.hairline)
            .padding(.leading, SetupCardLayout.dividerInset)
    }
}

/// Who the person is and what the Mac lets Memnox hear and see.
struct SetupYouCard: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(spacing: 0) {
            SetupStep("Your name", detail: "What I call you.", state: model.nameState) {
                NameField(text: $model.name)
                    .onSubmit { model.saveName() }
                    .onChange(of: model.name) { _, _ in if model.isFinished { model.saveName() } }
            }
            SetupDivider()
            SetupStep("Hear you", detail: "Microphone and speech recognition, on this Mac only.", state: model.listening) {
                if model.listening != .done {
                    Button("Allow") { Task { await model.allowListening() } }.buttonStyle(KitButton(kind: .primary))
                }
            }
            SetupDivider()
            SetupStep("See and act", detail: "Read your screen when you ask, and check that what it sent landed.", state: model.seeing) {
                if model.seeing != .done {
                    Button("Allow") { model.allowSeeing() }.buttonStyle(KitButton(kind: .primary))
                }
            }
        }
        .surface()
    }
}

/// The daemon and the key Touch ID signs with.
struct SetupMacCard: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(spacing: 0) {
            SetupStep("Memnox daemon", detail: model.daemonDetail, state: model.daemon) {
                if model.daemon != .done { checkAgain }
            }
            .tile(MemnoxTile())
            SetupDivider()
            SetupStep("Touch ID", detail: "Your finger approves anything outside a session's repository. Saying no needs only your voice.", state: model.key) {
                if model.key != .done { checkAgain }
            }
            .tile(IconTile(symbol: "touchid"))
        }
        .surface()
    }

    private var checkAgain: some View {
        Button("Check again") { Task { await model.check() } }.buttonStyle(KitButton(kind: .secondary))
    }
}

/// Pairing a phone: Pair, the code to scan, the digits to approve, and the result.
struct SetupPhoneCard: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        SetupStep("Pair a phone", detail: "Optional. Answer your agents and talk to Memnox from your iPhone.", state: model.phoneState) {
            phoneButton
        } extra: {
            PhoneExtra(model: model)
        }
        .surface()
    }

    /// Pair to start, Cancel while the QR waits, Try again after a failure, and nothing once paired.
    @ViewBuilder private var phoneButton: some View {
        switch model.phone {
        case .idle, .paired:
            Button("Pair") { Task { await model.pairPhone() } }.buttonStyle(KitButton(kind: .secondary))
        case .failed:
            Button("Try again") { Task { await model.pairPhone() } }.buttonStyle(KitButton(kind: .secondary))
        case .showing:
            Button("Cancel") { Task { await model.declinePhone() } }.buttonStyle(KitButton(kind: .secondary))
        case .opening, .checking, .approving:
            EmptyView()
        }
    }
}

/// Connecting to a server: the link pasted from memnox pair, the digits to type there, and the servers kept.
struct SetupServerCard: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        SetupStep("Connect to a server",
                  detail: "Optional. Talk to Memnox on a Linux server through the relay. Run memnox pair there and paste the link it prints.",
                  state: model.serverState) {
            serverButton
        } extra: {
            ServerExtra(model: model)
        }
        .surface()
        .onAppear { model.loadServers() }
    }

    @ViewBuilder private var serverButton: some View {
        switch model.server {
        case .idle, .connected, .failed:
            Button("Connect") { Task { await model.connectServer() } }
                .buttonStyle(KitButton(kind: .secondary))
                .disabled(model.serverLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        case .pairing, .showingCode:
            ProgressView().controlSize(.small)
        }
    }
}

/// Which agent thinks for the voice, and the voice itself with a way to hear it.
struct SetupVoiceCard: View {
    @ObservedObject var model: SetupModel
    /// Whether the agent rows show once an agent already answers, since then they are detail.
    @State private var showingAgents = false

    var body: some View {
        VStack(spacing: 0) {
            SetupStep("Who answers for you", detail: model.agentsDetail, state: model.agentsState) {
                if model.agentsState == .done {
                    Button(showingAgents ? "Hide" : "Details") { showingAgents.toggle() }
                        .buttonStyle(KitButton(kind: .secondary))
                }
            } extra: {
                if model.agentsState != .done || showingAgents { AgentRows(model: model) }
            }
            SetupDivider()
            SetupStep("Voice", detail: model.voiceDetail, state: model.voiceState) {
                HStack(spacing: Memnox.Spacing.small) {
                    VoicePicker(model: model)
                    Button { Task { await model.hear() } } label: {
                        Image(systemName: SetupCardLayout.playSymbol)
                    }
                    .buttonStyle(KitButton(kind: .secondary))
                    .help("Hear it")
                    .accessibilityLabel("Hear it")
                }
            } extra: {
                voiceExtra
            }
        }
        .surface()
        .animation(.easeInOut(duration: SetupCardLayout.stepChange), value: showingAgents)
    }

    @ViewBuilder private var voiceExtra: some View {
        switch model.kokoro.state {
        case .installing:
            ProgressView().controlSize(.small)
        case .failed:
            HStack(spacing: Memnox.Spacing.medium) {
                Button("Try again") { Task { await model.useKokoro?() } }.buttonStyle(KitButton(kind: .secondary))
                if !model.naturalVoice {
                    Button("Get a Mac voice instead") { model.openVoiceSettings() }.buttonStyle(KitButton(kind: .secondary))
                }
            }
        case .idle, .done:
            EmptyView()
        }
    }
}

/// Catching the person up after time away, kept the moment it is switched.
struct SetupCatchUpRow: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        SwitchRow(symbol: "clock.arrow.circlepath", title: "Catch me up", detail: "What my agents did while I was away",
                  isOn: Binding(get: { model.catchUp }, set: { model.catchUp = $0; model.saveCatchUp() }))
    }
}

/// The mark a step shows in the overview's checklist, the same as on its card.
struct SetupMark: View {
    let state: StepState

    var body: some View { StatusMark(state: state) }
}

/// One row of the checklist: its mark, its title and a line on what it is, the control on the right,
/// anything longer underneath, and what to do in words when it needs the person.
private struct SetupStep<Trailing: View, Extra: View>: View {
    let title: String
    let detail: String
    let state: StepState
    let trailing: Trailing
    let extra: Extra
    /// What the row is about, on a bordered tile at its start; with one, the checkbox moves to the end of the row.
    var tile: AnyView?

    private typealias Layout = SetupStepLayout

    init(_ title: String, detail: String, state: StepState, @ViewBuilder trailing: () -> Trailing, @ViewBuilder extra: () -> Extra) {
        self.title = title
        self.detail = detail
        self.state = state
        self.trailing = trailing()
        self.extra = extra()
    }

    var body: some View {
        HStack(alignment: tile == nil ? .top : .center, spacing: Memnox.Spacing.large) {
            if let tile { tile } else { StatusMark(state: state).padding(.top, Layout.markTopInset) }
            VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
                HStack(alignment: .center, spacing: Memnox.Spacing.large) {
                    VStack(alignment: .leading, spacing: Layout.lineSpacing) {
                        Text(title)
                            .font(Memnox.sans(Layout.titleSize, .semibold))
                            .foregroundStyle(Memnox.Palette.ink)
                        Text(detail)
                            .font(Memnox.sans(Memnox.TextSize.caption))
                            .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    trailing
                    if tile != nil, state == .done { StatusMark(state: state) }
                }
                extra
                if case .needs(let hint) = state {
                    Label(hint, systemImage: "exclamationmark.circle")
                        .font(Memnox.sans(Memnox.TextSize.caption, .medium))
                        .foregroundStyle(Memnox.ink(Memnox.Ink.primary))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.horizontal, Memnox.Spacing.xLarge)
        .padding(.vertical, Memnox.Spacing.large)
    }
}

/// A step row's measures, kept outside it because a generic type cannot hold static ones.
private enum SetupStepLayout {
    static let titleSize: CGFloat = 13
    static let lineSpacing: CGFloat = 3
    /// Lines the mark up with the title beside it.
    static let markTopInset: CGFloat = 1
}

extension SetupStep {
    /// The same row with a tile at its start.
    func tile<Tile: View>(_ view: Tile) -> SetupStep {
        var copy = self
        copy.tile = AnyView(view)
        return copy
    }
}

extension SetupStep where Extra == EmptyView {
    init(_ title: String, detail: String, state: StepState, @ViewBuilder trailing: () -> Trailing) {
        self.init(title, detail: detail, state: state, trailing: trailing) { EmptyView() }
    }
}

/// The voiceos checkbox: filled and ticked once done, an empty square while waiting, and marked when it needs you.
struct StatusMark: View {
    let state: StepState

    var body: some View { CheckBox(state: state) }
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
            .background(RoundedRectangle(cornerRadius: SetupLayout.fieldCornerRadius, style: .continuous).fill(Memnox.ink(Memnox.Ink.faintFill)))
            .overlay(
                RoundedRectangle(cornerRadius: SetupLayout.fieldCornerRadius, style: .continuous)
                    .strokeBorder(focused ? Memnox.ink(Memnox.Ink.secondary) : Memnox.ink(SetupLayout.fieldEdgeInk), lineWidth: Memnox.Stroke.hairline)
            )
            .shadow(color: focused ? Memnox.ink(Memnox.Ink.fill) : .clear, radius: Self.focusGlowRadius)
            .animation(.easeOut(duration: Self.focusFade), value: focused)
    }
}

/// Each agent on this Mac with what it said when asked, and a way to make another one the voice.
private struct AgentRows: View {
    @ObservedObject var model: SetupModel

    private enum Layout {
        static let rowSpacing: CGFloat = 8
        static let labelWidth: CGFloat = 84
        static let logoSide: CGFloat = 24
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.rowSpacing) {
            ForEach(model.agents.filter(\.installed)) { agent in
                HStack(alignment: .center, spacing: Memnox.Spacing.medium) {
                    BrandLogo(agent: agent.kind, name: agent.label, size: Layout.logoSide)
                    Text(agent.label)
                        .font(Memnox.sans(Memnox.TextSize.caption, .semibold))
                        .foregroundStyle(Memnox.Palette.foreground)
                        .frame(width: Layout.labelWidth, alignment: .leading)
                    // One line each, so a long failure cannot stretch the window; the whole of it shows on hover.
                    Text(status(agent))
                        .font(Memnox.sans(Memnox.TextSize.caption))
                        .foregroundStyle(Memnox.ink(agent.works == false ? Memnox.Ink.primary : Memnox.Ink.secondary))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(status(agent))
                    Spacer(minLength: Memnox.Spacing.small)
                    if agent.chosen {
                        Text("In use").font(Memnox.sans(Memnox.TextSize.caption, .semibold)).foregroundStyle(IslandPalette.green)
                    } else if agent.works == true {
                        Button("Use") { Task { await model.useAgent(agent.kind) } }.buttonStyle(KitButton(kind: .secondary))
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
                    .buttonStyle(KitButton(kind: .secondary))
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

/// Under the phone row: the QR to scan, then the phone's name and digits to approve, then the result.
private struct PhoneExtra: View {
    @ObservedObject var model: SetupModel

    private enum Layout {
        static let qrSize: CGFloat = 148
        /// The white margin a reader needs around the code to find its edges.
        static let quietZone: CGFloat = 10
        static let qrCornerRadius: CGFloat = 10
        static let codeSize: CGFloat = 26
        /// The digits shown in two groups of this many, the way a phone shows a code.
        static let codeGroup = 3
        static let codeTracking: CGFloat = 2
    }

    var body: some View {
        switch model.phone {
        case .opening:
            ProgressView().controlSize(.small)
        case .showing(let qr):
            HStack(alignment: .center, spacing: Memnox.Spacing.xLarge) {
                code(qr)
                VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
                    Text("Scan this with the Memnox app on your iPhone.")
                        .font(Memnox.sans(Memnox.TextSize.caption))
                        .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                    // The same pairing as a link, for a simulator with no camera or a phone that cannot scan.
                    Button("Copy link") { copy(qr) }.buttonStyle(KitButton(kind: .secondary))
                }
            }
        case .checking(let phone), .approving(let phone):
            checking(phone)
        case .paired(let name):
            Text(PairingLines.paired(name))
                .font(Memnox.sans(Memnox.TextSize.caption, .semibold))
                .foregroundStyle(IslandPalette.green)
        case .idle, .failed:
            EmptyView()
        }
    }

    @ViewBuilder private func code(_ qr: String) -> some View {
        if let image = QRImage.make(qr) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .frame(width: Layout.qrSize, height: Layout.qrSize)
                .padding(Layout.quietZone)
                .background(RoundedRectangle(cornerRadius: Layout.qrCornerRadius, style: .continuous).fill(Color.white))
        } else {
            Text("The code could not be drawn. Try again.")
                .font(Memnox.sans(Memnox.TextSize.caption))
                .foregroundStyle(Memnox.ink(Memnox.Ink.primary))
        }
    }

    private func checking(_ phone: PairingPhone) -> some View {
        let approving: Bool
        if case .approving = model.phone { approving = true } else { approving = false }
        return VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            Text(phone.name)
                .font(Memnox.sans(Memnox.TextSize.footnote, .semibold))
                .foregroundStyle(Memnox.Palette.foreground)
            Text(grouped(phone.code))
                .font(.system(size: Layout.codeSize, weight: .semibold, design: .monospaced))
                .tracking(Layout.codeTracking)
                .foregroundStyle(Memnox.Palette.ink)
                .textSelection(.enabled)
            Text("Approve if your iPhone shows the same digits.")
                .font(Memnox.sans(Memnox.TextSize.caption))
                .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
            HStack(spacing: Memnox.Spacing.medium) {
                // No Return shortcut, since letting a phone in must be a click made after comparing the digits.
                Button("Approve") { Task { await model.approvePhone() } }
                    .buttonStyle(KitButton(kind: .primary))
                    .disabled(approving)
                Button("Decline") { Task { await model.declinePhone() } }
                    .buttonStyle(KitButton(kind: .secondary))
                    .disabled(approving)
                if approving { ProgressView().controlSize(.small) }
            }
        }
    }

    private func copy(_ link: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
    }

    /// "482913" as "482 913", so six digits read at a glance.
    private func grouped(_ digits: String) -> String {
        guard digits.count > Layout.codeGroup else { return digits }
        return "\(digits.prefix(Layout.codeGroup)) \(digits.dropFirst(Layout.codeGroup))"
    }
}

/// Under the server row: the field for the link, the digits to type on the server, and each server kept,
/// with which one the voice talks to and a way to forget it.
private struct ServerExtra: View {
    @ObservedObject var model: SetupModel

    private enum Layout {
        static let codeSize: CGFloat = 26
        static let codeGroup = 3
        static let codeTracking: CGFloat = 2
        static let fieldWidth: CGFloat = 320
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            switch model.server {
            case .idle, .connected, .failed:
                TextField("", text: $model.serverLink, prompt: Text("memnox://pair?d=...").foregroundStyle(Memnox.Palette.muted))
                    .textFieldStyle(.plain)
                    .font(Memnox.sans(Memnox.TextSize.caption))
                    .foregroundStyle(Memnox.Palette.foreground)
                    .padding(.horizontal, Memnox.Spacing.regular)
                    .padding(.vertical, Memnox.Spacing.small)
                    .frame(width: Layout.fieldWidth)
                    .background(RoundedRectangle(cornerRadius: SetupLayout.fieldCornerRadius, style: .continuous).fill(Memnox.ink(Memnox.Ink.faintFill)))
                    .onSubmit { Task { await model.connectServer() } }
            case .pairing:
                Text("Meeting the server through the relay.")
                    .font(Memnox.sans(Memnox.TextSize.caption))
                    .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
            case .showingCode(let code):
                Text(grouped(code))
                    .font(.system(size: Layout.codeSize, weight: .semibold, design: .monospaced))
                    .tracking(Layout.codeTracking)
                    .foregroundStyle(Memnox.Palette.ink)
                    .textSelection(.enabled)
                Text(ServerPairingLines.typeCode)
                    .font(Memnox.sans(Memnox.TextSize.caption))
                    .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
            }
            if case .connected(let name) = model.server {
                Text(ServerPairingLines.connected(name))
                    .font(Memnox.sans(Memnox.TextSize.caption, .semibold))
                    .foregroundStyle(IslandPalette.green)
            }
            if !model.servers.isEmpty {
                machineRow(ServerPairingLines.thisMac, id: nil)
                ForEach(model.servers, id: \.machineId) { server in
                    machineRow(server.machine, id: server.machineId)
                }
            }
        }
    }

    /// One machine: its name, whether the voice talks to it, and Forget for a server.
    private func machineRow(_ name: String, id: String?) -> some View {
        HStack(spacing: Memnox.Spacing.medium) {
            Text(name)
                .font(Memnox.sans(Memnox.TextSize.footnote, .semibold))
                .foregroundStyle(Memnox.Palette.foreground)
            Spacer(minLength: Memnox.Spacing.small)
            if model.talkingTo == id {
                Text("Talking to it")
                    .font(Memnox.sans(Memnox.TextSize.caption))
                    .foregroundStyle(IslandPalette.green)
            } else {
                Button("Talk to it") { model.talkTo(id) }.buttonStyle(KitButton(kind: .secondary))
            }
            if let id {
                Button("Forget") { model.forgetServer(id) }.buttonStyle(KitButton(kind: .secondary))
            }
        }
    }

    /// "482913" as "482 913", so six digits read at a glance.
    private func grouped(_ digits: String) -> String {
        guard digits.count > Layout.codeGroup else { return digits }
        return "\(digits.prefix(Layout.codeGroup)) \(digits.dropFirst(Layout.codeGroup))"
    }
}

/// Kokoro's voices, as a quiet menu rather than a system pop up button.
private struct VoicePicker: View {
    @ObservedObject var model: SetupModel

    private static let chevronSymbol = "chevron.up.chevron.down"
    private static let chevronSize: CGFloat = 9

    var body: some View {
        Menu {
            ForEach(KokoroVoice.choices) { choice in
                Button(choice.label) { Task { await model.pickVoice(choice.id) } }
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
            .background(RoundedRectangle(cornerRadius: SetupLayout.fieldCornerRadius, style: .continuous).fill(Memnox.ink(Memnox.Ink.faintFill)))
            .overlay(RoundedRectangle(cornerRadius: SetupLayout.fieldCornerRadius, style: .continuous).strokeBorder(Memnox.ink(SetupLayout.fieldEdgeInk), lineWidth: Memnox.Stroke.hairline))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .pointingHand()
        .menuIndicator(.hidden)
        .help("Choose the Kokoro voice, which speaks once picked")
    }

    /// A voice saved before this list existed still shows its Kokoro id rather than nothing.
    private var current: String {
        KokoroVoice.choices.first { $0.id == model.kokoroVoiceId }?.label ?? model.kokoroVoiceId
    }
}

/// The first run walks through the onboarding until it is finished; after that, setup lives in the Settings window as
/// its Overview and its pages. Both read the one model, so a grant made in either shows in the other.
@MainActor
final class SetupWindow {
    func show(_ model: SetupModel) {
        SettingsWindow.shared.setup = model
        if model.isFinished {
            SettingsWindow.shared.show()
        } else {
            OnboardingWindow.shared.show(model)
        }
    }

    func close() {
        OnboardingWindow.shared.close()
        SettingsWindow.shared.close()
    }
}

/// Measures the setup card's pieces share, so the window, its fields and its pickers line up.
private enum SetupLayout {
    /// The name field and the voice picker are one width, so they read as one column.
    static let fieldWidth: CGFloat = 180
    static let fieldCornerRadius: CGFloat = 9
    static let fieldEdgeInk = 0.08
}
