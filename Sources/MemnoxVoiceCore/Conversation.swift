import Foundation

/// Where the confirmation key stands with the daemon.
public enum KeyStatus: Equatable {
    case registered
    /// Somebody else's key is trusted, so nothing can be confirmed from here.
    case anotherKey
    case unreachable
    /// The daemon answers but does not know voice: an older Memnox than this app.
    case tooOld
}

/// Whether the daemon can hold a conversation, which setup checks before saying it is ready.
public enum DaemonVoice: Equatable {
    case ready
    case tooOld
    case unreachable
}

/// What the orb shows. Each state looks and moves differently, so a glance says which it is.
public enum VoiceState: Equatable, Sendable {
    case idle
    case listening
    case thinking
    case speaking
    /// Apple's Touch ID sheet is up, which is the one state that wants a hand and not a voice.
    case needsYou
}

/// Where the words go out loud.
public protocol Speaker: AnyObject {
    /// One sentence, returning once it has been said.
    func speak(_ sentence: String) async
    /// Queued behind whatever is being said, so a reply's sentences run on as one.
    func queue(_ sentence: String)
    /// Returns once everything queued has been said.
    func drained() async
    func stop()
}

/// What puts a session in front of the person: its own window, or a card to read along with.
public protocol Presenter: AnyObject {
    /// Brings the session's window forward, and says whether it could.
    func open(_ host: DisplayHost?) async -> Bool
    /// A live window on the session, kept up to date while it is open, with a way to its own window.
    func live(session: String, host: DisplayHost?) async
    /// The session's own terminal tab or editor conversation, brought forward.
    /// Says whether it came forward, so the voice never calls a window open that never appeared.
    func focus(session: String, host: DisplayHost?) async -> Typed
    func card(_ card: SummaryCard) async
    /// Types an instruction into the agent's terminal prompt a key at a time and sends it; the request
    /// is what an editor's extension reads the words from, since its link may carry none.
    func type(_ text: String, into host: DisplayHost?, request: String) async -> Typed
    /// Brings the conversation forward in its editor, types the instruction into its message box and sends it.
    func prefill(_ text: String, session: String, host: DisplayHost?) async -> Typed
    /// Opens a new terminal tab in the folder and types the line that starts an agent there.
    func launch(_ command: String, in folder: String?) async -> Typed
    /// A card that turns a page per file while the voice walks through the change.
    func walk(_ walk: WalkCard) async
    /// The whole screen: every agent on this Mac, with its logo and what it reaches.
    func scan(_ agents: [AgentNode], title: String) async
    /// A trace as a waterfall card: what ran, inside what, for how long, and what failed.
    func trace(_ trace: TraceData, title: String) async
    /// Every session as its own card, together; the app reads the sessions itself.
    func board(title: String) async
    /// Closes the live window on the session and its own terminal tab, and says whether the tab went;
    /// the request is what an editor's extension checks its close link against.
    func close(session: String, host: DisplayHost?, request: String) async -> Typed
    /// Every card, live window, board and scan off the screen; no session is touched.
    func dismissAll() async
}

extension Presenter {
    public func close(session: String, host: DisplayHost?, request: String) async -> Typed {
        Typed(.failed, "this Mac cannot close a session's tab")
    }

    public func dismissAll() async {}
}

/// A walk through a session's change: a heading and one page per file.
public struct WalkCard: Equatable {
    public let title: String
    public let pages: [WalkPage]
    public let sessionId: String?
    public let host: DisplayHost?

    public init(title: String, pages: [WalkPage], sessionId: String? = nil, host: DisplayHost? = nil) {
        self.title = title
        self.pages = pages
        self.sessionId = sessionId
        self.host = host
    }
}

/// What a summary card shows: a heading, the summary being said, and the code behind it.
public struct SummaryCard: Equatable {
    public let title: String
    public let text: String
    public let files: [CardFile]
    public let excerpt: CardExcerpt?
    /// The session it summarises and where it runs, so a button on the card goes straight to it.
    public let sessionId: String?
    public let host: DisplayHost?

