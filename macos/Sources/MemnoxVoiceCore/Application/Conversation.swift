import Foundation

/// Talks and listens on the person's behalf: what they said goes whole to their own brain, what
/// is waiting on them is said out loud, and every allow waits for their fingerprint. It holds no
/// policy and never matches words: the brain understands them and the daemon decides.
/// The operator's tools by the names the runtime gives them, so a list of them is never spelled twice.
enum ToolName {
    static let startSession = "start_session"
    static let sendInstruction = "send_instruction"
    static let watchFor = "watch_for"
    static let pauseSession = "pause_session"
    static let show = "show"
    static let walkThrough = "walk_through"
    static let typeInApp = "type_in_app"
    static let controlApp = "control_app"
    static let answerQuestion = "answer_question"
    static let searchWeb = "search_web"
    static let openLink = "open_link"
    static let createFolder = "create_folder"
    static let signIn = "sign_in"
}

public final class Conversation {
    private let link: DaemonLink
    private let speaker: Speaker
    private let key: ConfirmKey
    private let face: Face
    private let owner: OwnerStore
    private let presenter: Presenter?
    private let chimes: Chimes?
    /// Shared with every other use case, since over the relay one session carries them all and refuses an id in flight.
    private let ids: RequestIds
    /// True when the answer to a subject reaches a server, which never takes a yes without a signature, whatever the event says.
    private let signsEveryYes: (String) -> Bool
    /// The server that raised a subject, nil for this Mac, so the person sees where a call waits.
    private let raisedOn: (String) -> String?
    /// The calls teammates' agents raised that the workspace routed to this person, answered through it and never a daemon.
    private let workspace: WorkspaceAnswering?
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
    /// Rule proposals the person asked for by pressing hand over, so they reach the card rather than a decline.
    private var handedOver = Set<String>()
    /// The hand over still waiting on the daemon, whose proposal event may arrive before its answer does.
    private var handingOver: Task<DaemonResponse?, Never>?
    /// A phone's turn put together from its notices, so each one shows the whole of it so far.
    private var phoneConversation = PhoneConversation()
    /// The phone holding this Mac's voice, set the moment the daemon says the voice moved, so nothing an event raises is said here meanwhile.
    public var phoneHolds: PhoneVoice?

    /// The phone driving this Mac, kept from the notice so its yes is asked there for as long as the grant lasts.
    private var drivenBy: DriveGrant?

    /// The phone that answers for this Mac now, the one holding the voice or driving it, so a yes is its Face ID
    /// rather than Touch ID here; nil when nobody does.
    public var phoneAnswers: String? {
        if let phoneHolds { return phoneHolds.name }
        guard let drivenBy, drivenBy.isLive(at: now()) else { return nil }
        return drivenBy.name
    }

    /// The phone a yes to this event is left to: the one answering for this Mac now, else the paired phone the daemon
    /// named on it, since pairing is enough and the person may be too far from the Mac to touch Touch ID.
    public func phoneFor(_ event: DaemonEvent) -> String? {
        if let phoneAnswers { return phoneAnswers }
        guard let paired = event.answerOn, !OwnDevices.shared.ids.contains(paired.deviceId) else { return nil }
        return paired.name
    }

    /// Whether an event is only shown here: stamped for a phone, or arriving while a phone holds the voice or drives.
    public func isQuiet(_ event: DaemonEvent) -> Bool {
        event.quietOnMac(phoneHolds: phoneAnswers != nil)
    }

    /// Said instead of Touch ID while a phone answers for this Mac, since that phone asks Face ID for the same yes.
    static func answerOnPhone(_ phone: String) -> String {
        let name = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        return "Answer it on \(name.isEmpty ? "your phone" : name), which asks for Face ID."
    }
    /// When their last word was recognised, set by whoever listened, so the wait for the end is timed.
    public var lastWordAt: Date?
    /// When the first sentence of the answer was ready to speak, for the trace of this turn.
    private var firstSentenceAt: Date?
    private let now: () -> Date
    /// The Mac's major version, taken in init so a test can name the System Settings pane of either release.
    private let macOSMajorVersion: Int
    /// Whether this build is signed ad hoc, which makes macOS forget the typing grant each time it is rebuilt.
    private let adHocBuild: Bool
    /// How the person asked to be addressed, read through a closure so the composition root owns the file and tests choose it.
    private let address: () -> String?
    /// Their name, which the wake line keeps for a greeting and says far less often than the address.
    private let name: () -> String?
    /// The app in front of the person as they speak, so the brain hears their words against what they work in.
    private let lookingAt: () -> String?
    /// The title of that app's window in front, so "the one in front of me" names a folder rather than a guess.
    private let lookingAtWindow: () -> String?
    /// Said when the daemon is older than the app, which is the one fix a person can make.
    static let tooOld = "The Memnox running on this Mac is older than this app, so it cannot answer yet. Update Memnox and ask me again."
    /// The operator tool the brain calls when the person is done talking.
    static let endTool = "end_conversation"
    /// The operator tool the brain calls when the person paused mid thought.
    static let holdTool = "keep_listening"
    /// Tools that act and answer with a read back at once, where "let me check" would be the wrong words.
    static let actingTools: Set<String> = [
        ToolName.startSession, ToolName.sendInstruction, ToolName.watchFor, ToolName.pauseSession,
        ToolName.show, ToolName.walkThrough, ToolName.typeInApp, ToolName.controlApp, ToolName.answerQuestion,
    ]

