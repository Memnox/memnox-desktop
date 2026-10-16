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
    /// Pressing keys for the person, which needs Accessibility.
    @Published var typing: StepState = .waiting
    /// Reading the screen, which needs Screen Recording.
    @Published var seeing: StepState = .waiting
    /// Whether Allow has been pressed for each, since only then is a missing grant something the person must go and do.
    /// Kept across launches, so a switch turned on before Memnox reopened is checked rather than asked for again.
    @Published private(set) var askedToType = UserDefaults.standard.bool(forKey: SetupModel.askedToTypeKey) {
        didSet { UserDefaults.standard.set(askedToType, forKey: SetupModel.askedToTypeKey) }
    }
    @Published private(set) var askedToSee = UserDefaults.standard.bool(forKey: SetupModel.askedToSeeKey) {
        didSet { UserDefaults.standard.set(askedToSee, forKey: SetupModel.askedToSeeKey) }
    }
    /// Memnox was restarted for Screen Recording and macOS still said no, which only a grant for an earlier copy does.
    @Published private(set) var seeingStale = false
    /// Reads the grants again while one still waits on the person, since switching it on sends no word back.
    private var grantWatch: Task<Void, Never>?
    /// Often enough that the row turns soon after the switch does, rarely enough to cost nothing.
    private static let grantPoll: TimeInterval = 2
    private static let nanosecondsPerSecond: TimeInterval = 1_000_000_000
    /// Whether an editor the daemon's extension goes into is on this Mac, and the editors it has landed in.
    @Published private(set) var editorsPresent = false
    @Published private(set) var editorsWithExtension: [String] = []
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
    /// Whether this Mac is connected to a workspace, asked before a phone pairs; nil when the daemon cannot say.
    var machineConnected: (() async -> Bool?)?
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
        // Coming back from System Settings is the moment a grant changed, so the rows catch up without reopening.
        becameActive = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.refreshGrants() }
    }

    private var becameActive: AnyCancellable?

    /// The grants macOS holds, read again; cheap, so it runs whenever the person comes back to the app.
    func refreshGrants() {
        listening = hearingState()
        typing = typingState()
        seeing = seeingState()
        keepWatchingGrants()
        // Never beside an ask, whose sheet this would race, and one at a time, since a read can wait on that sheet.
        guard askedToSee, !ScreenSight.allowed, asking.isEmpty, !confirmingSight else { return }
        confirmingSight = true
        Task { [weak self] in
            let granted = await ScreenSight.confirmGrant()
            guard let self else { return }
            self.confirmingSight = false
            if granted { self.seeing = self.seeingState() }
        }
    }

    /// The grants being asked for now, so a second press waits for the first rather than resets what it just added.
    @Published private(set) var asking: Set<SettingsPane> = []
    /// A ScreenCaptureKit read of the screen grant is running.
    private var confirmingSight = false

    /// Polls only while typing or seeing waits on a switch the person was sent to, and stops once both hold.
    private func keepWatchingGrants() {
        let waiting = [typing, seeing].contains { if case .needs = $0 { true } else { false } }
        guard waiting else {
            grantWatch?.cancel()
            grantWatch = nil
            return
        }
        guard grantWatch == nil else { return }
        // One read at a time, each arming the next while something still waits.
        grantWatch = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.grantPoll * Self.nanosecondsPerSecond))
            guard !Task.isCancelled, let self else { return }
            self.grantWatch = nil
            self.refreshGrants()
        }
    }

    /// What the daemon row says under its name: what is being done for it, else what it is for.
    var daemonDetail: String {
        runtime.doing.map { "\($0)…" } ?? "What your agents already talk to. Installed, started and updated for you."
    }

    /// Everything that can be checked without asking the person, checked as the card opens.
    func check() async {
        refreshGrants()
        // First, so the guide speaks in the voice Memnox keeps rather than the Mac's own before it.
        startKokoro()
        daemon = .waiting
        // Installed, started or updated here rather than told to the person, who only sees it if that fails.
        switch await runtime.ensure(conversation) {
        case .ready: daemon = .done
        case .tooOld, .unreachable, .refused: daemon = .needs(runtime.failed ?? "The Memnox service is not answering yet")
        }
        key = await keyState()
        // The daemon puts its editor extension in as it starts, so once it answers the folders say whether it landed.
        editorsPresent = EditorExtension.editorsPresent
        editorsWithExtension = EditorExtension.installedIn
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
                : "The agent you already use thinks for the voice, such as Claude Code, Codex, Cursor or Hermes, signed in with its own account. No API key needed."
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
        case .unreachable: agentsState = .needs("Waiting for the Memnox service")
        }
    }

    private func agentsState(_ found: [VoiceAgentStatus]) -> StepState {
        let installed = found.filter(\.installed)
        if installed.isEmpty {
            return .needs("Memnox brings no model of its own, so it answers through an agent you already use. Install and sign in to one of Claude Code, Codex, Cursor, Hermes or OpenClaw, then check again. No API key needed")
        }
        if let chosen = found.first(where: \.chosen), chosen.works == true { return .done }
        if installed.allSatisfy({ $0.works == nil }) { return .waiting }
        if installed.contains(where: { $0.works == true }) { return .needs("Choose the agent that answers for you") }
        return .needs("None of your agents answered. Fix one below, then check again")
    }

    /// Each grant is the person's alone: macOS shows its own sheet once and then only System Settings can. Until Allow
    /// has been pressed the row only waits, so the steps to follow appear once pressing it was not enough.
    func allowTyping() {
        askedToType = true
        typing = typingState()
        Task { await ask(.typing) }
    }

    func allowSeeing() {
        askedToSee = true
        seeing = seeingState()
        Task { await ask(.seeing) }
    }

    /// The switch shows on and macOS still says no: the entry is an earlier build's, so it is forgotten and asked for again,
    /// which puts this build in the list for the person to switch on once.
    func askAgain(_ pane: SettingsPane) async {
        // A fresh entry starts a fresh try, so the next restart is not read as the stale one again.
        if pane == .seeing { UserDefaults.standard.removeObject(forKey: Self.restartedForSeeingKey) }
        await ask(pane, forgettingEarlierBuilds: true)
    }

    /// Whether an ask for this pane is running, so its buttons wait for it rather than start another over it.
    func isAsking(_ pane: SettingsPane) -> Bool { asking.contains(pane) }

    private func ask(_ pane: SettingsPane, forgettingEarlierBuilds forget: Bool = false) async {
        guard !asking.contains(pane) else { return }
        asking.insert(pane)
        await pane.ask(forgettingEarlierBuilds: forget)
        asking.remove(pane)
        refreshGrants()
    }

    /// Typing and reading back need Accessibility, under the name this macOS gives the pane.
    private func typingState() -> StepState {
        if AXIsProcessTrusted() { return .done }
        guard askedToType else { return .waiting }
        return .needs(Self.waitingForSwitch)
    }

    /// Seeing the screen and the proof shots need Screen Recording, which macOS reads only when the app next starts.
    private func seeingState() -> StepState {
        let restarted = UserDefaults.standard.bool(forKey: Self.restartedForSeeingKey)
        if ScreenSight.allowed {
            UserDefaults.standard.removeObject(forKey: Self.restartedForSeeingKey)
            seeingStale = false
            return .done
        }
        seeingStale = restarted
        guard askedToSee else { return .waiting }
        return .needs(restarted ? "Memnox restarted and macOS still says no" : Self.waitingForSwitch)
    }

    /// What to do in System Settings, one step a line, shown under a grant that waits on the person.
    func steps(for pane: SettingsPane) -> [String] {
        switch pane {
        case .typing:
            // An ad hoc build is a new app to macOS each time it is rebuilt, so the switch can show on while doing nothing.
            let adHoc = BuildSignature.isAdHoc
                ? ["This build is signed ad hoc, so every rebuild needs this again. Run scripts/signing-setup.sh and build once more."]
                : []
            return ["In System Settings, open \(pane.title).",
                    "Switch Memnox on. If it already shows on, press Start over and switch it on again.",
                    Self.notListed] + adHoc
        case .seeing where seeingStale:
            return ["The switch that shows on belongs to an earlier copy of Memnox, or sits under \(Self.audioOnlyList), which grants sound only.",
                    "Press Start over, switch Memnox on in the top list, then restart Memnox."]
        case .seeing:
            return ["In System Settings, open \(pane.title).",
                    "Switch Memnox on in the top list, not under \(Self.audioOnlyList).",
                    Self.notListed,
                    "Press Restart Memnox, since macOS hands the grant over only when Memnox starts again."]
        }
    }

    /// The second list in the same pane, where a switch looks like the screen grant and is not.
    private static let audioOnlyList = "System Audio Recording Only"

    /// Set as Memnox restarts for Screen Recording, so a no after the restart is known to be a stale grant.
    static let restartedForSeeingKey = "restartedForSeeing"

    private static let waitingForSwitch = "Waiting for the switch in System Settings"
    /// The fallback every Mac app gives, for a list that still leaves Memnox out.
    private static let notListed = "Not in the list? Press + under it and choose Memnox in Applications."

    /// Quits and opens Memnox again, since macOS hands over a Screen Recording grant only to the next start. The name is
    /// kept first, so the first run picks up where it was with nothing retyped.
    func reopen() {
        saveName()
        if case .needs = seeing { UserDefaults.standard.set(true, forKey: Self.restartedForSeeingKey) }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { opened, _ in
            // Only once the new one is up, so a build that is not a bundle keeps the one that is running.
            guard opened != nil else { return }
            Task { @MainActor in NSApp.terminate(nil) }
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

    /// The voice is part of setting up, so it starts with the first run and runs beside the other checks; once it is
    /// in, whatever the guide held back is said in it.
    private func startKokoro() {
        // A failed install is the row's Try again to retry, never every line the guide says.
        if case .failed = kokoro.state { return }
        guard !speaksWithKokoro, !kokoroStarting else { return }
        kokoroStarting = true
        Task { [weak self] in
            await self?.useKokoro?()
            self?.kokoroStarting = false
            self?.sayHeldGuide()
        }
    }

    private var kokoroStarting = false
    /// The guide's lines waiting for Kokoro, so the first run hears one voice from start to end.
    private var heldGuide: [String] = []

    /// Says a line of the first run's guide, unless the person muted Memnox. Interrupting cuts off what it was saying,
    /// for a step changed or a row clicked; otherwise the line waits its turn. Held while Kokoro is still coming.
    func guide(_ line: String, interrupting: Bool = true) {
        guard !VoiceMute.shared.on else { return }
        startKokoro()
        // A line that follows the notch is stale by the time Kokoro is in, so only a step's own line is held.
        if kokoroStarting, !interrupting { return }
        if interrupting { heldGuide.removeAll() }
        heldGuide.append(line)
        guard !kokoroStarting else { return }
        if interrupting { voice.stop() }
        sayHeldGuide()
    }

    /// Quiet at once, for the first run closing or the person muting it.
    func stopGuide() {
        heldGuide.removeAll()
        voice.stop()
    }

    private func sayHeldGuide() {
        let lines = heldGuide
        heldGuide.removeAll()
        guard !VoiceMute.shared.on else { return }
        for line in lines { voice.queue(line) }
    }

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

    /// Opens a pairing and shows its QR, or shows and says the daemon's reason when it will not open one. A Mac not yet
    /// connected to a workspace is told where to connect before the daemon is asked, since its refusal names no page.
    func pairPhone() async {
        stopWatchingPairing()
        phone = .opening
        if await machineConnected?() == false { return failPairing(PairingLines.connectFirst) }
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
            return speaksWithKokoro ? "A natural voice, running on this Mac." : "The Mac's own voice."
        case .installing:
            // The steps and sizes stay in the log; a person setting up is told only that it takes a while.
            return "Getting your voice ready. This takes a few minutes the first time, so carry on with the rest."
        case .idle, .failed:
            return "The voice installs itself the first time. The Mac voice speaks until then."
        }
    }

    /// Whether the voice is still on its way, which holds the first run until it is in; a failed install does not,
    /// since a Mac with no connection must still be able to finish.
    var voiceStillComing: Bool {
        switch kokoro.state {
        case .idle, .installing: return true
        case .done, .failed: return false
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
    static let askedToTypeKey = "askedToType"
    static let askedToSeeKey = "askedToSee"

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
        case .anotherKey: return .needs("Memnox still trusts a Touch ID key from an earlier setup. In Terminal, run memnox voice forget-key, then press Check again")
        case .unreachable: return .needs("Waiting for the Memnox service")
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

/// What the Mac lets Memnox hear, type and see. Allow asks macOS; when that was not enough, a picture of the switch to
/// flip takes the place of a paragraph, since the two grants kept in System Settings are the ones people get stuck on.
struct SetupPermissionsCard: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(spacing: 0) {
            SetupStep("Hear you", detail: "Microphone and speech recognition, on this Mac only.", state: model.listening) {
                if model.listening != .done {
                    Button("Allow") { Task { await model.allowListening() } }.buttonStyle(KitButton(kind: .primary))
                }
            }
            SetupDivider()
            SetupStep("Type for you", detail: "Type what you confirm into your agents, and read back that it landed.", state: model.typing) {
                if case .waiting = model.typing {
                    Button("Allow") { model.allowTyping() }.buttonStyle(KitButton(kind: .primary)).disabled(model.isAsking(.typing))
                }
            } extra: {
                if case .needs = model.typing {
                    PermissionGuide(pane: .typing, steps: model.steps(for: .typing)) {
                        Button("Start over") { Task { await model.askAgain(.typing) } }
                            .buttonStyle(KitButton(kind: .secondary))
                            .disabled(model.isAsking(.typing))
                    }
                }
            }
            SetupDivider()
            SetupStep("See your screen", detail: "Read the window you ask about, and check that what it sent landed.", state: model.seeing) {
                if case .waiting = model.seeing {
                    Button("Allow") { model.allowSeeing() }.buttonStyle(KitButton(kind: .primary)).disabled(model.isAsking(.seeing))
                }
            } extra: {
                if case .needs = model.seeing {
                    PermissionGuide(pane: .seeing, steps: model.steps(for: .seeing)) {
                        // macOS hands the grant over only to the next start, so restarting is the last step there.
                        if !model.seeingStale {
                            Button("Restart Memnox") { model.reopen() }.buttonStyle(KitButton(kind: .primary))
                        }
                        Button("Start over") { Task { await model.askAgain(.seeing) } }
                            .buttonStyle(KitButton(kind: model.seeingStale ? .primary : .secondary))
                            .disabled(model.isAsking(.seeing))
                    }
                }
            }
        }
        .surface()
    }
}

/// The person's name, on the Account page beside who they are in Memnox Cloud.
struct SetupNameRow: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        SetupStep("Your name", detail: "What Memnox calls you.", state: model.nameState) {
            NameField(text: $model.name)
                .onSubmit { model.saveName() }
                .onChange(of: model.name) { _, _ in if model.isFinished { model.saveName() } }
        }
    }
}

