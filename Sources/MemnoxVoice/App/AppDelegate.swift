import AppKit
import MemnoxVoiceCore

/// How long to wait before subscribing again after the daemon went away.
private let resubscribeSeconds: TimeInterval = 2
private let nanosecondsPerSecond: TimeInterval = 1_000_000_000

/// Wires the face, the ears and the voice to the conversation, and keeps one ear on the daemon
/// for anything that starts waiting on the person.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let audio = AudioIO()
    private let ears = Ears()
    private let wake = WakeEars()
    private let barge = BargeEars()
    /// Control and Option held down: a rule said for as long as they are held.
    private let holdKeys = HoldKeys()
    private let dictationKey = DictationKey()
    /// The person's dictionary and latest dictations, on this Mac only.
    let dictations = DictationStore()
    private lazy var polish = DictationPolish(link: link)
    /// Off unless the person turns it on: news that needs nobody stays quiet until they call Memnox.
    private static let speakUpKey = "speakUp"
    /// On unless turned off: cutting in by speaking over the voice.
    private static let bargeKey = "talkOver"
    /// Kokoro or the Mac's own voice, as picked in the menu bar panel.
    private static let voiceChoiceKey = "voiceChoice"
    private let kokoro = KokoroServer()
    /// Puts Kokoro on this Mac the first time, so the natural voice is the default with nothing to run.
    private let kokoroInstaller = KokoroInstaller()
    private let runtime = RuntimeInstaller()
    /// The setup card while it is open, told when the voice changes so its picker lists the right voices.
    private weak var setupModel: SetupModel?
    /// Off until the person turns it on, since it keeps the microphone open whenever the orb is idle.
    private static let wakeKey = "wakeOnName"
    /// On unless turned off: what the person says shows in the notch word by word as it is heard.
    private static let liveWordsKey = "liveWords"
    /// On unless turned off: words reach a session without its window coming forward, so the person stays where they are.
    private static let stayPutKey = "deliverInBackground"
    private let link = UnixSocketLink()
    /// One id source for every request, since a relay session refuses an id already in flight.
    private let ids = RequestIds()
    /// This Mac's daemon, or a server picked in setup: what the voice and the session views talk to.
    private lazy var target = TargetLink(local: link)
    /// The presenter the conversation and the island use, which only shows a server's sessions and never acts on them.
    private lazy var shown = TargetPresenter(presenter) { [target] in target.isRemote }
    /// The servers paired over the relay, each record holding this Mac's Noise key for it.
    private let servers = KeychainPairedServers()
    /// One relay link per server, kept while it stays paired, so its held calls arrive whichever machine is picked.
    private var relays: [String: NoiseRelayLink] = [:]
    /// The subscription to each server, by machine id, beside the one to this Mac's own daemon.
    private var listening: [String: Task<Void, Never>] = [:]
    private var serverPairing: ServerPairing!
    /// Memnox Cloud for the person signed in on this Mac; a different deployment is set under this defaults key.
    private static let cloudKey = "cloudURL"
    private let cloud = HttpWorkspaceInbox(base: UserDefaults.standard.string(forKey: AppDelegate.cloudKey).flatMap(URL.init(string:)) ?? HttpWorkspaceInbox.defaultBase)
    /// The team credential, in its own Keychain item apart from the paired servers.
    private let personCredential = KeychainPersonCredential()
    /// Teammates' calls the workspace routed to the person, answered through it and never through a daemon.
    private var teamCalls: WorkspaceAnswering!
    private var account: AccountModel?
    private var readingInbox: Task<Void, Never>?
    /// Often enough that a teammate is not kept waiting, rarely enough to stay quiet on the network.
    private static let inboxEvery: TimeInterval = 20
    /// The machine picked, by its id; absent is this Mac.
    private static let machineKey = "talkingTo"
    // Set once in applicationDidFinishLaunching, before anything can reach them.
    private var panel: IslandPanel!
    private var preview: IslandPreview?
    private var voice: Voice!
    private var conversation: Conversation!
    /// Pairs phones and looks after the devices paired, signing with the same key as the conversation.
    private var pairing: Pairing!
    private var hotkey: Hotkey?
    private let owner = DefaultsOwner()
    private let presenter = SessionPresenter()
    private let chimes = SystemChimes()
    private let frontApp = FrontApp()
    /// When the screen locked, so coming back after a while can be caught up on.
    private var awaySince: Date?
    /// Long enough that a coffee counts and a glance away does not.
    private static let awayLongEnough: TimeInterval = 10 * 60
    /// The system's own announcements that the screen locked and unlocked.
    private static let screenLocked = Notification.Name("com.apple.screenIsLocked")
    private static let screenUnlocked = Notification.Name("com.apple.screenIsUnlocked")
    private let setup = SetupWindow()
    private var menuBar: MenuBarPanel?
    private var menu: MenuModel?
    /// The home the window opens on, read again when the stream says what it counts has changed.
    private var home: HomeModel?
    /// The held calls not yet settled, counted for the menu's Need you since the island shows only one at a time.
    private var waitingCalls = Set<String>()
    /// Turns run one after another, so a held call never talks over an answer.
    private var tail: Task<Void, Never>?
    /// Touch ID sheets one after another, apart from the conversation, since two at once collide.
    private var confirmations: Task<Void, Never>?
    private var talking = false
    /// Turns queued or running, since the name is only listened for when there are none.
    private var turns = 0
    /// A phone holds the voice, so the Mac does not answer to its name and the phone hears it alone.
    private var phoneHoldsVoice = false

    /// How long the microphone stays open for a follow up after an answer, long enough to think one up.
    private static let followUpSeconds: TimeInterval = 15
    /// How long it waits for the rest when the brain thought they stopped mid thought; past it, what they said is answered as it stands.
    private static let restOfThoughtSeconds: TimeInterval = 6
    /// A request this long already says what to do, so a hold on it waits only a breath for more.
    private static let longRequestWords = 8
    private static let briefRestSeconds: TimeInterval = 2.5

    private static func restOfThought(after said: String) -> TimeInterval {
        said.split(whereSeparator: \.isWhitespace).count >= longRequestWords ? briefRestSeconds : restOfThoughtSeconds
    }
    private static let firstWordSeconds: TimeInterval = 10

    func applicationDidFinishLaunching(_ notification: Notification) {
        Appearance.apply()
        // The island on its own, touring its states, with nothing listening and no daemon needed.
        if IslandPreview.requested {
            panel = IslandPanel(loudness: { IslandPreview.level })
            let preview = IslandPreview(panel: panel)
            self.preview = preview
            preview.start()
            return
        }
        // Opened from the disk image: the copy in Applications takes over, since only it can keep its permissions.
        if ApplicationsFolder.moveIfOutside() { return }
        // Before anything reads the Kokoro voice, so the first sentence is already in Sky.
        KokoroVoice.adoptSkyOnce()
        let voice = Voice()
        voice.route = audio
        self.voice = voice
        VoiceMute.shared.voice = voice
        panel = IslandPanel(loudness: { [audio] in max(audio.micLevel, voice.level) })
        ears.hearing = { [weak self] words in
            self?.panel.show(.listening, caption: caption(words))
            self?.panel.hearing(words)
        }
        ears.guessing = { [weak self] words in
            Task { @MainActor [weak self] in
                guard let self, let mine = self.ownWordsOnly(words) else { return }
                await self.conversation?.guess(mine)
            }
        }
        ears.missed = { [weak self] in
            self?.panel.show(.listening, caption: "Sorry, say that again?")
        }
        Task { [ears] in await ears.prepare() }
        let key: ConfirmKey
        do {
            key = ForegroundKey(try SecureEnclaveConfirmKey())
        } catch {
            // No Secure Enclave or no keychain: nothing can ever be confirmed from this Mac.
            NSLog("Memnox: no confirmation key, so allows stay in the terminal: \(error)")
            key = RefusingKey()
        }
        teamCalls = WorkspaceAnswering(inbox: cloud, store: personCredential, key: key)
        conversation = Conversation(
            link: target, speaker: voice, key: key, face: panel, owner: owner, presenter: shown, chimes: chimes,
            adHocBuild: BuildSignature.isAdHoc,
            address: { chosenAddress() },
            name: { chosenName() },
            lookingAt: { [frontApp] in frontApp.name },
            lookingAtWindow: { [frontApp] in frontApp.windowTitle },
            ids: ids,
            // A server never takes a yes without a signature, whatever the event says.
            signsEveryYes: { [target] subject in target.reachesAnotherMachine(subject: subject) },
            raisedOn: { [target] subject in target.machine(for: subject)?.serverName },
            workspace: teamCalls
        )
        // A team's question answered by voice leaves the island the way a press of its button does.
        conversation.teamAnswered = { [weak self] subject, outcome in
            Task { @MainActor [weak self] in
                self?.panel.answered(subject, outcome)
                self?.teamForget(subject)
            }
        }
        let account = AccountModel(signIn: WorkspaceSignIn(inbox: cloud, store: personCredential, key: key))
        account.changed = { [weak self] in self?.readInbox() }
        // The daemon keeps its own sign in, the one the voice acts through, so the page offers it beside this app's.
        account.daemon = DaemonAccountModel(signIn: DaemonSignIn(link: link, ids: ids))
        // And this Mac's own connection to the workspace, which is what the rules, memory and phone pairing read.
        // A workspace with no name yet reads as no name, never as the person.
        account.machine = DaemonAccountModel(signIn: DaemonSignIn(link: link, side: .machine, ids: ids), unnamed: "")
        // Too old is answered with Update, which the app does itself, rather than with a step for a terminal.
        let update: () async -> Void = { [weak self] in
            guard let self, let conversation = self.conversation else { return }
            await self.runtime.updateNow(conversation)
        }
        account.daemon?.update = update
        account.machine?.update = update
        self.account = account
        SettingsWindow.shared.account = account
        SettingsWindow.shared.dictations = dictations
        // Phones pair with this Mac's own daemon, whichever machine the voice talks to.
        pairing = Pairing(link: link, key: key, ids: ids)
        serverPairing = ServerPairing(
            pairer: RelayPairer(dialer: WebSocketDialer(), key: ReasonedKey(key, reason: ServerPairingLines.proofReason), kind: IntroducedKind.desktop),
            store: servers
        )
        restoreMachine()
        presenter.livePanel.fetch = { [weak self] session in await self?.conversation.sessionView(session) }
        presenter.livePanel.diff = { [weak self] session, path in await self?.conversation.sessionDiff(session, path: path) }
        presenter.livePanel.island = panel.islandModel
        presenter.remote = { [target] in target.isRemote }
        presenter.sessions = { [weak self] in await self?.conversation.sessionsList() ?? [] }
        presenter.orbFrame = { [weak self] in self?.panel.orbFrame }
        presenter.inBackground = { UserDefaults.standard.bool(forKey: Self.stayPutKey) }
        presenter.frontApp = { [frontApp] in frontApp.name }
        presenter.personsApp = { [frontApp] in frontApp.running }
        presenter.corrected = { [weak self] typed, sent in
            Task { await self?.conversation.learn(typed: typed, sent: sent) }
        }
        panel.wire(
            answer: { [weak self] card, answer in self?.answerHeld(card, answer) },
            answerQuestion: { [weak self] card, number, answer in self?.answerQuestion(card, number: number, answer: answer) },
            tapped: { [weak self] in self?.tappedIsland() }
        )
        panel.wireSessions(
            list: { [weak self] in await self?.conversation.sessionsList() ?? [] },
            view: { [weak self] session in await self?.conversation.sessionView(session) },
            open: { [shown] session, host in Task { _ = await shown.focus(session: session, host: host) } }
        )
        panel.wireLive { [presenter] session, host in Task { await presenter.live(session: session, host: host) } }
        panel.keepHistory(in: HistoryFile())
        panel.wireConversation(
            openAnswer: { [presenter] exchange in
                Task { await presenter.card(SummaryCard(title: exchange.question, text: exchange.answer)) }
            },
            answerDraft: { [weak self] card, send in self?.answerDraft(card, send: send) },
            answerWork: { [weak self] card, send in self?.answerWork(card, send: send) },
            openSignIn: { [weak self] tool in self?.openSignIn(tool) },
            notMine: { [weak self] card in self?.notMine(card) },
            answerRule: { [weak self] card, scope in self?.answerRule(card, scope: scope) },
            // The question goes back whole, marked as carried on after a sign in so the daemon never takes it as a new
            // request to sign in again, and nothing here reads its words.
            askAgain: { [weak self] question in
                guard let self, !self.talking else { return }
                self.enqueue { [weak self] in await self?.converse(opening: question, openingIntent: .resume) }
            },
            // A tapped ask is a new request, so it carries no intent and goes whole to ask as if it were said.
            ask: { [weak self] words in
                guard let self, !self.talking else { return }
                self.enqueue { [weak self] in await self?.converse(opening: words) }
            }
        )
        hotkey = Hotkey { [weak self] in self?.talk() }
        holdKeys.began = { [weak self] in self?.ruleHeld() }
        holdKeys.ended = { [weak self] in self?.panel.ruling(false) }
        holdKeys.start()
        dictationKey.began = { [weak self] in self?.dictationHeld() }
        dictationKey.start()
        if !HoldKeys.canWatch { diary.note("Accessibility is off, so holding Control and Option for a rule is not seen yet") }
        UserDefaults.standard.register(defaults: [DictationKey.enabledKey: true, DictationStore.polishKey: true, DictationStore.liveKey: true, Self.speakUpKey: false, Self.bargeKey: true, SystemChimes.key: true, Self.liveWordsKey: true, Self.stayPutKey: true])
        panel.showLiveWords(UserDefaults.standard.bool(forKey: Self.liveWordsKey))
        wake.spoken = { [weak self] in
            self?.voice.spoken(since: Date().addingTimeInterval(-Self.echoLingers)) ?? ""
        }
        wake.woke = { [weak self] after in
            self?.enqueue { [weak self] in await self?.converse(opening: after, greet: after.isEmpty) }
        }
        // One list of agents and connected apps for the menu, the notch and Settings.
        let tools = ToolsModel(
            readAgents: { [weak self] in await self?.conversation?.voiceAgents() ?? .unreachable },
            readConnections: { [weak self] in await self?.conversation?.connections() ?? .unreachable }
        )
        panel.useTools(tools)
        let menu = MenuModel(
            wakeOn: UserDefaults.standard.bool(forKey: Self.wakeKey),
            talk: { [weak self] in self?.talk() },
            setWake: { [weak self] in self?.setWake($0) },
            speakUpOn: UserDefaults.standard.bool(forKey: Self.speakUpKey),
            setSpeakUp: { UserDefaults.standard.set($0, forKey: Self.speakUpKey) },
            talkOverOn: UserDefaults.standard.bool(forKey: Self.bargeKey),
            setTalkOver: { UserDefaults.standard.set($0, forKey: Self.bargeKey) },
            chimesOn: UserDefaults.standard.bool(forKey: SystemChimes.key),
            setChimes: { UserDefaults.standard.set($0, forKey: SystemChimes.key) },
            liveWordsOn: UserDefaults.standard.bool(forKey: Self.liveWordsKey),
            setLiveWords: { [weak self] on in
                UserDefaults.standard.set(on, forKey: Self.liveWordsKey)
                self?.panel.showLiveWords(on)
            },
            stayPutOn: UserDefaults.standard.bool(forKey: Self.stayPutKey),
            setStayPut: { UserDefaults.standard.set($0, forKey: Self.stayPutKey) },
            voiceChoice: VoiceChoice.mac,
            chooseVoice: { [weak self] choice in Task { await self?.chooseVoice(choice, announce: true) } },
            setUp: { [weak self] in self?.showSetup() },
            saySomething: { [weak self] in self?.saySomething() },
            sayRule: { [weak self] in self?.sayRule() },
            copyWhatHappened: { [weak self] in self?.copyWhatHappened() },
            pairPhone: { [weak self] in self?.pairPhone() },
            revoke: { [weak self] device in self?.revoke(device) },
            letDrive: { [weak self] device, on in self?.letDrive(device, on) },
            loadDevices: { [weak self] in self?.loadDevices() },
            loadOverview: { [weak self] in self?.loadOverview() },
            tools: tools
        )
        self.menu = menu
        menuBar = MenuBarPanel(model: menu)
        panel.wireLauncher(
            sayRule: { [weak self] in self?.sayRule() },
            copyWhatHappened: { [weak self] in self?.copyWhatHappened() },
            openSettings: { page in SettingsWindow.shared.show(page) }
        )
        let home = HomeModel(
            load: { [weak self] in await self?.conversation.home() },
            handOver: { [weak self] action in await self?.conversation.handOver(action) ?? .unreachable },
            protectAgents: { [runtime] in await runtime.protectAgents() },
            remote: { [target] in target.isRemote },
            openWaiting: { [weak self] in self?.panel.openIsland() },
            openSession: { [weak self] session in self?.watchLive(session) }
        )
        self.home = home
        SettingsWindow.shared.home = home
        let chosen = UserDefaults.standard.string(forKey: Self.voiceChoiceKey) ?? VoiceChoice.kokoro
        Task {
            await chooseVoice(chosen, announce: false)
            // Installed in the background on first launch; the Mac's voice speaks until it is ready.
            guard chosen != VoiceChoice.mac, !KokoroServer.isInstalled else { return }
            if await kokoroInstaller.install() { await chooseVoice(VoiceChoice.kokoro, announce: false) }
        }
        listenForName()
        listenToDaemon()
        readInbox()
        watchPresence()
        let setUp = UserDefaults.standard.bool(forKey: SetupModel.doneKey)
        // Every launch, the first included, so the daemon is up as the app opens and an app updated past its runtime
        // brings the runtime along before anyone asks. Setup's own check joins this run rather than starting another.
        // Somebody signed in who never set this Mac up only answers what is routed to them, so it is left alone.
        Task { [runtime, conversation, target, account] in
            // A server keeps its own runtime and trusts the key it paired with, so neither is this Mac's to tend.
            guard !target.isRemote, setUp || !account.isSignedIn else { return }
            if let conversation, await runtime.ensure(conversation) != .unreachable, setUp { await conversation.introduce() }
        }
        if !setUp, !account.isSignedIn {
            // Somebody who only answers what is routed to them has what they came for, so setup is not pushed on them each launch.
            showSetup()
        }
    }

    /// The hotkey, the menu and Siri all end here: open the orb and listen.
    @objc func talk() {
        if talking {
            Task { await conversation.interrupt() }
            return
        }
        enqueue { [self] in await converse() }
    }

    private func converse(opening: String = "", greet: Bool = false, openingIntent: AskIntent? = nil) async {
        talking = true
        panel.present()
        guard await Ears.mayHear() else {
            // Said, since a silent orb that cannot hear looks exactly like one that is not listening.
            panel.show(.speaking, caption: "I need permission to hear you")
            do { try audio.start() } catch {}
            await voice.speak("I cannot hear you yet. Allow Memnox under Microphone and Speech Recognition in System Settings, Privacy and Security.")
            audio.stop()
            panel.dismiss()
            talking = false
            return
        }
        do { try audio.start() } catch { NSLog("Memnox: no audio: \(error)") }
        // Started while they are still talking, so the answer does not wait on a cold start.
        Task { [conversation] in await conversation?.warm() }
        // Learnt alongside rather than before, so the microphone is heard from the first word; the names land by the next listen.
        Task { [weak self] in await self?.learnNames() }
        var waiting = Self.firstWordSeconds
        if greet {
            // Called by name alone, it answers the way a person would before they ask.
            await voice.speak(conversation.answerToCall())
        }
        var next: String? = opening.isEmpty ? nil : opening
        /// How the opening words were asked, which only ever applies to them and never to what is said after.
        var intentNow = opening.isEmpty ? nil : openingIntent
        /// Words the brain held for, answered as they stand if nothing more comes, so a wrong hold is never silence.
        var held: String?
        diary.note("listening")
        chimes.play(.listening)
        panel.show(.listening, caption: "")
        while true {
            let heard: String?
            if let cutIn = next { heard = cutIn } else { heard = await ownWordsOnly(ears.listen(through: audio, waiting: waiting)) }
            let finished = heard == nil && held != nil
            conversation.lastWordAt = next == nil && !finished ? ears.lastWordAt : nil
            guard let said = heard ?? held else { break }
            next = await answer(said, finished: finished || intentNow != nil, intent: intentNow)
            intentNow = nil
            // They carried on before any answer was said, so it is one question in two breaths, not two.
            if let more = next, !conversation.spokeThisTurn { next = "\(said) \(more)" }
            // A hold beside words it said is an answer that ends in a question, so it waits as after any answer.
            let holding = conversation.takeHold() && !conversation.spokeThisTurn
            // Held once on words already marked whole is a brain ignoring the note, and asking again would loop.
            held = holding && !finished ? said : nil
            // They said they were done, so the orb goes now rather than after another wait.
            if next == nil, conversation.takeEnd() { break }
            waiting = holding ? Self.restOfThought(after: said) : Self.followUpSeconds
            panel.show(.listening, caption: "")
        }
        chimes.play(.closed)
        audio.stop()
        panel.dismiss()
        talking = false
    }

    /// What was heard less the tail of its own voice: a sentence said just before, such as a confirmation's
    /// apology, is still in the room when the microphone opens. Nil when nothing of the person is left.
    private func ownWordsOnly(_ heard: String?) -> String? {
        guard let heard, let voice else { return heard }
        let recent = voice.spoken(since: Date().addingTimeInterval(-Self.echoLingers))
        let mine = withoutEchoRuns(heard, spoken: recent)
        if mine != heard { diary.note("took its own words off: \(heard)") }
        return mine.contains(where: \.isLetter) ? mine : nil
    }

    /// Long enough for the longest sentence it says to finish playing and come back through the microphone.
    private static let echoLingers: TimeInterval = 15

    /// Answers one thing said, listening over the voice so the person can cut in; returns what they cut in with.
    private func answer(_ said: String, finished: Bool = false, intent: AskIntent? = nil) async -> String? {
        await overVoice { [conversation] in await conversation?.heard(said, finished: finished, intent: intent) }
    }

    /// Anything spoken, with an ear open the whole time: the moment the person talks over it the
    /// voice stops and the brain stops, and their whole sentence is returned once they pause.
    private func overVoice(_ speaking: @escaping @MainActor () async -> Void) async -> String? {
        guard UserDefaults.standard.bool(forKey: Self.bargeKey) else {
            await speaking()
            return nil
        }
        let voice = self.voice! // Set at launch, before any turn can run.
        var cutting: Task<Void, Never>?
        // A breath before, so the first sentence queued for this reply is part of what counts as its own.
        // Back far enough to cover a sentence from before this reply that is still playing.
        let began = Date().addingTimeInterval(-Self.echoLingers)
        barge.watch(
            through: audio,
            spoken: { voice.spoken(since: began) },
            speaking: { voice.level > 0 },
            playing: { voice.playingLevel },
            pause: { voice.hush() },
            resume: { voice.carryOn() }
        ) { [weak self] in
            cutting = Task { await self?.conversation.interrupt() }
        }
        await speaking()
        // The old answer's cancel must reach the daemon before the next question does, or it cancels that one.
        await cutting?.value
        return await barge.finish(audio)
    }

    /// An event from one machine: all of it from the one picked, and from the rest what waits on the person.
    /// Its subject is remembered with the machine, so the answer goes back through the link it came from.
    private func arrived(_ event: DaemonEvent, from machine: MachineTarget) {
        let chosen = target.target.machineId == machine.machineId
        guard MachineEvents.delivers(event, chosen: chosen, thisMac: machine == .thisMac) else { return }
        target.remember(subject: event.subject, from: machine)
        arrived(event)
        if event.eventKind == .settled { target.forget(subject: event.subject) }
    }

    /// Something began or stopped waiting: said out loud, then listened to for the answer.
    private func arrived(_ event: DaemonEvent) {
        // Shown at once, since it belongs to the answer being said now and a queue would hold it until after.
        // A card, a window or a Touch ID sheet belongs to the conversation happening now, so it
        // comes up at once; queued, it would wait until the person stopped talking.
        // Saying the name near the phone must not wake the Mac as well, so the name is not listened for while a phone holds the voice.
        if let voiceOn = event.voiceOn {
            phoneHoldsVoice = voiceOn.holding
            // Told at once rather than in its turn, so an event right behind it is already quiet here.
            conversation?.phoneHolds = PhoneVoice(voiceOn)
            if voiceOn.holding { wake.stop() } else { listenForName() }
        }
        // What waits, works and was answered is what the home counts, so it is read again while somebody can see it.
        if event.eventKind != .show, SettingsWindow.shared.isShowing { home?.refreshSoon() }
        // A drive grant, a phone's turn and the voice moving are shown rather than said, so they never wait behind speech.
        if event.eventKind == .show || event.isShownOnly {
            Task { [conversation] in await conversation?.handle(event) }
            return
        }
        // The island shows a held call the moment it arrives, so a hand can answer it before the voice has finished.
        switch event.eventKind {
        case .held:
            panel.hold(event, server: target.machine(for: event.subject)?.serverName)
            waitingCalls.insert(event.subject)
        case .settled:
            // The daemon does not say who answered or whether it ran out, so the card claims neither.
            panel.release(event.subject, note: SettledLine.unknown)
            waitingCalls.remove(event.subject)
        case .paused: panel.shake()
        case .notice where event.noticeKind == .finished: panel.finished(event)
        // Shown as taps while the voice reads it, so either a hand or a word answers it.
        case .notice where event.noticeKind == .question: panel.question(event)
        case .notice, .proposal, .show, nil: break
        }
        // Seen as well as said, and only from the daemon's facts, so a pass the ledger never saw is never celebrated.
        if let gesture = reaction(to: event) { panel.react(gesture, session: event.sessionId) }
        if event.eventKind == .proposal {
            let previous = confirmations
            confirmations = Task { [conversation] in
                await previous?.value
                await conversation?.handle(event)
            }
            return
        }
        // A phone holds the voice, so the island shows it and the Mac neither speaks nor opens its microphone.
        if conversation?.isQuiet(event) ?? event.quietOnMac {
            Task { [conversation] in await conversation?.handle(event) }
            return
        }
        guard event.isSaid(speakUp: UserDefaults.standard.bool(forKey: Self.speakUpKey)) else { return }
        enqueue { [self] in
            if event.eventKind == .settled {
                await conversation.handle(event)
                return
            }
            panel.present()
            do { try audio.start() } catch { NSLog("Memnox: no audio: \(error)") }
            let cutIn = await overVoice { [conversation] in await conversation?.handle(event) }
            // Only something waiting on their answer keeps the microphone open; news is said and the orb goes back to sleep.
            // A held call answered or run out before its turn came is not waited on.
            let live = event.eventKind != .held || conversation.stillAsking(event.subject)
            if cutIn != nil || (event.awaitsAnswer && live) {
                await converse(opening: cutIn ?? "")
            } else {
                audio.stop()
                panel.dismiss()
            }
        }
    }

    /// A button on the island: Touch ID for an allow that reaches outside the session, then the answer,
    /// and the call stays up if it did not go through.
    private func answerHeld(_ card: HeldCard, _ answer: HoldAnswer) {
        let previous = confirmations
        confirmations = Task { [weak self, conversation, panel] in
            await previous?.value
            guard let conversation, let panel else { return }
            let outcome = await conversation.answerHeld(card.subject, answer, reason: card.reason(for: answer), touchID: card.touchID)
            panel.answered(card.subject, outcome)
            switch outcome {
            // The card already went, or says who got there first, so only the bookkeeping is left.
            case .answered, .answeredElsewhere: self?.teamForget(card.subject)
            case .cancelled, .failed: break
            }
        }
    }

    /// A choice tapped on an agent's question: sent in turn behind any other answer, and the card moves on once it lands.
    private func answerQuestion(_ card: AgentQuestionCard, number: Int, answer: String) {
        let previous = confirmations
        confirmations = Task { [conversation, panel] in
            await previous?.value
            guard let conversation, let panel else { return }
            let outcome = await conversation.answerQuestion(card.subject, number: number, answer: answer)
            panel.questionAnswered(card, number: number, answer: answer, outcome)
        }
    }

    /// Reads the team's inbox now and then every little while, for as long as the app runs; signed out, it reads nothing.
    private func readInbox() {
        readingInbox?.cancel()
        readingInbox = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let teamCalls = self.teamCalls else { return }
                self.teamArrived(await teamCalls.refresh())
                try? await Task.sleep(nanoseconds: UInt64(Self.inboxEvery * nanosecondsPerSecond))
            }
        }
    }

    /// What a read of the team's inbox changed: new calls on the island beside this Mac's and the servers', gone ones off it.
    private func teamArrived(_ change: InboxChange) {
        if change.signedOut {
            // The workspace revoked it, so it is forgotten here rather than sent again every poll.
            personCredential.delete()
            account?.signedOutByWorkspace()
        }
        teamSettled(change.gone, notes: change.answeredElsewhere, quietly: change.signedOut)
        for call in change.arrived {
            // Known to belong to the workspace, so no daemon link is ever sent its answer.
            target.rememberWorkspace(subject: call.id)
            waitingCalls.insert(call.id)
            diary.note("the team routed \(call.id) to you: \(call.who)")
            // Queued beside this Mac's and the servers' calls, so none takes another's place on the island.
            panel.hold(card: HeldCard(team: call))
            announceTeam(call)
        }
    }

    /// A teammate's call said aloud like one of this Mac's, after whatever is being said now, and then listened for
    /// like one, since every ask names it to the brain; a phone holding the voice keeps the Mac quiet.
    private func announceTeam(_ call: WorkspaceHeldCall) {
        guard !phoneHoldsVoice else { return }
        enqueue { [self] in
            // Answered or gone before its turn came, so it is not asked about.
            guard waitingCalls.contains(call.id) else { return }
            panel.present()
            do { try audio.start() } catch { NSLog("Memnox: no audio: \(error)") }
            let cutIn = await overVoice { [conversation] in await conversation?.announceTeam(call) }
            // Answered by hand or elsewhere while it was said, so nothing is left to listen for.
            if cutIn != nil || conversation.stillAsking(call.id) {
                await converse(opening: cutIn ?? "")
            } else {
                audio.stop()
                panel.dismiss()
            }
        }
    }

    /// Teammates' calls answered or gone: off the island with who answered where the workspace said, and the voice
    /// stops asking about them. A sign out takes them down without a word, since nobody answered them.
    private func teamSettled(_ ids: [String], notes: [String: String], quietly: Bool) {
        for id in ids where target.belongsToWorkspace(subject: id) {
            teamForget(id)
            let note = quietly ? nil : notes[id] ?? SettledLine.unknown
            panel.release(id, note: note)
            conversation.teamSettled(id, line: note)
        }
    }

    /// A teammate's call nothing waits on any more, so it is no longer counted or routed.
    private func teamForget(_ id: String) {
        guard target.belongsToWorkspace(subject: id) else { return }
        target.forget(subject: id)
        waitingCalls.remove(id)
    }

    /// Control and Option held: whatever was going on gives way, and the rule is listened to for as long as they are down.
    private func ruleHeld() {
        panel.ruling(true)
        if talking {
            // The listen in progress ends with nothing heard and the voice stops, so the rule turn comes next.
            ears.cut.set(true)
            Task { await conversation.interrupt() }
        }
        enqueue { [weak self] in await self?.converseRule() }
    }

    /// A rule, heard until the keys are let go and then sent at once with the rule intent; the brain
    /// reads it back and asks where it holds, and the conversation carries on for the answer.
    private func converseRule() async {
        // Let go before this turn began: nothing was said for it, so there is nothing to take down.
        guard holdKeys.holding else {
            panel.ruling(false)
            return
        }
        talking = true
        panel.present()
        panel.ruling(true)
        guard await Ears.mayHear() else {
            panel.ruling(false)
            panel.dismiss()
            talking = false
            return
        }
        do { try audio.start() } catch { NSLog("Memnox: no audio: \(error)") }
        Task { [conversation] in await conversation?.warm() }
        chimes.play(.listening)
        panel.show(.listening, caption: "")
        diary.note("listening for a rule")
        let down = holdKeys.down
        let said = ownWordsOnly(await ears.listen(through: audio, waiting: 0, holding: { down.isSet }))
        panel.ruling(false)
        guard let said else {
            chimes.play(.closed)
            audio.stop()
            panel.dismiss()
            talking = false
            return
        }
        let cutIn = await overVoice { [conversation] in await conversation?.heard(said, finished: true, intent: .rule) }
        // The place can be said as well as picked, so the microphone stays open for the answer.
        await converse(opening: cutIn ?? "")
    }

    /// Right Option held, or tapped twice for hands free: everything said until it ends is written where the cursor is,
    /// cleaned on this Mac and, when the person turned it on, polished by their own Claude Code. With text
    /// selected, what they say is an instruction about it, and the selection is replaced by the result.
    private func dictationHeld() {
        guard !talking else {
            dictationKey.stop()
            return
        }
        let front = NSWorkspace.shared.frontmostApplication
        // Started while they are still talking, so the polish skips Claude Code's cold start.
        if dictations.polishes { Task { [polish] in await polish.warm() } }
        enqueue { [weak self] in await self?.dictate(into: front) }
    }

    private func dictate(into app: NSRunningApplication?) async {
        // Let go before this turn began: nothing was said for it.
        guard dictationKey.active else { return }
        let focus = FocusedText.read(in: app)
        guard !focus.isSecure else {
            // A password field is never written into by voice, whatever was said.
            diary.note("not dictating into a password field")
            dictationKey.stop()
            chimes.play(.failed)
            return
        }
        talking = true
        defer { talking = false }
        guard await Ears.mayHear() else { return }
        panel.present()
        do { try audio.start() } catch { NSLog("Memnox: no audio: \(error)") }
        chimes.play(.listening)
        panel.show(.listening, caption: focus.selection == nil ? "Dictating" : "Say what to do with the selection")
        panel.dictating(focus.selection == nil ? "Speak, and it types where your cursor is" : "Say what to do with the selection")
        let live = dictations.typesLive ? LiveTyping(app: app, focus: focus) : nil
        let said = await listenForDictation(focus: focus, live: live)
        dictationKey.stop()
        audio.stop()
        guard let said, said.contains(where: \.isLetter) else {
            // Words typed live and then heard as nothing are taken back, so a cough leaves no trace.
            if let live, !live.typed.isEmpty, live.stillOurs { await live.show("") }
            live?.end()
            panel.dismiss()
            chimes.play(.closed)
            return
        }
        panel.show(.thinking, caption: "")
        let family = DictationFamily(bundleID: app?.bundleIdentifier, windowTitle: focus.windowTitle)
        let written = await dictationText(said, family: family, focus: focus)
        panel.dismiss()
        guard let written else {
            // Editing a selection needs the model, and without its answer the selection is left untouched.
            chimes.play(.failed)
            diary.note("the selection was left as it was, since it could not be edited just now")
            return
        }
        let place = app?.localizedName ?? "the app in front"
        let landed = await put(written, into: app, live: live)
        live?.end()
        guard let landed else {
            // Kept rather than lost: a paste into whatever is in front now does it by hand.
            dictations.record(DictationEntry(at: Date(), heard: said, written: written, app: app?.localizedName))
            diary.note("\(place) was not in front, so the dictation is on the clipboard")
            chimes.play(.failed)
            return
        }
        dictations.record(DictationEntry(at: Date(), heard: said, written: landed, app: app?.localizedName))
        diary.note("dictated into \(place) as \(family.rawValue): \(landed)")
        if focus.selection == nil, let element = focus.element { watchForCorrections(landed, in: element, focus: focus) }
    }

    /// Everything said while the key is held, plus a moment after it comes up so the last word is not cut off, heard
    /// with the person's own words and the names around the cursor as hints, and typed into the field as it comes
    /// when typing live. The typing runs on its own loop, so the recognizer never waits on a key press.
    private func listenForDictation(focus: FocusedText, live: LiveTyping?) async -> String? {
        let dictionary = dictations.dictionary
        let hints = dictionary.spellings + cursorHints(before: focus.before, after: focus.after)
        let words = DictatedSoFar()
        var typing: Task<Void, Never>?
        if let live {
            live.begin()
            ears.revising = { words.set($0) }
            let names = dictionary.spellings + recognizerHints.filter { $0.contains(where: \.isUppercase) }
            typing = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: UInt64(Self.liveLook * 1_000_000_000))
                    guard let heard = words.takeChanged() else { continue }
                    let text = liveDictation(heard, final: false, dictionary: names, replacements: dictionary.replacements)
                    await live.show(fitted(text, after: focus.before, before: focus.after))
                }
            }
        }
        let down = dictationKey.down
        let said = await ears.listen(through: audio, waiting: 0, holding: { down.isSet }, tail: Self.releaseTail, hints: hints)
        ears.revising = nil
        typing?.cancel()
        await typing?.value
        return said
    }

    /// The finished words where the cursor is: over what was typed live while that is still Memnox's own, as it
    /// stands when the person has typed since, and pasted when nothing was typed live. Nil when they could not go in.
    private func put(_ written: String, into app: NSRunningApplication?, live: LiveTyping?) async -> String? {
        if let live {
            if live.stillOurs, await live.show(written) { return written }
            if !live.typed.isEmpty {
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app?.processIdentifier else {
                    // They moved to another app mid sentence, so the whole of it waits on the clipboard.
                    PromptTyping.leaveOnClipboard(written)
                    return nil
                }
                // The person carried on in the field, so what is there now is theirs to keep, and nothing is replaced.
                diary.note("left the live words as typed, since the field changed after them")
                return live.typed
            }
        }
        return await PromptTyping.paste(written, into: app) ? written : nil
    }

    /// How long the key may be up before listening ends, enough for the last syllable to reach the recognizer.
    private static let releaseTail: TimeInterval = 0.4
    /// How often the words heard are typed live, quick enough to follow speech and slow enough to type each change once.
    private static let liveLook: TimeInterval = 0.12

    /// What goes in: for a selection, the model's edit of it or nothing; otherwise the Mac's cleanup, replaced by the
    /// model's polish when that is on and answers in time, then the person's replacements, then fitted to the cursor.
    private func dictationText(_ said: String, family: DictationFamily, focus: FocusedText) async -> String? {
        let dictionary = dictations.dictionary
        // Their own spellings first, then the names Memnox knows on this Mac, proper names only.
        let names = dictionary.spellings + recognizerHints.filter { $0.contains(where: \.isUppercase) }
        if let selection = focus.selection {
            guard dictations.polishes else { return nil }
            return await polish.polish(said, family: family, vocabulary: names, selection: selection,
                                       patience: DictationPolish.editPatience)
        }
        let local = cleanedDictation(said, dictionary: names, replacements: dictionary.replacements, style: family.style)
        var text = local
        if dictations.polishes, let polished = await polish.polish(said, family: family, vocabulary: names) {
            text = replaced(polished, by: dictionary.replacements)
        }
        return fitted(text, after: focus.before, before: focus.after)
    }

    /// Reads the field again a while later, and what the person changed in the words just written is learned: the
    /// dictionary writes it their way next time, and the recognizer hears it better.
    private func watchForCorrections(_ written: String, in element: AXUIElement, focus: FocusedText) {
        guard let start = focus.range?.location, let value = focus.value else { return }
        let prefix = String(value.prefix(start))
        let suffix = focus.range.map { String(value.dropFirst($0.location + $0.length)) } ?? ""
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.correctionWatch * 1_000_000_000))
            guard let self, let now = FocusedText.value(of: element),
                  now.hasPrefix(prefix), now.hasSuffix(suffix), now.count >= prefix.count + suffix.count else { return }
            let edited = String(now.dropFirst(prefix.count).dropLast(suffix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let typed = written.trimmingCharacters(in: .whitespacesAndNewlines)
            guard edited != typed, !edited.isEmpty else { return }
            let corrections = correctedWords(typed: typed, sent: edited)
            self.dictations.learn(corrections)
            await self.conversation?.learn(typed: typed, sent: edited)
        }
    }

    /// Long enough to fix a word just written, short enough that the field is still the same text.
    private static let correctionWatch: TimeInterval = 20

    /// Enforce or Not now on a rule: Touch ID over the place picked, one sheet after another, and the card stays up if it did not go.
    private func answerRule(_ card: RuleCard, scope: RuleScope?) {
        let previous = confirmations
        confirmations = Task { [weak self, conversation, panel] in
            await previous?.value
            guard let conversation, let panel else { return }
            let reason = "\(card.draft.summary) \(scope.map(placeWords) ?? "")"
            panel.ruleAnswered(card, await conversation.answerRule(card.subject, scope: scope, reason: reason))
            // A rule handed over takes its action off the ready card, and no event says so.
            if SettingsWindow.shared.isShowing { self?.home?.refresh() }
        }
    }

    /// A draft's Send or close: Touch ID for a Send, one after another with every other sheet, and the card stays up if it did not go.
    private func answerDraft(_ card: DraftCard, send: Bool) {
        let previous = confirmations
        confirmations = Task { [conversation, panel] in
            await previous?.value
            guard let conversation, let panel else { return }
            panel.draftAnswered(card, await conversation.answerDraft(card.subject, send: send, reason: card.reason))
        }
    }

    /// What goes out in the person's name: Touch ID for a Send, one sheet after another, and the card stays up if it did not go.
    private func answerWork(_ card: WorkCard, send: Bool) {
        let previous = confirmations
        confirmations = Task { [conversation, panel] in
            await previous?.value
            guard let conversation, let panel else { return }
            let outcome = await conversation.answerDraft(card.subject, send: send, reason: card.reason, edited: card.edited)
            panel.workAnswered(card, outcome)
        }
    }

    /// Not me takes nothing away by itself: it asks for a fresh sign in, which replaces an account not tied to them.
    private func notMine(_ card: SignedInCard) {
        panel.signedInDismissed(card)
        guard !talking else { return }
        // Said as the person would say it, so the brain opens a fresh sign in with their own account.
        let again = "Sign me in to \(card.tool) again, with my own account"
        enqueue { [weak self] in await self?.converse(opening: again) }
    }

    /// The tool's own sign in, in the browser; its icon goes once tapped, and comes back if they ask again unsigned.
    private func openSignIn(_ tool: ToolSignIn) {
        guard let url = URL(string: tool.url), url.scheme == "https" else {
            // Written down, since a tap that does nothing at all reads as a notch that cannot be clicked.
            diary.note("not opening the \(tool.toolkit) sign in, since its link is not https")
            return
        }
        guard NSWorkspace.shared.open(url) else {
            diary.note("the browser would not open the \(tool.toolkit) sign in")
            return
        }
        panel.signingIn(tool)
    }

    /// A tap on the resting notch starts listening; a tap on an open island puts it away.
    private func tappedIsland() {
        if talking { panel.dismiss() } else { talk() }
    }

    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        // The name is not listened for while anything else runs, so the orb never wakes on its own voice.
        wake.stop()
        turns += 1
        let previous = tail
        tail = Task { @MainActor [weak self] in
            await previous?.value
            await work()
            guard let self else { return }
            self.turns -= 1
            self.listenForName()
        }
    }

    /// Listens for "Memnox" while the orb is idle, when the person has turned it on.
    private func listenForName() {
        guard turns == 0, !phoneHoldsVoice, UserDefaults.standard.bool(forKey: Self.wakeKey) else { return }
        wake.start(through: audio)
    }

    /// Puts the chosen voice in place and says it once so the person hears the change; Kokoro when
    /// nothing was chosen, and the Mac's own voice whenever the chosen one cannot run.
    private func chooseVoice(_ choice: String, announce: Bool) async {
        // Anything but the Mac's own voice is Kokoro, so a choice from an older version still lands somewhere.
        let choice = choice == VoiceChoice.mac ? VoiceChoice.mac : VoiceChoice.kokoro
        var inUse = VoiceChoice.mac
        if choice == VoiceChoice.kokoro {
            voice.engine = await kokoro.ready() ? KokoroVoice.chosen() : nil
            if voice.engine != nil { inUse = VoiceChoice.kokoro }
        } else {
            voice.engine = nil
        }
        // A voice that could not start is not remembered, so the next launch tries the default again.
        if inUse == choice { UserDefaults.standard.set(choice, forKey: Self.voiceChoiceKey) }
        menu?.voiceChoice = inUse
        tellVoice(KokoroVoice.chosen().voice)
        await setupModel?.voiceChanged()
        diary.note("speaking with \(inUse)")
        guard announce else { return }
        enqueue { [self] in
            panel.present()
            panel.show(.speaking, caption: inUse == choice ? "New voice" : "The voice is not running")
            await voice.speak(inUse == choice
                ? "Good evening. This is how I sound now."
                : "That voice is not available, so I will keep using this one.")
            panel.dismiss()
        }
    }

    /// The Kokoro voice picked, told to the daemon so a paired phone speaks with it too.
    private func tellVoice(_ voice: String) {
        Task { [pairing] in await pairing?.tellVoice(voice) }
    }

    /// From the menu: setup opens on its phone row and a pairing starts.
    private func pairPhone() {
        showSetup()
        Task { [weak self] in await self?.setupModel?.pairPhone() }
    }

    /// A session from the home's Working now, opened in the live window with the host its card names.
    private func watchLive(_ session: HomeWorking) {
        Task { [weak self] in
            guard let self, let conversation = self.conversation else { return }
            let host = await conversation.sessionsList().first { $0.sessionId == session.sessionId }?.host
            await self.shown.live(session: session.sessionId, host: host)
        }
    }

    /// The menu's four numbers, from the daemon's sessions and the calls still held.
    private func loadOverview() {
        Task { [weak self] in
            guard let self, let conversation = self.conversation else { return }
            let sessions = await conversation.sessionsList()
            self.menu?.overview = MenuOverview(sessions: sessions, waiting: self.waitingCalls.count)
        }
    }

    /// The phones paired and not revoked, for the menu's list.
    private func loadDevices() {
        Task { [weak self] in
            guard let self, let pairing = self.pairing else { return }
            let found = await pairing.devices()
            self.menu?.devices = found.filter { !$0.isRevoked && $0.deviceKind == .phone }
        }
    }

    /// Revoke in the menu: no Touch ID, since it only narrows what can reach this Mac.
    private func revoke(_ device: Device) {
        Task { [weak self] in
            guard let self, let pairing = self.pairing else { return }
            _ = await pairing.revoke(device)
            self.loadDevices()
        }
    }

    /// Let it drive this Mac in the menu: on, Touch ID signs the grant of mac since it widens what the phone can do;
    /// off goes unsigned since it only narrows it, and ends any drive under way.
    private func letDrive(_ device: Device, _ on: Bool) {
        Task { [weak self] in
            guard let self, let pairing = self.pairing else { return }
            _ = on ? await pairing.grant(.mac, to: device) : await pairing.ungrant(.mac, from: device)
            self.loadDevices()
        }
    }

    /// A short line through the orb, apart from any conversation, the way the menu's own lines are said.
    private func sayAside(_ line: String) {
        enqueue { [self] in
            panel.present()
            panel.show(.speaking, caption: caption(line))
            await voice.speak(line)
            panel.dismiss()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        kokoro.stop()
    }

    private func setWake(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.wakeKey)
        menu?.wakeOn = on
        guard on else {
            wake.stop()
            return
        }
        Task { [self] in
            // Asked here, since turning it on is the moment somebody expects to be asked.
            guard await Ears.mayHear() else {
                setWake(false)
                return
            }
            guard wake.canListen else {
                setWake(false)
                enqueue { [self] in
                    panel.present()
                    panel.show(.speaking, caption: "I cannot listen for my name here")
                    await voice.speak("This Mac cannot recognise speech on its own, so I will not listen for my name. Option Space still works.")
                    panel.dismiss()
                }
                return
            }
            listenForName()
        }
    }

    /// This Mac's own daemon is always listened to, so its agents' held calls reach the island whichever machine is picked.
    private func listenToDaemon() {
        _ = listen(to: .thisMac, through: link)
    }

    /// Reconnects after a machine's daemon restarts or its relay drops, until the task is cancelled when the server is forgotten.
    private func listen(to machine: MachineTarget, through link: DaemonLink) -> Task<Void, Never> {
        let ids = self.ids
        let deliver: @MainActor (DaemonEvent) -> Void = { [weak self] event in self?.arrived(event, from: machine) }
        return Task.detached {
            while !Task.isCancelled {
                do {
                    for try await response in link.stream(DaemonRequest(id: ids.next(), method: .subscribe)) {
                        guard let event = response.event else { continue }
                        await deliver(event)
                    }
                } catch {}
                try? await Task.sleep(nanoseconds: UInt64(resubscribeSeconds * nanosecondsPerSecond))
            }
        }
    }

    /// Lock and unlock, which is the Mac's own word for the person leaving and coming back.
    private func watchPresence() {
        UserDefaults.standard.register(defaults: [SetupModel.catchUpKey: true])
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: Self.screenLocked, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.awaySince = Date() }
        }
        center.addObserver(forName: Self.screenUnlocked, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cameBack() }
        }
        // Asleep, nothing was read, so the team's inbox is read the moment the Mac wakes rather than on the next tick.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.readInbox() }
        }
    }

    /// Whether coming back found anything to say, set inside the turn that said it.
    private var caughtUp = false

    private func cameBack() {
        guard let since = awaySince else { return }
        awaySince = nil
        guard Date().timeIntervalSince(since) >= Self.awayLongEnough,
              UserDefaults.standard.bool(forKey: SetupModel.catchUpKey) else { return }
        enqueue { [self] in
            panel.present()
            do { try audio.start() } catch { NSLog("Memnox: no audio: \(error)") }
            caughtUp = false
            let cutIn = await overVoice { [weak self] in
                self?.caughtUp = await self?.conversation?.welcomeBack(since: since) ?? false
            }
            // The daemon says nothing when nothing waits on them, and then the orb goes back to sleep unheard.
            if cutIn != nil || caughtUp {
                await converse(opening: cutIn ?? "")
            } else {
                audio.stop()
                panel.dismiss()
            }
        }
    }

    /// The agents, CLIs and servers on this machine, so the recognizer hears "Railway" and not "right away".
    private func learnNames() async {
        let words = await conversation.vocabulary()
        let names = Array(Set(firstRecognizerHints + words))
        // Every term still trains the model below; the hints are kept to the few it weighs well.
        recognizerHints = chosenHints(firstRecognizerHints, words, SpokenTerms.terms)
        diary.note("listening for \(recognizerHints.count) names")
        // Hints only nudge the recognizer, so the same names also train a model it hears them with.
        await Vocabulary.train(names: names)
    }

    /// How to say a rule, from the menu: hold the keys, say it, let go. Without Accessibility the keys
    /// are never seen, so that is asked for first, the same leave typing into an agent needs.
    @objc func sayRule() {
        let allowed = HoldKeys.canWatch || PromptTyping.allowed()
        enqueue { [self] in
            panel.present()
            let line = allowed
                ? "Hold Control and Option, say the rule, then let go. I will ask where it should hold."
                : "To hear the rule keys I need Accessibility. Switch Memnox on in System Settings, then hold Control and Option to say a rule."
            panel.show(.speaking, caption: allowed ? "Hold Control Option to say a rule" : "Memnox needs Accessibility")
            await voice.speak(line)
            panel.dismiss()
        }
    }

    /// Checks the voice on its own, apart from listening and the daemon.
    @objc func saySomething() {
        enqueue { [self] in
            panel.present()
            panel.show(.speaking, caption: "Testing my voice")
            await voice.speak("This is Memnox. If you can hear me, my voice works.")
            panel.dismiss()
        }
    }

    /// The last steps the app took, on the clipboard, for when something went quiet.
    @objc func copyWhatHappened() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diary.text.isEmpty ? "Nothing has happened yet." : diary.text, forType: .string)
    }

    @objc func showSetup() {
        // The window keeps the model it was built with until setup finishes, so an open one is shown again.
        if let setupModel {
            setup.show(setupModel)
            return
        }
        let model = SetupModel(owner: owner, conversation: conversation, pairing: pairing, voice: voice, kokoro: kokoroInstaller, runtime: runtime) { [weak self] in
            self?.setupFinished()
        }
        model.serverPairing = serverPairing
        model.talkingTo = UserDefaults.standard.string(forKey: Self.machineKey)
        model.serversChanged = { [weak self] in self?.restoreMachine() }
        model.chooseMachine = { [weak self] machineId in self?.talkTo(machineId) }
        model.say = { [weak self] line in self?.sayAside(line) }
        model.devicesChanged = { [weak self] in self?.loadDevices() }
        model.machineConnected = { [weak self] in await self?.account?.machine?.connected() }
        model.voicePicked = { [weak self] voice in self?.tellVoice(voice) }
        model.useKokoro = { [weak self] in
            guard let self else { return }
            if await self.kokoroInstaller.install() { await self.chooseVoice(VoiceChoice.kokoro, announce: false) }
        }
        setupModel = model
        setup.show(model)
    }

    /// The machine the voice talks to from now on, nil for this Mac, remembered across launches.
    private func talkTo(_ machineId: String?) {
        UserDefaults.standard.set(machineId, forKey: Self.machineKey)
        restoreMachine()
    }

    /// Points the conversation at the machine remembered, falling back to this Mac when that server is no longer paired,
    /// and tells the events which device ids are this Mac's own on each server.
    private func restoreMachine() {
        let paired = servers.all()
        OwnDevices.shared.set(Set(paired.map(\.deviceId)))
        // A link per server still paired, so a forgotten one is closed rather than left open on the relay.
        for (machineId, relay) in relays where !paired.contains(where: { $0.machineId == machineId }) {
            relays[machineId] = nil
            listening[machineId]?.cancel()
            listening[machineId] = nil
            target.unregister(machineId: machineId)
            Task { await relay.close() }
        }
        // Every server is listened to, not only the one picked, so none of their held calls is missed.
        for server in paired {
            let relay = relays[server.machineId] ?? NoiseRelayLink(mac: server, dialer: WebSocketDialer())
            relays[server.machineId] = relay
            let machine = MachineTarget.server(machineId: server.machineId, deviceId: server.deviceId, name: server.machine)
            target.register(machine, link: relay)
            if listening[server.machineId] == nil { listening[server.machineId] = listen(to: machine, through: relay) }
        }
        let chosen = UserDefaults.standard.string(forKey: Self.machineKey)
        guard let server = paired.first(where: { $0.machineId == chosen }) else {
            if chosen != nil { UserDefaults.standard.removeObject(forKey: Self.machineKey) }
            if target.isRemote { target.choose(.thisMac) }
            setupModel?.talkingTo = nil
            return
        }
        let wanted = MachineTarget.server(machineId: server.machineId, deviceId: server.deviceId, name: server.machine)
        if target.target != wanted { target.choose(wanted) }
        setupModel?.talkingTo = server.machineId
    }

    /// Setup is done: the window goes, and the orb says hello once so the person hears it work.
    private func setupFinished() {
        setup.close()
        enqueue { [self] in
            panel.present()
            do { try audio.start() } catch { NSLog("Memnox: no audio: \(error)") }
            let name = owner.name.map { ", \($0)" } ?? ""
            let hello = UserDefaults.standard.bool(forKey: Self.wakeKey)
                ? "Online and ready\(name). Say Memnox whenever you need me."
                : "Online and ready\(name). Press Option Space whenever you need me."
            panel.show(.speaking, caption: caption(hello))
            await voice.speak(hello)
            audio.stop()
            panel.dismiss()
        }
    }
}

/// Stands in when this Mac cannot hold a confirmation key: every allow is declined, never faked.
private final class RefusingKey: ConfirmKey {
    var publicPoint: String { "" }
    func sign(_ message: String, reason: String) async throws -> String? { nil }
}