    /// The calls that change something the person can see, which the side panel lists; a lookup is left out as talk.
    static let listedTools: Set<String> = actingTools.union([
        ToolName.searchWeb, ToolName.openLink, ToolName.createFolder, ToolName.signIn,
    ])

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
        // The same rule WakeLines greets by, kept here so the brain is told it need not greet again.
        if since.map({ $0 >= WakeLines.freshAfter }) ?? true { greetedAt = moment }
        let hour = Calendar.current.component(.hour, from: moment)
        return wakeLines.line(address: address(), name: name(), hour: hour, sinceLastCall: since, at: moment)
    }
    /// When the Mac last greeted them out loud, which the brain hears of so the same hello is never said twice.
    private var greetedAt: Date?
    /// A greeting holds for this long, the same span the daemon counts as one sitting.
    static let greetingHolds: TimeInterval = 30 * 60

    /// Long enough to say "yes, go ahead" and have the brain propose it.
    static let answerWindow: TimeInterval = 120
    /// How long after a sign in finished its request is still worth carrying on with, when nothing was said since.
    static let resumeWindow: TimeInterval = 60

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
        adHocBuild: Bool = false,
        address: @escaping () -> String? = { nil },
        name: @escaping () -> String? = { nil },
        lookingAt: @escaping () -> String? = { nil },
        lookingAtWindow: @escaping () -> String? = { nil },
        // Nothing said while it looks something up or acts: only results, and questions only it can't answer alone.
        fillers: [String] = [],
        quietLimit: TimeInterval = 75,
        reconnectWait: TimeInterval = 8,
        ids: RequestIds = RequestIds(),
        signsEveryYes: @escaping (String) -> Bool = { _ in false },
        raisedOn: @escaping (String) -> String? = { _ in nil },
        workspace: WorkspaceAnswering? = nil
    ) {
        self.workspace = workspace
        self.ids = ids
        self.signsEveryYes = signsEveryYes
        self.raisedOn = raisedOn
        self.quietLimit = quietLimit
        self.reconnectWait = reconnectWait
        self.now = now
        self.address = address
        self.name = name
        self.lookingAt = lookingAt
        self.lookingAtWindow = lookingAtWindow
        self.macOSMajorVersion = macOSMajorVersion
        self.adHocBuild = adHocBuild
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

    /// One file's diff as the session left it, for the live window to open under the file's name; nil when none is known.
    public func sessionDiff(_ sessionId: String, path: String) async -> CardExcerpt? {
        var request = newRequest(.sessionView)
        request.sessionId = sessionId
        request.path = path
        return (try? await link.request(request))?.diff
    }

    /// The sessions lately, most recently active first, for the switcher to turn through.
    public func sessionsList() async -> [SessionCard] {
        (try? await link.request(newRequest(.sessionsList)))?.sessions ?? []
    }

    /// The home's five blocks; nil when the daemon is away or too old to know them, so the window keeps what it had.
    public func home() async -> DaemonHome? {
        guard let response = try? await link.request(newRequest(.home)), response.ok else { return nil }
        return response.home
    }

    /// The person pressed to hand the ready action over: the daemon proposes the rule, and that proposal counts as
    /// asked for, so it goes on the rule card for a place and Touch ID rather than being declined as unasked.
    public func handOver(_ action: String) async -> HandOver {
        var request = newRequest(.handOver)
        request.action = action
        let link = self.link
        let asking = Task { try? await link.request(request) }
        handingOver = asking
        let response = await asking.value
        if handingOver == asking { handingOver = nil }
        guard let response else { return .unreachable }
        if response.ok, let proposed = response.proposed {
            handedOver.insert(proposed)
            return .proposed(proposed)
        }
        // A runtime from before the home answers a method it does not know with a bare ok and nothing else.
        return .refused(response.reason ?? response.error ?? "This Memnox is older than the app")
    }

    /// Whether a proposal is the one a hand over asked for, waiting on one still in flight since its event can come first.
    private func fromHandOver(_ subject: String) async -> Bool {
        if handedOver.remove(subject) != nil { return true }
        guard let pending = handingOver, let response = await pending.value else { return false }
        return response.ok && response.proposed == subject
    }

    /// Which agents can be the voice. A recheck asks every installed one again, which takes up to a minute and a half.
    public func voiceAgents(recheck: Bool = false) async -> VoiceAgentsAnswer {
        var request = newRequest(.voiceAgents)
        if recheck { request.recheck = true }
        return await agentsAnswer(request)
    }

    /// The person picking the agent the voice thinks with, from the next question on.
    public func chooseVoiceAgent(_ kind: String) async -> VoiceAgentsAnswer {
        var request = newRequest(.chooseVoiceAgent)
        request.voiceAgent = kind
        return await agentsAnswer(request)
    }

    private func agentsAnswer(_ request: DaemonRequest) async -> VoiceAgentsAnswer {
        guard let response = try? await link.request(request) else { return .unreachable }
        if response.ok, let agents = response.voiceAgents { return .agents(agents) }
        // An older daemon answers a method it does not know with a bare ok and no agents.
        return .refused(response.error ?? "This Memnox is older than the app")
    }

    /// The person's own connected tools, for the menu and the notch to show.
    public func connections() async -> ConnectionsAnswer {
        guard let response = try? await link.request(newRequest(.connectionsList)) else { return .unreachable }
        if response.ok, let connections = response.connections { return .connections(connections) }
        // An older daemon answers a method it does not know with a bare ok and no connections.
        return .refused(response.reason ?? response.error ?? "This Memnox is older than the app")
    }

    /// The person started talking: the brain starts now, so the answer skips its cold start.
    public func warm() async {
        _ = try? await link.request(newRequest(.warm))
    }

    /// Whether the daemon answers, and whether it speaks voice rather than only answering ok.
    public func daemonVoice() async -> DaemonVoice {
        guard let pong = try? await link.request(DaemonRequest(id: takeId(), method: .ping)) else { return .unreachable }
        if let refusal = Self.refusal(pong) { return refusal }
        guard isAtLeast(pong.version, MinimumRuntime.version) else { return .tooOld }
        guard let response = try? await link.request(DaemonRequest(id: takeId(), method: .waiting)) else {
            return .unreachable
        }
        if let refusal = Self.refusal(response) { return refusal }
        guard response.ok, response.waiting != nil else { return .tooOld }
        // A runtime built from a checkout keeps its version while it gains methods, so the newest one this app needs
        // is asked for too; only a plain unknown method counts, since a dropped answer is not an older Memnox.
        if let machine = try? await link.request(DaemonRequest(id: takeId(), method: .machine)),
           !machine.ok, machine.error?.hasPrefix(Self.unknownMethodError) == true {
            return .tooOld
        }
        return .ready
    }

    /// A no with a reason is kept in the daemon's words, since only an unknown method means an older Memnox.
    private static func refusal(_ response: DaemonResponse) -> DaemonVoice? {
        guard !response.ok, let error = response.error, !error.hasPrefix(unknownMethodError) else { return nil }
        return .refused(error)
    }

    /// Whether this Mac holds a key Touch ID can sign with; without one every allow stays in the terminal.
    public var canSign: Bool { !key.publicPoint.isEmpty }

    /// Registers this Mac's key with the daemon, which trusts the first one it is given.
    public func registerKey() async -> KeyStatus {
        var request = DaemonRequest(id: takeId(), method: .registerKey)
        request.point = key.publicPoint
        guard let response = try? await link.request(request) else { return .unreachable }
        if response.outcome == Outcome.anotherKey { return .anotherKey }
        if !response.ok, let error = response.error, !error.hasPrefix(Self.unknownMethodError) { return .refused(error) }
        // Only the word itself counts, since an older daemon answered anything with a bare ok.
        return response.ok && response.outcome == Outcome.registered ? .registered : .tooOld
    }

    /// At launch: registers the key, and says so when somebody else's is already there.
    public func introduce() async {
        if await registerKey() == .anotherKey {
            await say(Self.anotherKeyLine)
        }
    }

    /// The words so far at a pause, sent the way `heard` would send them so the daemon can start
    /// the answer now and hand it over the moment `heard` arrives with the same words. Nothing of
    /// it is said or done before then, so a guess the person talks past costs nothing but the try.
    public func guess(_ said: String) async {
        let trimmed = said.trimmingCharacters(in: .whitespacesAndNewlines)
        // Cut the same way `heard` cuts, so a guess and the words that follow it match and the guess is kept.
        let words = withoutTrailingName(withoutLeadingName(trimmed))
        guard words.contains(where: \.isLetter), !nameAlone(trimmed) else { return }
        var request = newRequest(.ask)
        request.said = withUnsent(words)
        request.lookingAt = lookingAt()
        request.lookingAtWindow = lookingAtWindow()
        request.teamCalls = workspace?.briefs()
        request.speculative = true
        _ = try? await link.request(request)
    }

    /// What the person said, whole. No keyword decides anything here. `finished` says the brain
    /// held for the rest and none came, so it answers what it has rather than waiting again.
    /// `intent` is how they asked, set by the keys they held, never by a word they said.
    public func heard(_ said: String, finished: Bool = false, intent: AskIntent? = nil) async {
        let trimmed = said.trimmingCharacters(in: .whitespacesAndNewlines)
        // Its name called at either end is somebody getting its attention, not part of the question.
        let words = withoutTrailingName(withoutLeadingName(trimmed))
        // A lone "." is the recognizer hearing noise, and answering it makes the voice talk to nobody.
        guard words.contains(where: \.isLetter) else { return }
        interrupted = false
        macTold = false
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
        face.asked(words)
        var request = newRequest(.ask)
        request.said = withUnsent(words)
        request.lookingAt = lookingAt()
        request.lookingAtWindow = lookingAtWindow()
        // Every ask names the team's questions, the empty list included, so the brain never answers one already gone.
        request.teamCalls = workspace?.briefs()
        if finished { request.finished = true }
        if let greetedAt, now().timeIntervalSince(greetedAt) < Self.greetingHolds { request.greeted = true }
        request.intent = intent?.rawValue
        answering = false
        mayFill = true
        let askedAt = now()
        firstSentenceAt = nil
        showingReply = true
        var told = await speakStream(request)
        // launchd starts a stopped daemon again within seconds, so a question asked in that gap waits for it rather than failing.
        var waited: TimeInterval = 0
        while told == .unreachable, daemonDown, waited < reconnectWait, !interrupted {
            try? await Task.sleep(nanoseconds: UInt64(Self.reconnectStep * Self.nanosecondsPerSecond))
            waited += Self.reconnectStep
            told = await speakStream(request)
        }
        showingReply = false
        face.replied(failure: Self.failure(told))
        await reportTimings(askedAt: askedAt, spokeUntil: lastWordAt)
        mayFill = false
        filledLastTurn = fillerSpoke
        fillerSpoke = false
        // Heard before the apology starts, so a broken turn never sounds like a slow one.
        if told != .spoke, told != .silent { chimes?.play(.failed) }
        // Holding on words already marked whole is the brain ignoring the note, and silence there sounds like nobody heard.
        if finished, holding, !interrupted {
            diary.note("the brain held again on words marked whole: \(words)")
            await say(Self.sayItAgain)
        }
        // Kept for the next question, so "why?" after Memnox was unreachable still has its thread.
        // A stalled turn reached the brain, so its words are already in the conversation.
        unsent = told == .spoke || told == .silent || told == .refused(Self.stalled) ? nil : (words, now())
        if told == .unreachable { await say("My apologies, I cannot reach Memnox on this Mac at the moment.") }
        if case .refused(let error) = told {
            await say(error == Self.tooOld || error == Self.stalled ? error : "My apologies, I could not ask that: \(error).")
        }
        face.show(.listening, caption: "")
    }

    /// Why a turn got no answer, as the history shows it beside the question; nil when it was answered or simply quiet.
    static func failure(_ told: Told) -> String? {
        switch told {
        case .spoke, .silent: return nil
        case .unreachable: return "Memnox could not be reached on this Mac"
        case .refused(let error):
            if error == tooOld { return "The Memnox running here is older than this app" }
            return error == stalled ? "No answer came, so it stopped waiting" : error
        }
    }

    /// Set once this Mac said out loud what the person has to do, so the brain's own words on it are left out.
    private var macTold = false

    /// Set while an answer to the person streams, so its words reach the notch and a brief's never do.
    private var showingReply = false

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

    /// The daemon's refusal of a brief whose call is no longer waiting on anybody.
    static let nothingToBrief = "nothing to brief about"

    /// Whether a held call is still the one being asked about, so the microphone stays open only for a live one.
    public func stillAsking(_ subject: String) -> Bool { asking == subject }

    /// How the daemon's refusal of a method it does not know begins, which means it is older than the app.
    private static let unknownMethodError = "no method"

    /// Said when a turn went quiet without ending, so the person is never left waiting on silence.
    static let stalled = "My apologies, I lost the thread there. Could you say that again?"

    /// Longer than any tool takes between two chunks, typing a few sentences into a terminal included.
    private let quietLimit: TimeInterval

    /// Set when the last turn found no daemon at the socket at all, the one failure worth waiting out.
    private var daemonDown = false
    /// How long a question waits for a daemon that is starting again, about as long as launchd takes.
    private let reconnectWait: TimeInterval
    /// How often it looks for the daemon while it waits.
    private static let reconnectStep: TimeInterval = 0.5

    /// Thrown when the daemon sent nothing for longer than any turn takes.
    struct Stalled: Error {}

    /// The daemon's chunks as they come, ended with `Stalled` once none has arrived for `limit` seconds,
    /// since a turn that never sends its end would otherwise hold the orb in thinking for good.
    static func quieted(
        _ upstream: AsyncThrowingStream<DaemonResponse, Error>,
        limit: TimeInterval
    ) -> AsyncThrowingStream<DaemonResponse, Error> {
        AsyncThrowingStream { continuation in
            let heard = LastHeard()
            let pump = Task {
                do {
                    for try await response in upstream {
                        await heard.touch()
                        continuation.yield(response)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            let watch = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: UInt64(min(limit, 1) * nanosecondsPerSecond))
                    if await heard.quietFor() >= limit {
                        continuation.finish(throwing: Stalled())
                        pump.cancel()
                        return
                    }
                }
            }
            continuation.onTermination = { _ in
                pump.cancel()
                watch.cancel()
            }
        }
    }

    /// When the last chunk arrived, shared between the reading task and the one watching it.
    private actor LastHeard {
        private var at = Date()
        func touch() { at = Date() }
        func quietFor() -> TimeInterval { Date().timeIntervalSince(at) }
    }

    /// Streams a turn into speech, sentence by sentence, and says how it ended.
    private func speakStream(_ request: DaemonRequest) async -> Told {
        streaming += 1
        defer { streaming -= 1 }
        daemonDown = false
        diary.note("sent \(request.method)")
        saidThisReply = []
        var sentences = SentenceSplitter()
        var spoke = false
        do {
            for try await response in Self.quieted(link.stream(request), limit: quietLimit) {
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
        } catch is Stalled {
            diary.note("\(request.method) sent nothing for \(Int(quietLimit)) seconds, so it was stopped")
            _ = try? await link.request(DaemonRequest(id: takeId(), method: .cancel))
            if let rest = sentences.flush(), !interrupted { flow(rest) }
            await speaker.drained()
            return spoke ? .spoke : .refused(Self.stalled)
        } catch {
            diary.note("\(request.method) failed: \(error)")
            if case ProtocolError.notRunning = error { daemonDown = true }
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
            // After keep_listening nothing more is said this turn, since anything would talk over them;
            // nor once this Mac told them what to do, since the brain would only say it again.
            guard !holding, !macTold else { break }
            if showingReply, !interrupted, let text = chunk.text { face.replying(text) }
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
            if Self.listedTools.contains(toolWord(chunk.tool)) { face.acted(TakenAction(tool: toolWord(chunk.tool), at: now())) }
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
            // The phone holding the voice asks; the island shows the card for a hand at the Mac, with no sound.
            if isQuiet(event) {
                diary.note("\(event.subject) held while \(phoneHolding(event)) speaks, shown on the island without a sound")
                return
            }
            asking = event.subject
            interrupted = false
            var request = newRequest(.brief)
            request.briefing = Briefing.held.rawValue
            request.subject = event.subject
            chimes?.play(.held)
            let who = CallLabel.label(event.agentName ?? event.agent, at: .raised(on: raisedOn(event.subject)))
            face.show(.thinking, caption: caption("\(who) needs you"))
            // Told by their own brain with what the session has been doing; the facts alone if it cannot.
            let told = await speakStream(request)
            // Nothing to brief is a call already answered or run out, and asking about it asks about nothing.
            if told == .refused(Self.nothingToBrief) {
                asking = nil
                face.show(.idle, caption: "")
                return
            }
            if told != .spoke, !interrupted {
                await say(heldQuestion(owner: owner.name, event: event, label: who))
            }
            face.show(.listening, caption: caption("\(who) wants to \(event.what ?? event.summary)"))
        case .proposal:
            // The phone that asked answers it, so it is never declined here; a rule still goes on the card for a hand at the Mac.
            if isQuiet(event) {
                if let rule = event.rule { face.rule(subject: event.subject, rule) }
                diary.note("\(event.subject) proposed while \(phoneHolding(event)) speaks, left for it to answer")
                return
            }
            // Only after the person spoke: an allow nobody asked for is left alone, not put to Touch ID.
            // Or pressed for: hand over names exactly this proposal, so nothing else rides on the press.
            let spoke = lastHeard.map { now().timeIntervalSince($0) < Self.answerWindow } ?? false
            let pressed = await fromHandOver(event.subject)
            let asked = spoke || pressed
            if let team = event.teamAnswer, asked {
                // The read back names the call, so the sheet waits until it has been said, as any proposal's does.
                await untilQuiet()
                await carryOut(team, proposal: event)
            } else if let rule = event.rule, asked {
                // A rule waits on the card for where it holds; the sheet comes up only once a place is picked.
                face.rule(subject: event.subject, rule)
                if let phone = phoneFor(event) { await leaveForPhone(event, phone) }
            } else if let work = event.work, asked {
                // What goes out in their name waits on its card, read whole; the sheet comes up on Send.
                face.work(subject: event.subject, work)
                if let phone = phoneFor(event) { await leaveForPhone(event, phone) }
            } else if asked {
                // The same proposal can arrive twice, from the live feed and from a look at what waits, and confirming
                // it twice put Touch ID up twice for one request; so each is put to the sensor once.
                guard takenUp.insert(event.subject).inserted else {
                    diary.note("\(event.subject) is already being confirmed")
                    return
                }
                // The read back says what the sensor is for, so the sheet waits until it has been said.
                await untilQuiet()
                await confirm(event)
            } else {
                await decline(event)
            }
        case .paused:
            if isQuiet(event) {
                diary.note("paused \(event.subject) while \(phoneHolding(event)) speaks, shown without a sound")
                return
            }
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
            // A phone's conversation is shown and never said, so the room hears nothing and no chime plays.
            if let turn = event.phoneTurn {
                showPhone(turn)
                return
            }
            if let drivenBy = event.drivenBy {
                let grant = DriveGrant(drivenBy, now: now())
                self.drivenBy = grant
                diary.note(grant.map { "\($0.name) drives this Mac until \(drivenBy.until ?? "")" } ?? "\(drivenBy.name) stopped driving this Mac")
                face.driven(grant)
                return
            }
            // The pill says it and the request carries on, so a finished sign in is shown rather than briefed.
            if event.noticeKind == .signedIn, let signedIn = event.signedIn {
                // Asked again only while nothing has moved on, so an old request never lands on top of a newer one.
                let shown = movedOn(since: event.at) ? signedIn.withoutResume : signedIn
                diary.note("signed in to \(signedIn.toolkit)\(shown.resume == nil ? "" : ", carrying on")")
                face.signedIn(shown)
                return
            }
            if event.noticeKind == .signInStalled, let signedIn = event.signedIn {
                face.signedIn(signedIn)
            }
            if let voiceOn = event.voiceOn {
                let phone = PhoneVoice(voiceOn)
                phoneHolds = phone
                diary.note(phone.map { "\($0.name) took the voice from this Mac" } ?? "\(voiceOn.name) gave the voice back to this Mac")
                face.voiceOn(phone)
                return
            }
            if isQuiet(event) {
                diary.note("\(event.subject) told while \(phoneHolding(event)) speaks, left unsaid on this Mac")
                return
            }
            interrupted = false
            // Kept, so a tap on the island or an answer elsewhere stops it being read out after the fact.
            if event.noticeKind == .question { asking = event.subject }
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
                if !isQuiet(event) { chimes?.play(.settled) }
                face.show(.idle, caption: "answered elsewhere")
            }
        case .none:
            break
        }
    }

    /// A teammate's call the workspace routed here, said like one of this Mac's: chimed, captioned with its one label
    /// and asked aloud. Every ask names it to the brain, so a spoken answer comes back as a proposal this Mac carries
    /// out with the workspace; a button on the island answers it too, and either way no daemon answers it.
    public func announceTeam(_ call: WorkspaceHeldCall) async {
        guard workspace?.owns(call.id) ?? false else { return }
        // The phone holding the voice asks it; the island shows the card here without a sound.
        guard phoneHolds == nil else { return }
        asking = call.id
        interrupted = false
        chimes?.play(.held)
        face.show(.thinking, caption: caption("\(call.who) needs you"))
        await say(teamQuestion(owner: owner.name, call: call))
        // Answered by hand while it was being said, so the caption does not ask about a call already gone.
        guard asking == call.id else { return }
        face.show(.listening, caption: caption("\(call.who): \(call.what)"))
    }

    /// The person spoke after this moment, or it is too old to pick up where it left off.
    private func movedOn(since at: String) -> Bool {
        guard let moment = readInstant(at) else { return true }
        if let heard = lastHeard, heard > moment { return true }
        return now().timeIntervalSince(moment) > Self.resumeWindow
    }

    /// A team's question answered by voice and carried out here, so the island takes its card down as a button would.
    public var teamAnswered: ((String, HeldOutcome) -> Void)?

    /// A team's question the person answered by voice. The workspace takes the answer first and only then is the
    /// proposal confirmed to the daemon that raised it, so it never reads as done where the workspace did not take it.
    /// A yes is one touch over both messages, a deny goes unsigned both ways, and a cancelled touch sends the workspace nothing.
    private func carryOut(_ team: TeamAnswerBrief, proposal event: DaemonEvent) async {
        guard let workspace, let call = workspace.call(team.callId), let answer = team.holdAnswer else {
            diary.note("\(event.subject) answers \(team.callId), which is not waiting here, so it is declined")
            _ = await settleProposal(event.subject, .declined, signature: nil)
            chimes?.play(.failed)
            face.show(.idle, caption: "")
            await say(WorkspaceLines.gone)
            return
        }
        // This Mac's own label for the sheet, so what the sensor is touched for never rests on the daemon's words.
        let reason = CallLabel.touchIDReason(call.who, what: call.what, answer: answer)
        var signatures: [String]?
        if answer != .deny, let phone = phoneFor(event) {
            await leaveForPhone(event, phone)
            return
        }
        if answer != .deny {
            face.show(.needsYou, caption: caption("Touch ID to \(reason)"))
            let messages = [
                confirmationMessage(subject: call.id, answer: answer.rawValue),
                confirmationMessage(subject: event.subject, answer: ProposalAnswer.confirmed.rawValue),
            ]
            guard let signed = try? await key.sign(messages, reason: reason), signed.count == messages.count else {
                _ = await settleProposal(event.subject, .declined, signature: nil)
                chimes?.play(.declined)
                face.show(.idle, caption: "")
                await say(Self.afterConfirm(.declined, outcome: nil))
                return
            }
            signatures = signed
        }
        let outcome = await answerForTeam(workspace, call.id, answer, reason: reason, signed: signatures?.first)
        guard outcome == .answered else {
            // Nothing this Mac did reached the workspace, so the proposal is declined rather than left to read as done.
            _ = await settleProposal(event.subject, .declined, signature: nil)
            if case .answeredElsewhere = outcome { teamAnswered?(call.id, outcome) }
            return
        }
        teamAnswered?(call.id, outcome)
        let response = await settleProposal(event.subject, .confirmed, signature: signatures?.last)
        // The workspace already holds the answer, so a daemon that would not take the confirmation changes nothing done.
        if response?.ok != true { diary.note("\(event.subject) was carried out but not confirmed: \(response?.error ?? "no answer")") }
        await say(WorkspaceLines.answeredByVoice)
    }

    /// Confirms or declines a proposal to the daemon that raised it, which the link finds by its subject.
    private func settleProposal(_ subject: String, _ answer: ProposalAnswer, signature: String?) async -> DaemonResponse? {
        var request = newRequest(.confirm)
        request.subject = subject
        request.answer = answer.rawValue
        request.signature = signature
        return try? await link.request(request)
    }

    /// A teammate's call settled somewhere else while it was being asked about, so the voice stops asking.
    public func teamSettled(_ subject: String, line: String?) {
        guard asking == subject else { return }
        asking = nil
        speaker.stop()
        face.show(.idle, caption: caption(line ?? SettledLine.unknown))
    }

    /// The phone an event belongs to, by name when it holds the voice, for the diary.
    private func phoneHolding(_ event: DaemonEvent) -> String {
        event.heardOn?.name ?? event.origin?.deviceId ?? "a phone"
    }

    /// One notice of a phone's turn, put together with the ones before it; the words stay out of the diary.
    private func showPhone(_ turn: PhoneTurn) {
        guard let shown = phoneConversation.take(turn, at: now()) else { return }
        if turn.said != nil { diary.note("\(shown.name) started a turn, shown on the island without a sound") }
        if !shown.isAnswering { diary.note("\(shown.name) finished its turn") }
        face.phone(shown)
    }

    /// A window or a card the person asked for, put up while the answer is still being said.
    private func show(_ event: DaemonEvent) async {
        // Icons in the notch rather than a window, so it needs no presenter and waits on nothing.
        if event.displayKind == .signIn {
            face.signIns(event.signIn ?? [])
            return
        }
        // The brain says what it drafted and the card shows the message whole, so nothing goes out unread.
        if event.displayKind == .draft {
            if let draft = event.draft { face.draft(subject: event.subject, draft) }
            return
        }
        guard let presenter else { return }
        // A phone asked or holds the voice, so its own speaker answers; the Mac does the work and shows it, and says nothing.
        let quiet = isQuiet(event)
        if quiet { diary.note("doing \(event.subject) for \(phoneHolding(event)) without a sound") }
        await witnessBefore(event)
        switch event.displayKind {
        case .open:
            // Behind any typing, since a window brought forward mid sentence takes the rest of its keys.
            await oneAtATime { [self] in
                if let session = event.sessionId {
                    await presenter.live(session: session, host: event.host)
                } else if await !presenter.open(event.host) {
                    diary.note("could not open the window for \(event.subject)")
                    if !quiet { speaker.queue("My apologies, I could not bring its window forward.") }
                }
            }
        case .focus:
            if let session = event.sessionId {
                await oneAtATime { [self] in
                    await shown(event, await presenter.focus(session: session, host: event.host))
                }
            }
        case .type:
            await oneAtATime { [self] in
                face.show(.thinking, caption: "typing it in")
                await delivered(event, await presenter.type(event.summary, into: event.host, request: event.subject),
                                otherwise: "My apologies, I could not type it into its terminal.")
            }
        case .prefill:
            await oneAtATime { [self] in
                face.show(.thinking, caption: "typing it in")
                let typed = await event.sessionId.asyncMap { await presenter.prefill(event.summary, session: $0, host: event.host) }
                await delivered(event, typed ?? Typed(.failed, "no session to type into"),
                                otherwise: typed?.outcome == .clipboard
                                    ? "My apologies, I could not type it in safely, so your words are on the clipboard. Press Command V, then Return, in its chat."
                                    : "My apologies, I could not type it into its chat.")
            }
        case .launch:
            await oneAtATime { [self] in
                face.show(.thinking, caption: "starting it")
                let started: Typed
                switch event.via {
                case Self.viaTerminalApp:
                    started = await presenter.launch(event.summary, in: event.host?.cwd, terminalApp: event.host?.appPath ?? "")
                case Self.viaPanel:
                    started = await presenter.startInPanel(event.summary, in: event.host?.cwd, editor: event.host?.appPath)
                default:
                    started = await presenter.launch(event.summary, in: event.host?.cwd,
                                                     editor: event.host?.appPath, request: event.subject)
                }
                await delivered(event, started, otherwise: "My apologies, I could not start it.")
            }
        case .app:
            let start = AppStart(
                name: event.title ?? event.agent,
                appPath: event.host?.appPath,
                folder: event.host?.cwd,
                links: event.app?.links ?? [],
                env: event.app?.env ?? [:],
                // The summary falls back to the title, so only words the runtime sent are typed.
                typed: event.summary == event.title ? nil : event.summary,
                newChat: event.via == Self.viaNewChat,
                sendPrefilled: event.via == Self.viaSendPrefilled
            )
            await oneAtATime { [self] in
                face.show(.thinking, caption: "opening \(start.name)")
                await delivered(event, await presenter.openApp(start),
                                otherwise: start.typed == nil
                                    ? "My apologies, I could not open \(start.name)."
                                    : "\(start.name) is open, and your words are on the clipboard, since I could not type them in. Press Command V, then Return, in its chat.")
            }
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
        case .interrupt:
            face.show(.thinking, caption: "stopping it")
            let stopped = await event.sessionId.asyncMap { await presenter.interrupt(session: $0, host: event.host, request: event.subject) }
            await delivered(event, stopped ?? Typed(.failed, "no session to stop"),
                            otherwise: "My apologies, I could not stop it.")
        case .press:
            // Only what parses as keys is pressed, so the words of the request can never be typed as text.
            let keys = TerminalPress.parse(event.summary)
            // Behind any typing, since keys landing mid sentence would answer with the wrong words.
            await oneAtATime { [self] in
                face.show(.thinking, caption: "answering it")
                let pressed = await keys.asyncMap { keys in
                    await event.sessionId.asyncMap { await presenter.press(keys, session: $0, host: event.host, request: event.subject) }
                } ?? nil
                await delivered(event, pressed ?? Typed(.failed, keys == nil ? "those were not keys" : "no session to answer"),
                                otherwise: "My apologies, I could not answer it in its terminal.")
            }
        case .dismiss:
            await presenter.dismissAll()
        case .look:
            await look(event)
        case .folder:
            let opener = event.title.flatMap(FolderOpener.init(rawValue:)) ?? .finder
            guard let path = event.host?.cwd, await presenter.openFolder(path, in: opener) else {
                diary.note("could not open the folder for \(event.subject)")
                if !quiet { speaker.queue("My apologies, I could not open that folder.") }
                return
            }
        case .link:
            // Only a web address is opened, whatever the event carried, so a link never starts an app.
            guard let url = event.webLink, await presenter.openLink(url) else {
                diary.note("could not open the link for \(event.subject)")
                await shown(event, Typed(.failed, "not a web page this Mac could open"))
                if !quiet { speaker.queue("My apologies, I could not open that page.") }
                return
            }
            diary.note("opened a page on \(url.host ?? "the web") for \(event.subject)")
            await shown(event, Typed(.typed))
        case .draft, .signIn:
            // Shown by the face before the presenter is needed, above.
            break
        case .card:
            await presenter.card(SummaryCard(
                title: event.title ?? "Session",
                // Read, not heard, so the markdown stays for the card to lay out.
                text: event.summary,
                files: event.files ?? [],
                excerpt: event.excerpt,
                sessionId: event.cardSession,
                host: event.host
            ))
        case .none:
            break
        }
    }

    /// The screen as the brain asked to see it: the orb glances so the person knows, and the capture goes back unread here.
    private func look(_ event: DaemonEvent) async {
        guard let presenter else { return }
        face.react(.glance)
        let app = event.title.flatMap { $0.isEmpty ? nil : $0 }
        // A session's own tab is read by its terminal first, so its question is seen without Screen Recording.
        var sight = await event.host.asyncMap { await presenter.readTab(of: $0) } ?? nil
        if sight == nil { sight = await presenter.look(app: app) }
        diary.note("looked at \(sight?.app ?? app ?? "the screen")\(sight?.image == nil ? " with no capture" : "")")
        var request = newRequest(.seen)
        request.subject = event.subject
        request.sight = sight ?? Sight(app: app ?? "the screen")
        _ = try? await link.request(request)
    }

    /// Tells the brain whether a window came forward, with no sound, since the brain is the one to say it.
    private func shown(_ event: DaemonEvent, _ typed: Typed) async {
        if !typed.wentIn { diary.note("could not bring \(event.subject) forward: \(typed.reason ?? "no reason")") }
        var request = newRequest(.delivered)
        request.subject = event.subject
        request.answer = typed.outcome.rawValue
        request.reason = typed.reason
        _ = try? await link.request(request)
    }

    /// Tells the brain waiting on it how typing went, so it says that rather than what it hoped.
    /// Only a daemon too old to listen leaves a failure for the app to say itself.
    /// The typing in progress, and the lock that hands it on, since show events arrive on tasks of their own.
    private var typing: Task<Void, Never>?
    private let typingLock = NSLock()

    /// Keys pressed for one message at a time: the person talking on while a prompt goes in sends the rest
    /// as a message of its own, and two typed at once would mix their letters in the agent's prompt.
    private func oneAtATime(_ work: @escaping () async -> Void) async {
        await queued(work).value
    }

    /// Puts the work behind whatever is typing now, under the lock, which only a synchronous call may hold.
    private func queued(_ work: @escaping () async -> Void) -> Task<Void, Never> {
        typingLock.lock()
        defer { typingLock.unlock() }
        let previous = typing
        let mine = Task {
            await previous?.value
            await work()
        }
        typing = mine
        return mine
    }

    /// The displays that act on another app, whose window is captured either side of acting as its evidence.
    private static let witnessed: Set<Display> = [.type, .prefill, .launch, .app, .close, .interrupt]

    /// Each action's window as it was just before, kept until its outcome is told.
    private var evidenceBefore: [String: Witness] = [:]

    private func witnessBefore(_ event: DaemonEvent) async {
        guard let presenter, let kind = event.displayKind, Self.witnessed.contains(kind) else { return }
        evidenceBefore[event.subject] = await presenter.evidence(of: event.host, request: event.subject, at: .before)
    }

    /// The window just after acting beside the one from before, so what is said about it has a witness.
    private func witnessAfter(_ event: DaemonEvent) async -> Witness? {
        guard let presenter, let kind = event.displayKind, Self.witnessed.contains(kind) else { return nil }
        let before = evidenceBefore.removeValue(forKey: event.subject)
        let after = await presenter.evidence(of: event.host, request: event.subject, at: .after)
        guard let before else { return after }
        return before.after(after)
    }

    private func delivered(_ event: DaemonEvent, _ typed: Typed, otherwise: String) async {
        let quiet = isQuiet(event)
        if !quiet { chimes?.play(typed.wentIn || typed.outcome == .waiting ? .done : .failed) }
        if typed.outcome != .verified { diary.note("\(event.subject) \(typed.outcome.rawValue): \(typed.reason ?? "nothing read back")") }
        if let proof = typed.proof {
            diary.note("\(event.subject) seen landing: \(proof.checked)")
            face.proof(proof)
        }
        var request = newRequest(.delivered)
        request.subject = event.subject
        request.answer = typed.outcome.rawValue
        request.reason = typed.reason
        request.proof = typed.proof
        request.evidence = await witnessAfter(event)
        // The step only the person can take is said below, so the brain is told not to say it again.
        if !quiet, let hint = typed.hint, willSay(hint) {
            request.told = true
            macTold = true
        }
        // The clipboard line is said below too, so the brain is told it was, or it says it a second time.
        if !quiet, typed.hint == nil, typed.outcome == .clipboard || typed.outcome == .notAllowed {
            request.told = true
            macTold = true
        }
        let heard = (try? await link.request(request))?.ok == true
        // The daemon tells the phone how it went, so nothing is said in an empty room.
        if quiet {
            if let hint = typed.hint { diary.note("needs the person, left unsaid for a phone: \(hint)") }
            return
        }
        let said = typed.outcome == .notAllowed ? notAllowedLine() : otherwise
        if !heard, let line = Evidence.unheard(typed.outcome, otherwise: said) { speaker.queue(line) }
        if let hint = typed.hint { tell(hint) }
        // The words on the clipboard need a hand from the person, so that one is always said.
        // Unless a hint was just said, which already told them what happened and what to do.
        if typed.hint != nil { return }
        if heard, typed.outcome == .clipboard || typed.outcome == .notAllowed { speaker.queue(said) }
    }

    /// How the runtime names where a launch goes and an app start begins, as `DISPLAY_VIA` spells them.
    static let viaTerminalApp = "terminal-app"
    static let viaPanel = "panel"
    static let viaNewChat = "new-chat"
    static let viaSendPrefilled = "send-prefilled"

    /// Said when the brain held for more on words that were already all of it.
    static let sayItAgain = "Sorry, I did not quite follow. Could you say that once more?"

    /// The steps already said this run, so an instruction is heard once rather than after every message.
    private var hintsSaid: Set<TypingHint> = []

    /// Says what the person has to do, always, whatever the brain says, since only they can do it.
    private func tell(_ hint: TypingHint) {
        diary.note("needs the person: \(hint)")
        guard willSay(hint) else { return }
        hintsSaid.insert(hint)
        speaker.queue(Self.line(for: hint, macOSMajorVersion: macOSMajorVersion, adHocBuild: adHocBuild))
    }

    /// A step for this one typing is said every time; a setup step once a run, since they heard it already.
    private func willSay(_ hint: TypingHint) -> Bool {
        hint.isAboutThisTyping || !hintsSaid.contains(hint)
    }

    /// The steps for one hint, named the way the person sees them on screen.
    static func line(for hint: TypingHint, macOSMajorVersion: Int, adHocBuild: Bool = false) -> String {
        switch hint {
        case .allowTyping:
            return "That went in all at once, because I am not permitted to type yet. To watch me type it, open System Settings, Privacy and Security, \(typingPane(macOSMajorVersion: macOSMajorVersion)), and switch Memnox on.\(adHocNote(adHocBuild))"
        case .restartExtensions(let app):
            return "\(app) is still running the older Memnox extension. In \(app), press Command Shift P, run Developer: Restart Extension Host, then ask me again."
        case .installExtension(let app):
            return "The Memnox extension is not in \(app) yet. In a terminal, run memnox daemon with the install flag, so the daemon starts again and puts it in, then ask me again."
        case .pasteIn(let app):
            return "\(app) has more than one window or tab open, so I could not tell which one is the session's. Your words are on the clipboard: in its tab, press Command V, then Return."
        case .clickMessageBox(let app):
            return "I could not find Claude's message box in \(app). Click into it once, then ask me again, and I will remember it from then on. Your words are on the clipboard meanwhile."
        }
    }

    /// Proposals already taken up, so one that arrives again is never put to Touch ID a second time.
    private var takenUp: Set<String> = []

    /// Whether they have heard how to let Memnox type, so the second time is one short line rather than the whole of it.
    private var toldHowToAllow = false

    /// What to do about it in full the first time, since nothing they say can fix it, and after that only where the words are.
    private func notAllowedLine() -> String {
        defer { toldHowToAllow = true }
        return toldHowToAllow
            ? "Your words are on the clipboard again."
            : "I am not permitted to type yet. I have opened \(Self.typingPane(macOSMajorVersion: macOSMajorVersion)) for you with a fresh entry for Memnox: switch it on once, and I can type from then on.\(Self.adHocNote(adHocBuild)) Your words are on the clipboard meanwhile."
    }

    /// Said only of a build signed ad hoc, since that is the one case where a grant that shows on does nothing.
    static func adHocNote(_ adHocBuild: Bool) -> String {
        adHocBuild ? " This build of Memnox is signed ad hoc, so macOS forgets that grant each time it is rebuilt." : ""
    }

    /// Where macOS lists the apps that may press keys: renamed in macOS 27, and a grant left from an
    /// earlier build shows as on there while doing nothing, which only switching it off and on clears.
    public static func typingPane(macOSMajorVersion: Int) -> String {
        macOSMajorVersion >= typingPaneRenamedIn ? "Device Control and Data Access" : "Accessibility"
    }
    /// The first macOS release that calls the typing pane Device Control and Data Access.
    static let typingPaneRenamedIn = 27

    /// A proposal to let something happen: Touch ID signs exactly this one, or it is declined.
    /// A yes to a call that stays in its repository goes as it is, since the daemon asks no fingerprint for it.
    private func confirm(_ event: DaemonEvent) async {
        let answerKind: ProposalAnswer
        var signature: String?
        let needsTouchID = event.needsTouchID || signsEveryYes(event.subject)
        // A paired phone answers it, or one took over since it was queued, so it goes to Face ID there rather than Touch ID here.
        if needsTouchID, let phone = phoneFor(event) {
            await leaveForPhone(event, phone)
            return
        }
        if needsTouchID, await registerKey() == .anotherKey {
            chimes?.play(.failed)
            await say(Self.anotherKeyLine)
            return
        }
        if needsTouchID {
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
        } else {
            answerKind = .confirmed
        }
        var request = newRequest(.confirm)
        request.subject = event.subject
        request.answer = answerKind.rawValue
        request.signature = signature
        let response = try? await link.request(request)
        if await answeredFirst(response, chose: answerKind.rawValue) != nil { return }
        if response?.ok == true {
            marked(allowed: answerKind == .confirmed)
            await say(Self.afterConfirm(answerKind, outcome: response?.outcome))
        } else {
            chimes?.play(.failed)
            await say("My apologies, that was not confirmed: \(response?.error ?? "Memnox did not answer").")
        }
    }

    /// A yes left to the phone's Face ID: said and shown here unless that phone speaks, so the person knows where to look.
    private func leaveForPhone(_ event: DaemonEvent, _ phone: String) async {
        diary.note("\(event.subject) left for \(phone) to answer with Face ID")
        guard !isQuiet(event) else { return }
        let line = Self.answerOnPhone(phone)
        face.show(.idle, caption: caption(line))
        await say(line)
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

    /// A command still running on its own, or a held call only let through, is never called done.
    static func afterConfirm(_ answer: ProposalAnswer, outcome: String?) -> String {
        Evidence.afterConfirm(answer, outcome: outcome)
    }

    /// A held call answered with a button: a deny goes as it is, and an allow only with Touch ID over exactly
    /// this call, unless the daemon placed it inside its repository, where a tap is the answer.
    public func answerHeld(_ subject: String, _ answer: HoldAnswer, reason: String, touchID: Bool = true) async -> HeldOutcome {
        // A teammate's call has no rule on this Mac to relax, so from now on is a yes to this call there.
        if let workspace, workspace.owns(subject) {
            return await answerForTeam(workspace, subject, answer == .always ? .once : answer, reason: reason)
        }
        var request = newRequest(.confirm)
        request.subject = subject
        request.answer = answer.rawValue
        if answer != .deny, touchID || signsEveryYes(subject) {
            switch await signature(subject, answer: answer.rawValue, reason: reason) {
            case .signed(let signature): request.signature = signature
            case .refused(let outcome): return outcome
            }
        }
        let response = try? await link.request(request)
        // Answered by hand or elsewhere, so the voice stops asking rather than waiting on a reply that already came.
        if response?.ok == true || EarlierAnswer(response) != nil, asking == subject {
            asking = nil
            speaker.stop()
        }
        if let first = await answeredFirst(response, chose: answer.rawValue) { return .answeredElsewhere(first) }
        guard response?.ok == true else { return await notThrough(response) }
        marked(allowed: answer != .deny)
        face.show(.idle, caption: "")
        return .answered
    }

    /// A pick in an agent's own picker, tapped on the island. It is the person's own choice going to their own agent,
    /// which is ruled on as ever when it acts, so it goes with no Touch ID and no signature.
    public func answerQuestion(_ subject: String, number: Int, answer: String) async -> HeldOutcome {
        var request = newRequest(.confirm)
        request.subject = subject
        request.answer = answer
        request.questionNumber = number
        let response = try? await link.request(request)
        guard response?.ok == true else { return await notThrough(response) }
        // Picked by hand, so the voice stops reading out a question that already has its answer.
        if asking == subject {
            asking = nil
            speaker.stop()
        }
        face.show(.idle, caption: "")
        return .answered
    }

    /// A teammate's call answered through the workspace: Touch ID for every yes, since it always reaches another
    /// machine, and nothing for a deny; the daemon on this Mac never hears of it.
    private func answerForTeam(_ workspace: WorkspaceAnswering, _ subject: String, _ answer: HoldAnswer, reason: String,
                               signed: String? = nil) async -> HeldOutcome {
        // Answered by hand, so the question being said about it stops rather than asking after the answer.
        if asking == subject {
            asking = nil
            speaker.stop()
        }
        if answer != .deny, signed == nil, let phone = phoneAnswers { return .failed(Self.answerOnPhone(phone)) }
        if answer != .deny, signed == nil { face.show(.needsYou, caption: caption("Touch ID to \(reason)")) }
        let outcome = await workspace.answer(subject, answer, reason: reason, signed: signed)
        switch outcome {
        case .answered:
            marked(allowed: answer != .deny)
            face.show(.idle, caption: "")
        case .answeredElsewhere(let first):
            chimes?.play(.settled)
            await say(first.line)
            face.show(.idle, caption: "answered elsewhere")
        case .cancelled:
            face.show(.idle, caption: "")
        case .failed(let why):
            chimes?.play(.failed)
            face.show(.idle, caption: "")
            await say("That did not go through: \(why)")
        }
        return outcome
    }

    /// A rule answered from its card: the place picked is the answer Touch ID signs, so nobody else
    /// chooses where it holds; nil leaves the rule out, unsigned, since saying no can do no harm.
    public func answerRule(_ subject: String, scope: RuleScope?, reason: String) async -> HeldOutcome {
        var request = newRequest(.confirm)
        request.subject = subject
        request.answer = scope?.id ?? ProposalAnswer.declined.rawValue
        if let scope {
            switch await signature(subject, answer: scope.id, reason: reason) {
            case .signed(let signature): request.signature = signature
            case .refused(let outcome): return outcome
            }
        }
        let response = try? await link.request(request)
        let chose: ProposalAnswer = scope == nil ? .declined : .confirmed
        if let first = await answeredFirst(response, chose: chose.rawValue) { return .answeredElsewhere(first) }
        guard response?.ok == true else { return await notThrough(response) }
        marked(allowed: scope != nil)
        await say(Self.afterRule(scope))
        return .answered
    }

    /// Where it holds now, said once it is written, so the person hears the reach they signed for.
    static func afterRule(_ scope: RuleScope?) -> String {
        guard let scope else { return "Very well. I have left that rule out." }
        switch scope.scopeKind {
        case .machine: return "Very well. That rule is in force on this Mac."
        case .repository: return "Very well. That rule is in force in \(scope.label)."
        case .team: return "Very well. I have offered that rule to the team. It holds everywhere once a second admin approves it."
        case nil: return "Very well. That rule is in force."
        }
    }

    /// A drafted message answered from its card: Send goes only with Touch ID over exactly this draft, and closing it goes unsigned.
    public func answerDraft(
        _ subject: String, send: Bool, reason: String, edited: String? = nil, editedTo: String? = nil
    ) async -> HeldOutcome {
        var request = newRequest(.confirm)
        request.subject = subject
        let answer: ProposalAnswer = send ? .confirmed : .declined
        request.answer = answer.rawValue
        if send {
            // Only a Send carries rewritten words, since closing a draft sends nothing at all.
            request.edited = edited
            request.editedTo = editedTo
            switch await signature(subject, answer: answer.rawValue, edited: edited, editedTo: editedTo, reason: reason) {
            case .signed(let signature): request.signature = signature
            case .refused(let outcome): return outcome
            }
        }
        let response = try? await link.request(request)
        if let first = await answeredFirst(response, chose: answer.rawValue) { return .answeredElsewhere(first) }
        guard response?.ok == true else {
            diary.note("the draft \(subject) did not go out: \(response?.error ?? "no answer")")
            return await notThrough(response)
        }
        diary.note("the draft \(subject) \(send ? "went out" : "was closed"): \(response?.outcome ?? "")")
        marked(allowed: send)
        face.show(.idle, caption: "")
        // Said, since a chime alone left the person asking whether it ever went.
        if send { await say(Self.sentLine) }
        return .answered
    }

    /// Said once a draft went out, so a send is never left to be guessed at.
    static let sentLine = "Sent."

    /// What the person changed in a message the app typed before they sent it: each word they swapped
    /// for one that sounds alike is sent to be learned, so it is heard right the next time they say it.
    public func learn(typed: String, sent: String) async {
        let corrections = correctedWords(typed: typed, sent: sent)
        guard !corrections.isEmpty else { return }
        var request = newRequest(.learnWords)
        request.learned = corrections.map { LearnedWord(heard: $0.heard, meant: $0.meant) }
        let kept = (try? await link.request(request))?.words ?? []
        diary.note("learned from an edit: \(corrections.map { "\($0.heard) is \($0.meant)" }.joined(separator: ", ")); kept \(kept.count)")
    }

    /// A fingerprint over exactly this answer, or why there is none to send.
    private enum Signing {
        case signed(String)
        case refused(HeldOutcome)
    }

    /// Touch ID over this answer, asked only once the daemon trusts this Mac's key: a signature from any
    /// other key is refused after the fingerprint, which reads as the button doing nothing.
    private func signature(
        _ subject: String, answer: String, edited: String? = nil, editedTo: String? = nil, reason: String
    ) async -> Signing {
        // A press is a hand at this Mac, so only a phone holding the voice or driving takes it from Touch ID; a paired one still gets it.
        if let phone = phoneAnswers {
            face.show(.idle, caption: "")
            return .refused(.failed(Self.answerOnPhone(phone)))
        }
        if await registerKey() == .anotherKey {
            chimes?.play(.failed)
            face.show(.idle, caption: "")
            await say(Self.anotherKeyLine)
            return .refused(.failed(Self.anotherKeyLine))
        }
        face.show(.needsYou, caption: caption("Touch ID to \(reason)"))
        guard let signature = try? await key.sign(confirmationMessage(subject: subject, answer: answer, edited: edited, editedTo: editedTo), reason: reason) else {
            face.show(.idle, caption: "")
            return .refused(.cancelled)
        }
        return .signed(signature)
    }

    /// The answer that came first, when another route got there before this one: it stands, so the
    /// person hears it only when it differs from what they chose, and never the outcome of their own press.
    private func answeredFirst(_ response: DaemonResponse?, chose: String) async -> EarlierAnswer? {
        guard let first = EarlierAnswer(response) else { return nil }
        diary.note("answered elsewhere first: \(first.word ?? "unknown"), this one was \(chose)")
        chimes?.play(.settled)
        if !first.matches(chose) { await say(first.line) }
        face.show(.idle, caption: "answered elsewhere")
        return first
    }

    /// An answer that went through, heard as a chime and seen as the orb ringing out or pulling in.
    private func marked(allowed: Bool) {
        chimes?.play(allowed ? .allowed : .declined)
        face.react(allowed ? .allowed : .refused)
    }

    /// An answer the daemon would not take, said with its reason, since a shake alone tells nobody what to do.
    private func notThrough(_ response: DaemonResponse?) async -> HeldOutcome {
        let why = response?.error ?? "Memnox did not answer"
        chimes?.play(.failed)
        face.show(.idle, caption: "")
        await say("That did not go through: \(why).")
        return .failed(why)
    }

    /// Said when the daemon trusts another key, so nothing this Mac signs can be confirmed until it is cleared.
    static let anotherKeyLine = "Memnox trusts another key for confirmations, so your fingerprint cannot confirm anything yet. Run memnox voice forget-key in a terminal, then open me again."

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
    }

    /// What this reply has said so far, so a sentence told twice around a tool is said once.
    private var saidThisReply: [String] = []

    /// A sentence of a streamed reply, queued so the reply is spoken as one run rather than line by line.
    private func flow(_ sentence: String) {
        if firstSentenceAt == nil { firstSentenceAt = now() }
        answering = true
        let spoken = speakable(sentence)
        guard !spoken.isEmpty else { return }
        if repeats(spoken, saidAlready: saidThisReply) {
            diary.note("left out a repeat: \(spoken)")
            return
        }
        saidThisReply.append(spoken)
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
        ids.next()
    }
}

extension Optional {
    /// The value mapped through async work, or nil without doing it.
    func asyncMap<T>(_ transform: (Wrapped) async -> T) async -> T? {
        guard let value = self else { return nil }
        return await transform(value)
    }
}