    public init(title: String, text: String, files: [CardFile] = [], excerpt: CardExcerpt? = nil,
                sessionId: String? = nil, host: DisplayHost? = nil) {
        self.title = title
        self.text = text
        self.files = files
        self.excerpt = excerpt
        self.sessionId = sessionId
        self.host = host
    }
}

/// The orb and the pill, told what to show.
public protocol Face: AnyObject {
    func show(_ state: VoiceState, caption: String)
}

/// Talks and listens on the person's behalf: what they said goes whole to their own brain, what
/// is waiting on them is said out loud, and every allow waits for their fingerprint. It holds no
/// policy and never matches words: the brain understands them and the daemon decides.
public final class Conversation {
    private let link: DaemonLink
    private let speaker: Speaker
    private let key: ConfirmKey
    private let face: Face
    private let owner: OwnerStore
    private let presenter: Presenter?
    private let chimes: Chimes?
    private var nextId = 1
    /// The held call last asked about out loud, so an answer elsewhere can end the question.
    private var asking: String?
    /// Set when the person talks over an answer, so the rest of it is never said.
    private var interrupted = false
    private let fillers: [String]
    /// Set as soon as any words of the answer are spoken, so the filler never talks over them.
    private var answering = false
    /// Whether the last turn needed one, since "let me look" twice running sounds like a machine.
    private var filledLastTurn = false
    private var fillerSpoke = false
    /// Only while answering the person, since "one sec" before a held call or a catch up sounds wrong.
    private var mayFill = false
    /// Set when the brain said the person is done, so the orb closes after this reply instead of listening on.
    private var ending = false
    /// Set when the brain said the person has not finished, so the orb waits longer for the rest.
    private var holding = false

    /// Whether the last turn was the brain waiting for the rest of what they were saying, read once.
    public func takeHold() -> Bool {
        defer { holding = false }
        return holding
    }

    /// Whether any words of the reply were said this turn, beyond a "let me look".
    public var spokeThisTurn: Bool { answering }

    /// Whether the last reply ended the conversation, read once.
    public func takeEnd() -> Bool {
        defer { ending = false }
        return ending
    }
    /// When the person last said something, since an allow may only follow their own words.
    private var lastHeard: Date?
    /// When their last word was recognised, set by whoever listened, so the wait for the end is timed.
    public var lastWordAt: Date?
    /// When the first sentence of the answer was ready to speak, for the trace of this turn.
    private var firstSentenceAt: Date?
    private let now: () -> Date
    /// The Mac's major version, taken in init so a test can name the System Settings pane of either release.
    private let macOSMajorVersion: Int
    /// Said when the daemon is older than the app, which is the one fix a person can make.
    static let tooOld = "The Memnox running on this Mac is older than this app, so it cannot answer yet. Update Memnox and ask me again."
    /// The operator tool the brain calls when the person is done talking.
    static let endTool = "end_conversation"
    /// The operator tool the brain calls when the person paused mid thought.
    static let holdTool = "keep_listening"
    /// Tools that act and answer with a read back at once, where "let me check" would be the wrong words.
    static let actingTools: Set<String> = [
        "start_session", "send_instruction", "watch_for", "pause_session", "show", "walk_through",
    ]
    /// Every operator tool that proposes an action starts with this, and each reads its proposal back at once.
    private static let proposingToolPrefix = "propose_"
    /// Said back when the person calls it, the way somebody looks up from their desk.
    public var wakeLines = WakeLines()
    /// When it was last called, so the first call in a while is greeted for the hour.
    private var lastCalled: Date?

    /// The line for being called now: a greeting for the hour the first time in a while, a word or two after.
    public func answerToCall() -> String {
        let moment = now()
        let since = lastCalled.map { moment.timeIntervalSince($0) }
        lastCalled = moment
        let hour = Calendar.current.component(.hour, from: moment)
        return wakeLines.line(address: chosenAddress(), hour: hour, sinceLastCall: since)
    }
    /// Long enough to say "yes, go ahead" and have the brain propose it.
    static let answerWindow: TimeInterval = 120

