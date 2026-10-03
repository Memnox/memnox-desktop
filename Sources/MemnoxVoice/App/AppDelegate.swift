import AppKit
import MemnoxVoiceCore

/// Far above the conversation's own request ids, which count up from one, so a subscription never shares one.
private let firstSubscriptionId = 1_000
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
    /// Off unless the person turns it on: news that needs nobody stays quiet until they call Memnox.
    private static let speakUpKey = "speakUp"
    /// On unless turned off: cutting in by speaking over the voice.
    private static let bargeKey = "talkOver"
    /// Kokoro or the Mac's own voice, as picked in the menu bar panel.
    private static let voiceChoiceKey = "voiceChoice"
    private let kokoro = KokoroServer()
    /// Puts Kokoro on this Mac the first time, so the natural voice is the default with nothing to run.
    private let kokoroInstaller = KokoroInstaller()
    /// Off until the person turns it on, since it keeps the microphone open whenever the orb is idle.
    private static let wakeKey = "wakeOnName"
    private let link = UnixSocketLink()
    // Set once in applicationDidFinishLaunching, before anything can reach them.
    private var panel: IslandPanel!
    private var preview: IslandPreview?
    private var voice: Voice!
    private var conversation: Conversation!
    private var hotkey: Hotkey?
    private let owner = DefaultsOwner()
    private let presenter = SessionPresenter()
    private let chimes = SystemChimes()
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
    /// Turns run one after another, so a held call never talks over an answer.
    private var tail: Task<Void, Never>?
    /// Touch ID sheets one after another, apart from the conversation, since two at once collide.
    private var confirmations: Task<Void, Never>?
    private var talking = false
    /// Turns queued or running, since the name is only listened for when there are none.
    private var turns = 0

    /// How long the microphone stays open for a follow up after an answer, long enough to think one up.
    private static let followUpSeconds: TimeInterval = 15
    /// How long it waits for the rest when the brain thought they stopped mid thought; past it, what they said is answered as it stands.
    private static let restOfThoughtSeconds: TimeInterval = 6
    private static let firstWordSeconds: TimeInterval = 10

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The island on its own, touring its states, with nothing listening and no daemon needed.
        if IslandPreview.requested {
            panel = IslandPanel(loudness: { IslandPreview.level })
            let preview = IslandPreview(panel: panel)
            self.preview = preview
            preview.start()
            return
        }
        let voice = Voice()
        self.voice = voice
        panel = IslandPanel(loudness: { [audio] in max(audio.micLevel, voice.level) })
        ears.hearing = { [weak self] words in
            self?.panel.show(.listening, caption: caption(words))
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
            key = try SecureEnclaveConfirmKey()
        } catch {
            // No Secure Enclave or no keychain: nothing can ever be confirmed from this Mac.
            NSLog("Memnox: no confirmation key, so allows stay in the terminal: \(error)")
            key = RefusingKey()
        }
        conversation = Conversation(
            link: link, speaker: voice, key: key, face: panel, owner: owner, presenter: presenter, chimes: chimes,
            address: { chosenAddress() }
        )
        presenter.livePanel.fetch = { [weak self] session in await self?.conversation.sessionView(session) }
        presenter.sessions = { [weak self] in await self?.conversation.sessionsList() ?? [] }
        presenter.orbFrame = { [weak self] in self?.panel.orbFrame }
        panel.wire(
            answer: { [weak self] subject, answer, reason in self?.answerHeld(subject, answer, reason: reason) },
            tapped: { [weak self] in self?.tappedIsland() }
        )
        panel.wireSessions(
            list: { [weak self] in await self?.conversation.sessionsList() ?? [] },
            view: { [weak self] session in await self?.conversation.sessionView(session) },
            open: { [presenter] session, host in Task { _ = await presenter.focus(session: session, host: host) } }
        )
        hotkey = Hotkey { [weak self] in self?.talk() }
        UserDefaults.standard.register(defaults: [Self.speakUpKey: false, Self.bargeKey: true, SystemChimes.key: true])
        wake.woke = { [weak self] after in
            self?.enqueue { [weak self] in await self?.converse(opening: after, greet: after.isEmpty) }
        }
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
            voiceChoice: VoiceChoice.mac,
            chooseVoice: { [weak self] choice in Task { await self?.chooseVoice(choice, announce: true) } },
            setUp: { [weak self] in self?.showSetup() },
            saySomething: { [weak self] in self?.saySomething() },
            copyWhatHappened: { [weak self] in self?.copyWhatHappened() }
        )
        self.menu = menu
        menuBar = MenuBarPanel(model: menu)
        let chosen = UserDefaults.standard.string(forKey: Self.voiceChoiceKey) ?? VoiceChoice.kokoro
        Task {
            await chooseVoice(chosen, announce: false)
            // Installed in the background on first launch; the Mac's voice speaks until it is ready.
            guard chosen != VoiceChoice.mac, !KokoroServer.isInstalled else { return }
            if await kokoroInstaller.install() { await chooseVoice(VoiceChoice.kokoro, announce: false) }
        }
        listenForName()
        listenToDaemon()
        watchPresence()
        if UserDefaults.standard.bool(forKey: SetupModel.doneKey) {
            Task { await conversation.introduce() }
        } else {
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

    private func converse(opening: String = "", greet: Bool = false) async {
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
        await learnNames()
        var waiting = Self.firstWordSeconds
        if greet {
            // Called by name alone, it answers the way a person would before they ask.
            await voice.speak(conversation.answerToCall())
        }
        var next: String? = opening.isEmpty ? nil : opening
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
            next = await answer(said, finished: finished)
            // They carried on before any answer was said, so it is one question in two breaths, not two.
            if let more = next, !conversation.spokeThisTurn { next = "\(said) \(more)" }
            let holding = conversation.takeHold()
            // Held once on words already marked whole is a brain ignoring the note, and asking again would loop.
            held = holding && !finished ? said : nil
            // They said they were done, so the orb goes now rather than after another wait.
            if next == nil, conversation.takeEnd() { break }
            waiting = holding ? Self.restOfThoughtSeconds : Self.followUpSeconds
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
    private func answer(_ said: String, finished: Bool = false) async -> String? {
        await overVoice { [conversation] in await conversation?.heard(said, finished: finished) }
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
        barge.watch(through: audio, spoken: { voice.spoken(since: began) }, speaking: { voice.level > 0 }) { [weak self] in
            cutting = Task { await self?.conversation.interrupt() }
        }
        await speaking()
        // The old answer's cancel must reach the daemon before the next question does, or it cancels that one.
        await cutting?.value
        return await barge.finish(audio)
    }

    /// Something began or stopped waiting: said out loud, then listened to for the answer.
    private func arrived(_ event: DaemonEvent) {
        // Shown at once, since it belongs to the answer being said now and a queue would hold it until after.
        // A card, a window or a Touch ID sheet belongs to the conversation happening now, so it
        // comes up at once; queued, it would wait until the person stopped talking.
        if event.eventKind == .show {
            Task { [conversation] in await conversation?.handle(event) }
            return
        }
        // The island shows a held call the moment it arrives, so a hand can answer it before the voice has finished.
        switch event.eventKind {
        case .held: panel.hold(event)
        case .settled: panel.release(event.subject)
        case .paused: panel.shake()
        case .notice where event.noticeKind == .finished: panel.finished(event)
        case .notice, .proposal, .show, nil: break
        }
        if event.eventKind == .proposal {
            let previous = confirmations
            confirmations = Task { [conversation] in
                await previous?.value
                await conversation?.handle(event)
            }
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
            if cutIn != nil || event.awaitsAnswer {
                await converse(opening: cutIn ?? "")
            } else {
                audio.stop()
                panel.dismiss()
            }
        }
    }

    /// A button on the island: Touch ID for an allow, then the answer, and the call stays up if it did not go through.
    private func answerHeld(_ subject: String, _ answer: HoldAnswer, reason: String) {
        let previous = confirmations
        confirmations = Task { [conversation, panel] in
            await previous?.value
            guard let conversation, let panel else { return }
            panel.answered(subject, await conversation.answerHeld(subject, answer, reason: reason))
        }
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
        guard turns == 0, UserDefaults.standard.bool(forKey: Self.wakeKey) else { return }
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
        diary.note("speaking with \(inUse)")
        guard announce else { return }
        enqueue { [self] in
            panel.present()
            panel.show(.speaking, caption: inUse == choice ? "New voice" : "Kokoro is not running")
            await voice.speak(inUse == choice
                ? "Good evening. This is how I sound now."
                : "That voice is not available, so I will keep using this one.")
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

    /// Reconnects after the daemon restarts, since it is the daemon's to come and go.
    private func listenToDaemon() {
        let link = self.link
        let deliver: @MainActor (DaemonEvent) -> Void = { [weak self] event in self?.arrived(event) }
        Task.detached {
            var id = firstSubscriptionId
            while true {
                id += 1
                do {
                    for try await response in link.stream(DaemonRequest(id: id, method: .subscribe)) {
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
        guard !words.isEmpty else { return }
        recognizerHints = Array(Set(words + Self.spokenVocabulary))
        diary.note("listening for \(recognizerHints.count) names")
    }

    /// The words people use about their agents, which the recognizer otherwise hears as "urgent",
    /// "contacts", "Carter" or "closed quote", so it is told to expect them.
    private static let spokenVocabulary = [
        "Claude Code", "Codex", "Cursor", "Memnox", "Memnox runtime", "Memnox cloud", "Memnox client",
        "agent", "agents", "session", "sessions", "last session", "new session", "repository",
        "git push", "git status", "git history", "git changes", "commit", "commits", "pull request",
        "scan my computer", "walk me through", "put it back", "tell me when", "the tests pass",
    ]

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
        let model = SetupModel(owner: owner, conversation: conversation, voice: voice, kokoro: kokoroInstaller) { [weak self] in
            self?.setupFinished()
        }
        model.useKokoro = { [weak self] in
            guard let self else { return }
            if await self.kokoroInstaller.install() { await self.chooseVoice(VoiceChoice.kokoro, announce: false) }
        }
        setup.show(model)
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
