import AppKit
import MemnoxVoiceCore

/// Wires the face, the ears and the voice to the conversation, and keeps one ear on the daemon
/// for anything that starts waiting on the person.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let audio = AudioIO()
    private let ears = Ears()
    private let link = UnixSocketLink()
    // Set once in applicationDidFinishLaunching, before anything can reach them.
    private var panel: OrbPanel!
    private var voice: Voice!
    private var conversation: Conversation!
    private var hotkey: Hotkey?
    private let owner = DefaultsOwner()
    private let setup = SetupWindow()
    private var status: NSStatusItem?
    /// Turns run one after another, so a held call never talks over an answer.
    private var tail: Task<Void, Never>?
    private var talking = false

    /// How long the microphone stays open for a follow up after an answer.
    private static let followUpSeconds: TimeInterval = 8
    private static let firstWordSeconds: TimeInterval = 10

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = OrbPanel(loudness: { [audio] in max(audio.micLevel, audio.voiceLevel) })
        voice = Voice(audio: audio)
        ears.hearing = { [weak self] words in
            self?.panel.show(.listening, caption: caption(words))
        }
        let key: ConfirmKey
        do {
            key = try SecureEnclaveConfirmKey()
        } catch {
            // No Secure Enclave or no keychain: nothing can ever be confirmed from this Mac.
            NSLog("Memnox: no confirmation key, so allows stay in the terminal: \(error)")
            key = RefusingKey()
        }
        conversation = Conversation(link: link, speaker: voice, key: key, face: panel, owner: owner)
        hotkey = Hotkey { [weak self] in self?.talk() }
        status = menuBarItem()
        listenToDaemon()
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

    private func converse() async {
        talking = true
        panel.present()
        do { try audio.start() } catch { NSLog("Memnox: no audio: \(error)") }
        var waiting = Self.firstWordSeconds
        panel.show(.listening, caption: "")
        while let said = await ears.listen(through: audio, waiting: waiting) {
            await conversation.heard(said)
            waiting = Self.followUpSeconds
            panel.show(.listening, caption: "")
        }
        audio.stop()
        panel.dismiss()
        talking = false
    }

    /// Something began or stopped waiting: said out loud, then listened to for the answer.
    private func arrived(_ event: DaemonEvent) {
        enqueue { [self] in
            if event.eventKind == .settled {
                await conversation.handle(event)
                return
            }
            panel.present()
            do { try audio.start() } catch { NSLog("Memnox: no audio: \(error)") }
            await conversation.handle(event)
            if event.eventKind == .held { await converse() } else {
                audio.stop()
                panel.dismiss()
            }
        }
    }

    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = tail
        tail = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    /// Reconnects after the daemon restarts, since it is the daemon's to come and go.
    private func listenToDaemon() {
        let link = self.link
        let deliver: @MainActor (DaemonEvent) -> Void = { [weak self] event in self?.arrived(event) }
        Task.detached {
            var id = 1_000
            while true {
                id += 1
                do {
                    for try await response in link.stream(DaemonRequest(id: id, method: .subscribe)) {
                        guard let event = response.event else { continue }
                        await deliver(event)
                    }
                } catch {}
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    @objc func showSetup() {
        let model = SetupModel(owner: owner, conversation: conversation, voice: voice) { [weak self] in
            self?.setupFinished()
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
            let hello = "I'm here whenever you press Option Space\(name)."
            panel.show(.speaking, caption: caption(hello))
            await voice.speak(hello)
            audio.stop()
            panel.dismiss()
        }
    }

    private func menuBarItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "Memnox")
        let menu = NSMenu()
        let talkItem = NSMenuItem(title: "Talk to Memnox", action: #selector(talk), keyEquivalent: " ")
        talkItem.keyEquivalentModifierMask = [.option]
        talkItem.target = self
        menu.addItem(talkItem)
        let setupItem = NSMenuItem(title: "Set Up Memnox…", action: #selector(showSetup), keyEquivalent: ",")
        setupItem.target = self
        menu.addItem(setupItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Memnox", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        return item
    }
}

/// Stands in when this Mac cannot hold a confirmation key: every allow is declined, never faked.
private final class RefusingKey: ConfirmKey {
    var publicPoint: String { "" }
    func sign(_ message: String, reason: String) async throws -> String? { nil }
}