    public init(
        link: DaemonLink,
        speaker: Speaker,
        key: ConfirmKey,
        face: Face,
        owner: OwnerStore,
        presenter: Presenter? = nil,
        chimes: Chimes? = nil,
        now: @escaping () -> Date = Date.init,
        macOSMajorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
        fillers: [String] = ["One moment.", "Checking.", "Looking into it."]
    ) {
        self.now = now
        self.macOSMajorVersion = macOSMajorVersion
        self.fillers = fillers
        self.link = link
        self.speaker = speaker
        self.key = key
        self.face = face
        self.owner = owner
        self.presenter = presenter
        self.chimes = chimes
    }

    /// The names this machine uses, from the daemon, for the recognizer to listen for.
    public func vocabulary() async -> [String] {
        (try? await link.request(newRequest(.vocabulary)))?.words ?? []
    }

    /// A session as it is right now, for the live window on it; nil when the daemon does not know it.
    public func sessionView(_ sessionId: String) async -> SessionView? {
        var request = newRequest(.sessionView)
        request.sessionId = sessionId
        return (try? await link.request(request))?.session
    }

    /// The sessions lately, most recently active first, for the switcher to turn through.
    public func sessionsList() async -> [SessionCard] {
        (try? await link.request(newRequest(.sessionsList)))?.sessions ?? []
    }

    /// The person started talking: the brain starts now, so the answer skips its cold start.
    public func warm() async {
        _ = try? await link.request(newRequest(.warm))
    }

    /// Whether the daemon answers, and whether it speaks voice rather than only answering ok.
    public func daemonVoice() async -> DaemonVoice {
        guard let response = try? await link.request(DaemonRequest(id: takeId(), method: .waiting)) else {
            return .unreachable
        }
        return response.ok && response.waiting != nil ? .ready : .tooOld
    }

    /// Registers this Mac's key with the daemon, which trusts the first one it is given.
    public func registerKey() async -> KeyStatus {
        var request = DaemonRequest(id: takeId(), method: .registerKey)
        request.point = key.publicPoint
        guard let response = try? await link.request(request) else { return .unreachable }
        if response.outcome == Outcome.anotherKey { return .anotherKey }
        // Only the word itself counts, since an older daemon answered anything with a bare ok.
        return response.ok && response.outcome == Outcome.registered ? .registered : .tooOld
    }

    /// At launch: registers the key, and says so when somebody else's is already there.
    public func introduce() async {
        if await registerKey() == .anotherKey {
            await say("Another key is registered for confirmations on this Mac, so I will not confirm anything. Run memnox voice forget-key in a terminal, then open me again.")
        }
    }

    /// The words so far at a pause, sent the way `heard` would send them so the daemon can start
    /// the answer now and hand it over the moment `heard` arrives with the same words. Nothing of
    /// it is said or done before then, so a guess the person talks past costs nothing but the try.
    public func guess(_ said: String) async {
        let trimmed = said.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = withoutLeadingName(trimmed)
        guard words.contains(where: \.isLetter), !nameAlone(trimmed) else { return }
        var request = newRequest(.ask)
        request.said = withUnsent(words)
        request.speculative = true
        _ = try? await link.request(request)
    }