/// The daemon and the key Touch ID signs with.
struct SetupMacCard: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(spacing: 0) {
            SetupStep("Memnox service", detail: model.daemonDetail, state: model.daemon) {
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
    /// The menu's voice choice, which adds the Mac's own voice to the picker; nil offers Kokoro alone.
    var menu: MenuModel?
    /// Whether the agent rows show once an agent already answers, since then they are detail.
    @State private var showingAgents = false

    var body: some View {
        VStack(spacing: 0) {
            SetupStep("Who answers for you", detail: model.agentsDetail, state: model.agentsState) {
                if model.agentsState == .done {
                    Button(showingAgents ? "Hide agents" : "Show agents") { showingAgents.toggle() }
                        .buttonStyle(KitButton(kind: .secondary))
                }
            } extra: {
                if model.agentsState != .done || showingAgents { AgentRows(model: model) }
            }
            SetupDivider()
            SetupStep("Voice", detail: model.voiceDetail, state: model.voiceState) {
                HStack(spacing: Memnox.Spacing.small) {
                    VoicePicker(model: model, menu: menu)
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
            // Says what the spinner is for and what speaks meanwhile, so a long download never looks stuck.
            HStack(spacing: Memnox.Spacing.medium) {
                ProgressView().controlSize(.small)
                Text("Downloading the voice. Memnox speaks with your Mac's own voice until it is in.")
                    .font(Memnox.sans(Memnox.TextSize.caption))
                    .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
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
struct NameField: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    private static let focusGlowRadius: CGFloat = 6
    private static let focusFade: TimeInterval = 0.15

    var body: some View {
        TextField("", text: $text, prompt: Text("Your name").foregroundStyle(Memnox.Palette.muted))
            .focused($focused)
            .accessibilityLabel("Your name")
            .kitField(focused: focused)
            .frame(width: SetupLayout.fieldWidth)
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
                    .kitField()
                    .frame(width: Layout.fieldWidth)
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

/// The voices, as a quiet menu rather than a system pop up button: the Mac's own first where the menu's choice is
/// given, then each Kokoro voice. One picker, so what it shows is always what speaks.
private struct VoicePicker: View {
    @ObservedObject var model: SetupModel
    var menu: MenuModel?

    private static let chevronSymbol = "chevron.up.chevron.down"
    private static let chevronSize: CGFloat = 9
    private static let macLabel = "Mac voice"

    var body: some View {
        Menu {
            if menu != nil {
                Button(Self.macLabel) { pickMac() }
                Divider()
            }
            ForEach(KokoroVoice.choices) { choice in
                Button(choice.label) { pickKokoro(choice.id) }
            }
        } label: {
            HStack {
                Text(current).font(Memnox.sans(Memnox.TextSize.callout)).foregroundStyle(Memnox.Palette.foreground)
                Spacer()
                Image(systemName: Self.chevronSymbol).font(.system(size: Self.chevronSize)).foregroundStyle(Memnox.Palette.muted)
            }
            // As tall as the name field above it, so the two read as one column.
            .padding(.horizontal, Memnox.Spacing.large)
            .frame(width: SetupLayout.fieldWidth, height: Kit.buttonHeight)
            .background(RoundedRectangle(cornerRadius: SetupLayout.fieldCornerRadius, style: .continuous).fill(Memnox.ink(Memnox.Ink.faintFill)))
            .overlay(RoundedRectangle(cornerRadius: SetupLayout.fieldCornerRadius, style: .continuous).strokeBorder(Memnox.ink(SetupLayout.fieldEdgeInk), lineWidth: Memnox.Stroke.hairline))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .pointingHand()
        .menuIndicator(.hidden)
        .help("Choose the voice Memnox speaks with")
    }

    private func pickMac() {
        guard let menu else { return }
        menu.voiceChoice = VoiceChoice.mac
        menu.chooseVoice(VoiceChoice.mac)
    }

    /// Kokoro saved first, so the voice chosen is the one that speaks once the menu switches to it.
    private func pickKokoro(_ id: String) {
        if let menu {
            menu.kokoroVoice = id
            menu.voiceChoice = VoiceChoice.kokoro
            menu.chooseVoice(VoiceChoice.kokoro)
        }
        Task { await model.pickVoice(id) }
    }

    /// The Mac's voice while it speaks; else the Kokoro voice, a voice saved before this list existed still showing its id.
    private var current: String {
        if let menu, menu.voiceChoice == VoiceChoice.mac { return Self.macLabel }
        return KokoroVoice.choices.first { $0.id == model.kokoroVoiceId }?.label ?? model.kokoroVoiceId
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
    static let fieldWidth: CGFloat = 220
    static let fieldCornerRadius: CGFloat = 9
    static let fieldEdgeInk = 0.08
}