    /// What the person said, whole. No keyword decides anything here. `finished` says the brain
    /// held for the rest and none came, so it answers what it has rather than waiting again.
    public func heard(_ said: String, finished: Bool = false) async {
        let trimmed = said.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = withoutLeadingName(trimmed)
        // A lone "." is the recognizer hearing noise, and answering it makes the voice talk to nobody.
        guard words.contains(where: \.isLetter) else { return }
        interrupted = false
        lastHeard = now()
        // Its name alone is somebody getting its attention, answered the way the wake word is.
        if nameAlone(trimmed) {
            diary.note("heard my name alone: \(trimmed)")
            await say(answerToCall())
            face.show(.listening, caption: "")
            return
        }
        diary.note("heard: \(words)")
        chimes?.play(.sent)
        face.show(.thinking, caption: caption(words))
        var request = newRequest(.ask)
        request.said = withUnsent(words)
        if finished { request.finished = true }
        answering = false
        mayFill = true
        let askedAt = now()
        firstSentenceAt = nil
        let told = await speakStream(request)
        await reportTimings(askedAt: askedAt, spokeUntil: lastWordAt)
        mayFill = false
        filledLastTurn = fillerSpoke
        fillerSpoke = false
        // Heard before the apology starts, so a broken turn never sounds like a slow one.
        if told != .spoke, told != .silent { chimes?.play(.failed) }
        // Kept for the next question, so "why?" after Memnox was unreachable still has its thread.
        unsent = told == .spoke || told == .silent ? nil : (words, now())
        if told == .unreachable { await say("My apologies, I cannot reach Memnox on this Mac at the moment.") }
        if case .refused(let error) = told {
            await say(error == Self.tooOld ? error : "My apologies, I could not ask that: \(error).")
        }
        face.show(.listening, caption: "")
    }

    /// What they said while Memnox could not be reached, and when.
    private var unsent: (String, Date)?
    /// Long enough for a follow up to still be about what never arrived.
    private static let unsentKeptFor: TimeInterval = 120

    /// Their words, after what never reached the brain a moment ago, so the follow up makes sense.
    private func withUnsent(_ words: String) -> String {
        guard let missed = unsent, now().timeIntervalSince(missed.1) < Self.unsentKeptFor else { return words }
        unsent = nil
        return "Just before, Memnox could not be reached when they said: \"\(missed.0)\". Now they say: \(words)"
    }

    /// Welcome back: what waits on them, told by their own brain, and false when nothing does.
    @discardableResult
    public func welcomeBack(since: Date) async -> Bool {
        interrupted = false
        face.show(.thinking, caption: "catching up")
        var request = newRequest(.brief)
        request.briefing = Briefing.back.rawValue
        request.since = ISO8601DateFormatter().string(from: since)
        let told = await speakStream(request)
        if told != .spoke { face.show(.idle, caption: "") }
        return told == .spoke
    }

    /// How a streamed answer ended, so a brief that said nothing can fall back to the facts.
    enum Told: Equatable {
        case spoke
        case silent
        case refused(String)
        case unreachable
    }

    /// How the daemon's refusal of a method it does not know begins, which means it is older than the app.
    private static let unknownMethodError = "no method"

    /// Streams a turn into speech, sentence by sentence, and says how it ended.
    private func speakStream(_ request: DaemonRequest) async -> Told {
        streaming += 1
        defer { streaming -= 1 }
        diary.note("sent \(request.method)")
        var sentences = SentenceSplitter()
        var spoke = false
        do {
            for try await response in link.stream(request) {
                if let error = response.error, !response.ok {
                    diary.note("\(request.method) refused: \(error)")
                    return .refused(error.hasPrefix(Self.unknownMethodError) ? Self.tooOld : error)
                }
                // An older daemon answers a method it does not know with a bare ok and nothing more.
                guard let chunk = response.chunk else {
                    if response.event == nil, response.waiting == nil {
                        diary.note("\(request.method) answered with nothing: an older daemon")
                        return .refused(Self.tooOld)
                    }
                    continue
                }
                diary.note("chunk \(chunk.kind)\(chunk.text.map { ": \($0)" } ?? "")\(chunk.tool.map { " \(toolWord($0))" } ?? "")")
                if chunk.chunkKind == .text, !(chunk.text ?? "").isEmpty { spoke = true }
                if try await play(chunk, into: &sentences) { break }
            }
        } catch {
            diary.note("\(request.method) failed: \(error)")
            return spoke ? .spoke : .unreachable
        }
        if let rest = sentences.flush(), !interrupted {
            spoke = true
            flow(rest)
        }
        await speaker.drained()
        return spoke ? .spoke : .silent
    }

    private func newRequest(_ method: DaemonMethod) -> DaemonRequest {
        var request = DaemonRequest(id: takeId(), method: method)
        request.owner = owner.name
        return request
    }

    /// The person started talking over the answer: the voice stops now and the brain stops too.
    public func interrupt() async {
        interrupted = true
        speaker.stop()
        _ = try? await link.request(DaemonRequest(id: takeId(), method: .cancel))
    }

    /// Returns true once the turn is over.
    private func play(_ chunk: AskChunk, into sentences: inout SentenceSplitter) async throws -> Bool {
        switch chunk.chunkKind {
        case .text:
            // After keep_listening nothing more is said this turn, since anything would talk over them.
            guard !holding else { break }
            for sentence in sentences.push(chunk.text ?? "") where !interrupted { flow(sentence) }
        case .tool:
            // Whatever came before a tool call is a sentence on its own, even with no space after its "?".
            if let rest = sentences.flush(), !interrupted { flow(rest) }
            // The brain's own call, not the person's words, says they are done.
            if toolWord(chunk.tool) == Self.endTool {
                ending = true
                return false
            }
            // They are mid thought: nothing is said, so nothing talks over the rest of it.
            if toolWord(chunk.tool) == Self.holdTool {
                holding = true
                return false
            }
            // Looking something up takes seconds, so say so the moment it starts rather than on a timer.
            let acting = toolWord(chunk.tool).hasPrefix(Self.proposingToolPrefix) || Self.actingTools.contains(toolWord(chunk.tool))
            if mayFill, !acting, !answering, !fillerSpoke, !filledLastTurn, !interrupted, let words = fillers.randomElement() {
                fillerSpoke = true
                speaker.queue(words)
            }
            face.show(.thinking, caption: "reading \(toolWord(chunk.tool))")
        case .limited:
            if let rest = sentences.flush() { await say(rest) }
            await say("Your plan has reached its limit, so I could not finish that.")
        case .failed:
            // A turn the person cut short was stopped on purpose, so it is not reported as broken.
            guard !interrupted else { break }
            chimes?.play(.failed)
            if let rest = sentences.flush() { await say(rest) }
            await say("My apologies, that did not work: \(chunk.text ?? "the brain stopped").")
        case .done, .cancelled, .none:
            break
        }
        return chunk.endsTurn
    }

    /// Something that started or stopped waiting on the person.
    public func handle(_ event: DaemonEvent) async {
        switch event.eventKind {
        case .held:
            asking = event.subject
            interrupted = false
            var request = newRequest(.brief)
            request.briefing = Briefing.held.rawValue
            request.subject = event.subject
            chimes?.play(.held)
            face.show(.thinking, caption: "\(event.agentName ?? event.agent) needs you")
            // Told by their own brain with what the session has been doing; the facts alone if it cannot.
            if await speakStream(request) != .spoke, !interrupted {
                await say(heldQuestion(owner: owner.name, event: event))
            }
            let who = event.agentName ?? event.agent
            face.show(.listening, caption: caption("\(who) wants to \(event.what ?? event.summary)"))
        case .proposal:
            // Only after the person spoke: an allow nobody asked for is left alone, not put to Touch ID.
            if let heard = lastHeard, now().timeIntervalSince(heard) < Self.answerWindow {
                // The read back says what the sensor is for, so the sheet waits until it has been said.
                await untilQuiet()
                await confirm(event)
            } else {
                await decline(event)
            }
        case .paused:
            interrupted = false
            var request = newRequest(.brief)
            request.briefing = Briefing.paused.rawValue
            request.subject = event.subject
            if await speakStream(request) != .spoke, !interrupted {
                await say("I paused a session: \(event.summary).")
            }
        case .show:
            await show(event)
        case .notice:
            interrupted = false
            var request = newRequest(.brief)
            request.briefing = Briefing.notice.rawValue
            request.subject = event.subject
            face.show(.thinking, caption: caption(event.agentName ?? event.agent))
            // In its own words when it can; the plain fact when it cannot.
            if await speakStream(request) != .spoke, !interrupted { await say(event.summary) }
        case .settled:
            if asking == event.subject {
                asking = nil
                speaker.stop()
                chimes?.play(.settled)
                face.show(.idle, caption: "answered elsewhere")
            }
        case .none:
            break
        }
    }

    /// A window or a card the person asked for, put up while the answer is still being said.
    private func show(_ event: DaemonEvent) async {
        guard let presenter else { return }
        switch event.displayKind {
        case .open:
            if let session = event.sessionId {
                await presenter.live(session: session, host: event.host)
            } else if await !presenter.open(event.host) {
                diary.note("could not open the window for \(event.subject)")
                speaker.queue("My apologies, I could not bring its window forward.")
            }
        case .focus:
            if let session = event.sessionId {
                await shown(event, await presenter.focus(session: session, host: event.host))
            }
        case .type:
            face.show(.thinking, caption: "typing it in")
            await delivered(event, await presenter.type(event.summary, into: event.host, request: event.subject),
                            otherwise: "My apologies, I could not type it into its terminal.")
        case .prefill:
            face.show(.thinking, caption: "typing it in")
            let typed = await event.sessionId.asyncMap { await presenter.prefill(event.summary, session: $0, host: event.host) }
            await delivered(event, typed ?? Typed(.failed, "no session to type into"),
                            otherwise: typed?.outcome == .clipboard
                                ? "My apologies, I could not type it in safely, so your words are on the clipboard. Press Command V, then Return, in its chat."
                                : "My apologies, I could not type it into its chat.")
        case .launch:
            face.show(.thinking, caption: "starting it")
            await delivered(event, await presenter.launch(event.summary, in: event.host?.cwd),
                            otherwise: "My apologies, I could not start it.")
        case .walk:
            await presenter.walk(WalkCard(
                title: event.title ?? "Walk through",
                pages: (event.pages ?? []).map { WalkPage(path: $0.path, note: speakable($0.note), added: $0.added, removed: $0.removed, lines: $0.lines) },
                sessionId: event.sessionId,
                host: event.host
            ))
        case .agents:
            await presenter.scan(event.agents ?? [], title: event.title ?? "Your agents")
        case .trace:
            if let trace = event.trace { await presenter.trace(trace, title: event.title ?? "Trace") }
        case .sessions:
            await presenter.board(title: event.title ?? "Your sessions")
        case .close:
            face.show(.thinking, caption: "closing it")
            let closed = await event.sessionId.asyncMap { await presenter.close(session: $0, host: event.host, request: event.subject) }
            await delivered(event, closed ?? Typed(.failed, "no session to close"),
                            otherwise: "My apologies, I could not close its tab.")
        case .dismiss:
            await presenter.dismissAll()
        case .card:
            await presenter.card(SummaryCard(
                title: event.title ?? "Session",
                // Read, not heard, so the markdown stays for the card to lay out.
                text: event.summary,
                files: event.files ?? [],
                excerpt: event.excerpt,
                sessionId: event.sessionId,
                host: event.host
            ))
        case .none:
            break
        }
    }

    /// Tells the brain whether a window came forward, with no sound, since the brain is the one to say it.
    private func shown(_ event: DaemonEvent, _ typed: Typed) async {
        if typed.outcome != .typed { diary.note("could not bring \(event.subject) forward: \(typed.reason ?? "no reason")") }
        var request = newRequest(.delivered)
        request.subject = event.subject
        request.answer = typed.outcome.rawValue
        request.reason = typed.reason
        _ = try? await link.request(request)
    }

    /// Tells the brain waiting on it how typing went, so it says that rather than what it hoped.
    /// Only a daemon too old to listen leaves a failure for the app to say itself.
    private func delivered(_ event: DaemonEvent, _ typed: Typed, otherwise: String) async {
        chimes?.play(typed.outcome == .typed ? .done : .failed)
        if typed.outcome != .typed { diary.note("could not type for \(event.subject): \(typed.reason ?? typed.outcome.rawValue)") }
        var request = newRequest(.delivered)
        request.subject = event.subject
        request.answer = typed.outcome.rawValue
        request.reason = typed.reason
        let heard = (try? await link.request(request))?.ok == true
        let said = typed.outcome == .notAllowed ? notAllowedLine() : otherwise
        if !heard, typed.outcome != .typed { speaker.queue(said) }
        // The words on the clipboard need a hand from the person, so that one is always said.
        if heard, typed.outcome == .clipboard || typed.outcome == .notAllowed { speaker.queue(said) }
    }

    /// Whether they have heard how to let Memnox type, so the second time is one short line rather than the whole of it.
    private var toldHowToAllow = false

    /// What to do about it in full the first time, since nothing they say can fix it, and after that only where the words are.
    private func notAllowedLine() -> String {
        defer { toldHowToAllow = true }
        return toldHowToAllow
            ? "Your words are on the clipboard again."
            : "I am not permitted to type yet. In System Settings, Privacy and Security, \(Self.typingPane(macOSMajorVersion: macOSMajorVersion)), switch Memnox on, or off and on again if it already is. Your words are on the clipboard meanwhile."
    }

    /// Where macOS lists the apps that may press keys: renamed in macOS 27, and a grant left from an
    /// earlier build shows as on there while doing nothing, which only switching it off and on clears.
    static func typingPane(macOSMajorVersion: Int) -> String {
        macOSMajorVersion >= typingPaneRenamedIn ? "Device Control and Data Access" : "Accessibility"
    }
    /// The first macOS release that calls the typing pane Device Control and Data Access.
    static let typingPaneRenamedIn = 27

    /// A proposal to let something happen: Touch ID signs exactly this one, or it is declined.
    private func confirm(_ event: DaemonEvent) async {
        let answerKind: ProposalAnswer
        var signature: String?
        face.show(.needsYou, caption: caption("Touch ID to \(event.summary)"))
        do {
            signature = try await key.sign(
                confirmationMessage(subject: event.subject, answer: ProposalAnswer.confirmed.rawValue),
                reason: event.summary
            )
            answerKind = signature == nil ? .declined : .confirmed
        } catch {
            answerKind = .declined
        }
        var request = newRequest(.confirm)
        request.subject = event.subject
        request.answer = answerKind.rawValue
        request.signature = signature
        let response = try? await link.request(request)
        if response?.ok == true {
            chimes?.play(answerKind == .confirmed ? .allowed : .declined)
            await say(Self.afterConfirm(answerKind, outcome: response?.outcome))
        } else {
            chimes?.play(.failed)
            await say("My apologies, that was not confirmed: \(response?.error ?? "Memnox did not answer").")
        }
    }

    /// Replies streaming in now; a proposal arrives while its own read back is still being written.
    private var streaming = 0

    /// Waits for the reply in flight to finish and be said, bounded so a stuck stream never holds Touch ID back.
    private func untilQuiet() async {
        var checks = 0
        while streaming > 0, checks < Self.quietChecks {
            checks += 1
            try? await Task.sleep(nanoseconds: UInt64(Self.quietCheckInterval * Self.nanosecondsPerSecond))
        }
        await speaker.drained()
    }

    /// Twenty seconds in tenths, longer than any read back takes to stream.
    static let quietChecks = 200
    /// A tenth of a second between checks, which is what `quietChecks` counts in.
    private static let quietCheckInterval: TimeInterval = 0.1
    private static let nanosecondsPerSecond: TimeInterval = 1_000_000_000

    /// A command still running on its own, like a login waiting on its browser page, is never called done.
    static func afterConfirm(_ answer: ProposalAnswer, outcome: String?) -> String {
        guard answer == .confirmed else { return "Very well. I have left it as it was." }
        return outcome == Outcome.started
            ? "Very well. It is under way, and I will tell you if anything goes wrong."
            : "Very well. It is done."
    }

    /// A held call answered with a button: a deny goes as it is, and an allow only with Touch ID over exactly this call.
    public func answerHeld(_ subject: String, _ answer: HoldAnswer, reason: String) async -> HeldOutcome {
        var request = newRequest(.confirm)
        request.subject = subject
        request.answer = answer.rawValue
        if answer != .deny {
            face.show(.needsYou, caption: caption("Touch ID to \(reason)"))
            let signature = try? await key.sign(confirmationMessage(subject: subject, answer: answer.rawValue), reason: reason)
            guard let signature else {
                face.show(.idle, caption: "")
                return .cancelled
            }
            request.signature = signature
        }
        let response = try? await link.request(request)
        guard response?.ok == true else {
            chimes?.play(.failed)
            return .failed(response?.error ?? "Memnox did not answer")
        }
        // Answered by hand, so the voice stops asking rather than waiting on a reply that already came.
        if asking == subject {
            asking = nil
            speaker.stop()
        }
        chimes?.play(answer == .deny ? .declined : .allowed)
        face.show(.idle, caption: "")
        return .answered
    }

    private func decline(_ event: DaemonEvent) async {
        var request = newRequest(.confirm)
        request.subject = event.subject
        request.answer = ProposalAnswer.declined.rawValue
        _ = try? await link.request(request)
        chimes?.play(.declined)
        await say("Something proposed an allow you did not ask for. I have declined it.")
    }

    /// The app's part of the answer, sent once it is spoken, so a trace shows where the seconds went:
    /// waiting for the end of what they said, the answer arriving, and saying it.
    private func reportTimings(askedAt: Date, spokeUntil: Date?) async {
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let done = now()
        var spans: [MacSpan] = []
        if let spoke = spokeUntil, spoke < askedAt {
            spans.append(MacSpan(name: SpanName.waitingForEnd, startAt: stamp.string(from: spoke), endAt: stamp.string(from: askedAt)))
        }
        if let first = firstSentenceAt {
            spans.append(MacSpan(name: SpanName.firstSentence, startAt: stamp.string(from: askedAt), endAt: stamp.string(from: first)))
            spans.append(MacSpan(name: SpanName.speaking, startAt: stamp.string(from: first), endAt: stamp.string(from: done)))
        }
        guard !spans.isEmpty else { return }
        var request = newRequest(.trace)
        request.spans = spans
        // Sent after the answer is spoken, and its failure ignored, so a trace never holds up the next question.
        _ = try? await link.request(request)
    }

    /// The app's step names on a trace, which the trace card names again under a `mac.` prefix.
    private enum SpanName {
        static let waitingForEnd = "waiting for the end"
        static let firstSentence = "first sentence ready"
        static let speaking = "speaking"
    }

    /// The daemon's outcome words this app acts on.
    private enum Outcome {
        /// The key was already registered by somebody else.
        static let anotherKey = "another key"
        static let registered = "registered"
        /// A confirmed command still running on its own.
        static let started = "started"
    }

    /// A sentence of a streamed reply, queued so the reply is spoken as one run rather than line by line.
    private func flow(_ sentence: String) {
        if firstSentenceAt == nil { firstSentenceAt = now() }
        answering = true
        let spoken = speakable(sentence)
        guard !spoken.isEmpty else { return }
        face.show(.speaking, caption: caption(spoken))
        speaker.queue(spoken)
    }

    private func say(_ sentence: String) async {
        answering = true
        let spoken = speakable(sentence)
        guard !spoken.isEmpty else { return }
        face.show(.speaking, caption: caption(spoken))
        await speaker.speak(spoken)
    }

    private func takeId() -> Int {
        defer { nextId += 1 }
        return nextId
    }
}

extension Optional {
    /// The value mapped through async work, or nil without doing it.
    func asyncMap<T>(_ transform: (Wrapped) async -> T) async -> T? {
        guard let value = self else { return nil }
        return await transform(value)
    }
}

/// Only what a voice should say: no markdown, no code marks, and a pause where a dash stood.
public func speakable(_ text: String) -> String {
    var spoken = text
    for mark in markdownMarks { spoken = spoken.replacingOccurrences(of: mark, with: "") }
    for dash in spokenDashes {
        spoken = spoken.replacingOccurrences(of: dash, with: ", ")
    }
    return spoken.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

/// Code marks, emphasis, headings and strikethrough, which a voice would otherwise read out.
private let markdownMarks = ["`", "*", "#", "_", "~"]
/// Em and en dashes, spaced first so the spaces go with them.
private let spokenDashes = [" \u{2014} ", "\u{2014}", " \u{2013} ", "\u{2013}"]
