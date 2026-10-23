import Foundation

// The daemon's line protocol, mirrored field for field from memnox-runtime's
// packages/core/src/daemon/protocol.ts and its session-view.ts, since the two sides only ever meet as JSON.

public enum DaemonMethod: String, Sendable {
    case ping
    case ask
    case subscribe
    case waiting
    case confirm
    case registerKey = "register-key"
    case cancel
    case locate
    case brief
    case warm
    case vocabulary
    case sessionView = "session-view"
    case sessionsList = "sessions-list"
    /// Whether an instruction the app was asked to type landed, so the brain never says it did when it did not.
    case delivered
    /// The app's own timings for the question just answered, so one trace shows the whole answer.
    case trace
    /// Which of the person's agents can be the voice, and why the others cannot.
    case voiceAgents = "voice-agents"
    /// The person picking which agent the voice thinks with.
    case chooseVoiceAgent = "choose-voice-agent"
    /// Words the person fixed in what the app typed for them, kept so they are heard right next time.
    case learnWords = "learn-words"
    /// What was on screen when the brain asked to look, answering a look display.
    case seen
    /// Opens a pairing for a phone and answers the QR it shows; refused while this Mac is not on Memnox Cloud.
    case pairBegin = "pair-begin"
    /// Streams where a pairing stands until it is paired, declined or expired.
    case pairPending = "pair-pending"
    /// The person's yes to a phone, signed with Touch ID over pairingMessage.
    case pairAccept = "pair-accept"
    /// The person's no to a phone, unsigned since saying no can do no harm.
    case pairDecline = "pair-decline"
    /// Every device paired with this Mac, revoked ones included.
    case devicesList = "devices-list"
    /// Takes a device's access away, unsigned since it only ever narrows what reaches this Mac.
    case deviceRevoke = "device-revoke"
    /// Gives a device one more capability, signed with Touch ID over grantMessage.
    case deviceGrant = "device-grant"
    /// Takes one capability back, unsigned since it only narrows what a device can do; taking mac ends a live drive.
    case deviceUngrant = "device-ungrant"
    /// The Kokoro voice the person picked, so the daemon can hand it to a paired phone.
    case voiceChoice = "voice-choice"
    /// A phone asking to drive this Mac until a time, or to stop; only ever sent from afar, named here so the wire is whole.
    case drive
    /// A phone whose app left the screen handing the voice back to this Mac; only ever sent from afar, named here so the wire is whole.
    case voiceRelease = "voice-release"
    /// One folder under the person's home as names and sizes, so a phone browses this Mac without the brain or the screen.
    case filesList = "files-list"
    /// One line rendered by this Mac's Kokoro and streamed back as PCM, so a phone in the background still speaks in the person's voice.
    case speak
    /// The five blocks the home opens on, read once so the window draws them without asking five questions.
    case home
    /// Turns the home's ready suggestion into a rule proposal, which the person confirms with Touch ID like any other.
    case handOver = "hand-over"
    /// Whether a person is signed in on the daemon's side, which is what the voice and the terminal act through.
    case person
    /// Starts the daemon's own sign in as the person, answering the code to approve; the daemon polls on its own.
    case personSignIn = "person-sign-in"
    /// Signs the daemon's person out.
    case personSignOut = "person-sign-out"
    /// Whether this machine is connected to a workspace, which is what carries rules, memory and phones to it.
    case machine
    /// Connects this machine to a workspace, the device flow memnox login runs, answering the code; the daemon polls on its own.
    case machineSignIn = "machine-sign-in"
    /// Disconnects this machine, which forgets its credential; rules already pulled stay in force.
    case machineSignOut = "machine-sign-out"
    /// Dictation written the way the person would have typed it, by their own Claude Code kept warm for it.
    case polish
    /// Starts that Claude Code as the dictation key goes down, so the answer skips its cold start.
    case polishWarm = "polish-warm"
    /// The person's own words typed into one session, signed over followUpMessage; the brain never reads them.
    case followUp = "follow-up"
    /// The person's own app accounts connected through Memnox Cloud, such as their mail and their chat, each with
    /// whether it works now; refused while this Mac has no person signed in.
    case connectionsList = "connections-list"
    /// Connects one tool as the person, any toolkit and any role: answers its sign in page, which the daemon opens
    /// in the Mac's browser only when asked over the local socket.
    case connectionsSignIn = "connections-sign-in"
    /// Undoes every sign in the person made to one tool, answering the connections as they then stand.
    case connectionsSignOut = "connections-sign-out"
    /// Up to thirty tools from Memnox Cloud's catalogue that match the words, for a picker of what to connect.
    case toolkitsSearch = "toolkits-search"
    /// One spoken sentence drafted into a rule and read back; with nothing left open it is proposed for Touch ID.
    case rule
}

public enum EventKind: String, Sendable {
    case held
    case proposal
    case paused
    case settled
    /// The person asked to see a session: its window brought forward, or its summary on a card.
    case show
    /// Worth saying unasked: a session finished, committed or pushed.
    case notice
}

/// How a show event wants to be shown.
public enum Display: String, Sendable {
    case open
    case card
    /// Type the person's confirmed instruction into the terminal tab the agent waits in.
    case type
    /// Open the session in its editor with the instruction in its input, for the person to send.
    case prefill
    /// Turn through the sessions to this one and bring its own terminal tab or editor forward.
    case focus
    /// Open a new terminal tab in a repository and type the line that starts an agent there.
    case launch
    /// Open an agent's own desktop app on a repository, with the task handed to it through its links.
    case app
    /// A card that pages through a session's changed files while the voice walks through them.
    case walk
    /// The whole screen: every agent on this Mac, from a live scan, with what each reaches.
    case agents
    /// A trace drawn as a waterfall: what ran, inside what, for how long, and what failed.
    case trace
    /// Every session lately as a card of its own, together, read at a glance.
    case sessions
    /// Close the live window on the session and its own terminal tab, which ends the agent there.
    case close
    /// Escape pressed in the terminal the session runs in, which stops its turn and keeps the tab.
    case interrupt
    /// Every Memnox card and window off the screen, with every agent and its tab left alone.
    case dismiss
    /// A message from the person's connected mail, drafted for them to read; Send is a signed confirm of the subject.
    case draft
    /// A folder the person named, opened where the title says.
    case folder
    /// Look at the screen: the window in front, or the app the title names, answered with seen.
    case look
    /// Keys pressed in the session's own terminal, named in the summary, to answer what its agent asks there.
    case press
    /// The icons of tools the person asked for and has not signed in to; each opens that tool's own sign in.
    case signIn = "signin"
    /// A web page the person asked to open, its one address in the app links, opened in their browser.
    case link
}

/// Where a folder opens, as the runtime's FOLDER_OPENER names it in a folder display's title.
public enum FolderOpener: String, Sendable {
    case finder
    case editor
    case terminal
}

/// How a person asked: holding Control and Option says what follows is a rule they want in force.
public enum AskIntent: String, Sendable {
    case rule
    /// What they asked before a sign in, asked again by the app once it finished, never something said just now.
    case resume
}

/// Where a rule can be put in force: every agent on this Mac, or only inside one repository.
public enum RuleScopeKind: String, CaseIterable, Sendable {
    case machine
    case repository
    /// Offered to the workspace: a second admin approves it, then every agent it runs follows it, the ones in the cloud too.
    case team
}

/// One place a proposed rule can go; its id is the answer Touch ID signs, so the choice is the person's alone.
public struct RuleScope: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: String
    /// "This Mac", or the repository's folder name.
    public let label: String
    public let folder: String?
    public let suggested: Bool?

    public init(id: String, kind: String, label: String, folder: String? = nil, suggested: Bool? = nil) {
        self.id = id
        self.kind = kind
        self.label = label
        self.folder = folder
        self.suggested = suggested
    }

    public var scopeKind: RuleScopeKind? { RuleScopeKind(rawValue: kind) }
}

/// A proposed rule as the card shows it before it is confirmed: what it does, and where it could hold.
public struct RuleDraft: Decodable, Equatable, Sendable {
    public let summary: String
    public let effect: String
    public let action: String
    public let branches: [String]?
    public let targets: [String]?
    public let reason: String
    public let scopes: [RuleScope]

    public init(summary: String, effect: String, action: String, branches: [String]? = nil, targets: [String]? = nil,
                reason: String, scopes: [RuleScope]) {
        self.summary = summary
        self.effect = effect
        self.action = action
        self.branches = branches
        self.targets = targets
        self.reason = reason
        self.scopes = scopes
    }

    public var ruleEffect: RuleEffect? { RuleEffect(rawValue: effect) }
    /// The place picked until the person picks another: the suggested one, or the first offered.
    public var suggestedScope: RuleScope? { scopes.first { $0.suggested == true } ?? scopes.first }
}

/// What a rule decides, the three effects the runtime's engine knows.
public enum RuleEffect: String, CaseIterable, Sendable {
    case allow
    case ask
    case deny
}

/// Whether a drafted message starts a thread or answers one.
public enum DraftMode: String, CaseIterable, Sendable {
    case compose
    case reply
}

/// The mail service a draft goes out through, which picks the mark on its card.
public enum MailService: String, CaseIterable, Sendable {
    case gmail
}

/// A message the person's connected mail account would send, shown whole before anything is sent.
public struct MailDraft: Decodable, Equatable, Sendable {
    public let service: String
    public let mode: String
    public let to: [String]
    public let cc: [String]?
    public let subject: String?
    public let body: String
    /// On a reply, how many messages the thread already holds.
    public let thread: Int?

    public init(service: String, mode: String, to: [String], cc: [String]? = nil, subject: String? = nil, body: String, thread: Int? = nil) {
        self.service = service
        self.mode = mode
        self.to = to
        self.cc = cc
        self.subject = subject
        self.body = body
        self.thread = thread
    }

    public var draftMode: DraftMode? { DraftMode(rawValue: mode) }
    public var mailService: MailService? { MailService(rawValue: service) }
}

/// A session as one card in the switcher: who, on what, in what state, and where it runs.
public struct SessionCard: Decodable, Equatable, Identifiable, Sendable {
    public let sessionId: String
    /// Which agent it is, such as claude-code; absent from a daemon older than the field.
    public let agent: String?
    public let agentName: String
    public let task: String?
    /// What the session is about now, as its agent titles it; absent from a daemon older than the field.
    public let focus: String?
    public let state: String
    public let thinking: Bool
    public let repository: String?
    public let runningIn: String?
    public let lastActive: String?
    public let host: DisplayHost?

    public var id: String { sessionId }
    /// The state as a known case, or nil for one this app does not know yet.
    public var sessionState: SessionState? { SessionState(rawValue: state) }

    public init(sessionId: String, agent: String? = nil, agentName: String, task: String? = nil, focus: String? = nil,
                state: String, thinking: Bool = false, repository: String? = nil, runningIn: String? = nil,
                lastActive: String? = nil, host: DisplayHost? = nil) {
        self.sessionId = sessionId
        self.agent = agent
        self.agentName = agentName
        self.task = task
        self.focus = focus
        self.state = state
        self.thinking = thinking
        self.repository = repository
        self.runningIn = runningIn
        self.lastActive = lastActive
        self.host = host
    }
}

/// Where a session is, as the runtime's SESSION_STATE in the sessions tool names it.
/// The wire keeps the raw string, so a state a newer daemon adds reads as nil rather than failing the event.
public enum SessionState: String, CaseIterable, Sendable {
    /// Something was recorded in the last few minutes.
    case working
    /// Its process is alive and nothing happened lately, so it waits on the person.
    case open
    case idle
    case quiet
    /// Its process is gone, so it is over whatever the ledger says.
    case ended
    case paused
}

/// What a notice reports, as the runtime's NOTICE_KIND in session/notices.ts names it.
/// The wire keeps the raw string, so a kind a newer daemon adds reads as nil rather than failing the event.
public enum NoticeKind: String, CaseIterable, Sendable {
    /// A long turn ended and the agent handed back to the person.
    case finished
    case committed
    case pushed
    /// Something the person asked to be told about happened.
    case watched
    /// Only watching, a rule would have asked about or refused something that went through.
    case wouldHave = "would-have"
    /// An agent asked its person something in its own picker.
    case question
    /// A command the voice started ran on its own and worked.
    case ended
    /// Two agents on one piece of work, here or across machines.
    case collision
    /// A teammate speaking to the person through the workspace, from their own computer.
    case message
    /// The person's agent and a teammate's found on one feature and introduced, which is shown and needs nobody.
    case together
    /// A session began.
    case started
    /// A session ended, closed by the person or with nothing in progress.
    case closed
    /// A session's process went away in the middle of a turn, so that turn never finished.
    case gone
    /// The person finished signing in to one of their tools, so what they asked can carry on.
    case signedIn = "signed-in"
    /// A sign in the person opened never finished, which a company's approval screen usually explains.
    case signInStalled = "sign-in-stalled"
    /// An agent stopped in its own terminal to ask its person something, answered by keys pressed there.
    case asking
}

/// How a finished turn left its tests, as the runtime's TURN_TESTS in session/turn-tests.ts names it.
/// The wire keeps the raw string, so a verdict a newer daemon adds reads as nil rather than failing the event.
public enum TurnTests: String, CaseIterable, Sendable {
    /// The last run inside the turn passed and nothing was written after it.
    case passed
    case failed
    /// The last run passed, but a file was written after it.
    case stale
    /// The agent ran no tests in the turn; not called none, which an optional would read as absent.
    case untested = "none"
}

/// Where the runtime caught a step, as its EVENT_SURFACE in event/event.ts names it.
public enum StepSurface: String, CaseIterable, Sendable {
    case mcp
    case shell
    case git
    case filesystem
    case network
    /// A question somebody asked, recorded so why can answer about it later.
    case question
    /// A change to an agent's configuration, which is not agent work.
    case config
}

/// One thing a session did, as the live window lists it.
public struct SessionViewStep: Decodable, Equatable, Sendable {
    public let at: String
    public let surface: String
    public let text: String
    public let failed: Bool?
    public let refused: Bool?

    /// The surface as a known case, or nil for one this app does not know yet.
    public var stepSurface: StepSurface? { StepSurface(rawValue: surface) }
}

/// A session as it is right now: what it is on, what it just did, and what it changed.
public struct SessionView: Decodable, Equatable, Sendable {
    public let sessionId: String
    public let agent: String
    public let agentName: String
    /// What it was opened for: the task it was given, or the person's first request in it.
    public let task: String?
    /// The person's latest request in it, when it differs from the task.
    public let lastAsk: String?
    public let state: String
    public let thinking: Bool
    public let repository: String?
    /// The branch its repository has checked out.
    public let branch: String?
    public let runningIn: String?
    /// Where in that app, in words: a Terminal tab, an editor's terminal, or an agent's panel in it.
    public let `where`: String?
    public let startedAt: String?
    public let lastActive: String?
    public let waitingOnYou: Int
    public let paused: String?
    public let helpers: [String]
    public let steps: [SessionViewStep]
    public let files: [CardFile]
    /// The changed lines of the file it changed most, so the code it is writing can be shown.
    public let excerpt: CardExcerpt?
    /// The conversation's latest lines, where the agent keeps a transcript Memnox can read.
    public let conversation: [ConversationLine]?
    /// What the agent said to end its latest turn, cut short, which is where the work stands.
    public let lastSaid: String?

    /// The state as a known case, or nil for one this app does not know yet.
    public var sessionState: SessionState? { SessionState(rawValue: state) }
}

/// A line of a session's conversation: what the person asked, what the agent said, or a tool it ran.
public struct ConversationLine: Decodable, Equatable, Sendable {
    public let at: String
    /// person, agent or tool.
    public let who: String
    public let text: String
}

/// A file on a summary card, with its lines added and removed; a binary file has no counts.
public struct CardFile: Decodable, Equatable, Sendable {
    public let path: String
    public let added: Int?
    public let removed: Int?

    public init(path: String, added: Int? = nil, removed: Int? = nil) {
        self.path = path
        self.added = added
        self.removed = removed
    }
}

/// What a folder entry is, as files-list names it.
public enum EntryKind: String, CaseIterable, Sendable {
    case folder
    case file
}

/// One entry of a folder as files-list answers it: its name and what it is, never what is in it.
public struct FileEntry: Codable, Equatable, Sendable {
    public let name: String
    public let kind: String
    /// A file's size in bytes; absent on a folder.
    public let bytes: Int?
    /// When it last changed, ISO 8601.
    public let modified: String?

    public init(name: String, kind: String, bytes: Int? = nil, modified: String? = nil) {
        self.name = name
        self.kind = kind
        self.bytes = bytes
        self.modified = modified
    }

    public var entryKind: EntryKind? { EntryKind(rawValue: kind) }
}

/// A few changed lines of one file, so the card shows the code and not only its name.
public struct CardExcerpt: Decodable, Equatable, Sendable {
    public let path: String
    public let lines: [String]

    public init(path: String, lines: [String]) {
        self.path = path
        self.lines = lines
    }
}

/// One file of a walk through: what the voice says about it and the lines it is about.
public struct WalkPage: Decodable, Equatable, Sendable {
    public let path: String
    public let note: String
    public let added: Int?
    public let removed: Int?
    public let lines: [String]

    public init(path: String, note: String, added: Int? = nil, removed: Int? = nil, lines: [String] = []) {
        self.path = path
        self.note = note
        self.added = added
        self.removed = removed
        self.lines = lines
    }
}

/// A step the app timed, sent to hang on the trace of the question it belongs to.
public struct MacSpan: Encodable, Equatable, Sendable {
    public let name: String
    public let startAt: String
    public let endAt: String
    public let attributes: [String: Double]?

    public init(name: String, startAt: String, endAt: String, attributes: [String: Double]? = nil) {
        self.name = name
        self.startAt = startAt
        self.endAt = endAt
        self.attributes = attributes
    }
}

/// A trace as a waterfall: every step's place on the clock, how deep it sits, and how it ended.
public struct TraceData: Decodable, Equatable, Sendable {
    public struct Row: Decodable, Equatable, Sendable {
        public let name: String
        public let depth: Int
        public let offsetMs: Double
        public let durationMs: Double
        public let status: String

        public init(name: String, depth: Int, offsetMs: Double, durationMs: Double, status: String) {
            self.name = name
            self.depth = depth
            self.offsetMs = offsetMs
            self.durationMs = durationMs
            self.status = status
        }
    }

    public let totalMs: Double
    public let rows: [Row]

    public init(totalMs: Double, rows: [Row]) {
        self.totalMs = totalMs
        self.rows = rows
    }
}

/// One agent on the scan screen: who it is and counted facts about what it reaches.
public struct AgentNode: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    /// The product, which picks its logo: claude-code, cursor, codex-cli, hermes.
    public let kind: String
    public let name: String
    public let servers: Int
    public let reaches: [String]
    public let working: Int
    public let open: Int
    /// Each MCP server by name, with what the last scan heard it hold; absent from an older daemon.
    public let mcp: [AgentServer]?
    /// Command line tools signed in on this Mac that its shell can run.
    public let clis: [String]?
    /// This agent's share of the Mac's real capabilities, so the shares add up to the machine; absent from an older daemon.
    public let capabilities: CapabilityShare?

    public init(id: String, kind: String, name: String, servers: Int = 0, reaches: [String] = [], working: Int = 0, open: Int = 0,
                mcp: [AgentServer]? = nil, clis: [String]? = nil, capabilities: CapabilityShare? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.servers = servers
        self.reaches = reaches
        self.working = working
        self.open = open
        self.mcp = mcp
        self.clis = clis
        self.capabilities = capabilities
    }
}

/// What one agent is credited with of the things that change something outside the Mac; no total means still counting.
public struct CapabilityShare: Decodable, Equatable, Sendable {
    public let total: Int?

    public init(total: Int? = nil) {
        self.total = total
    }
}

/// One MCP server on the scan screen; the counts are absent where no scan has asked it.
public struct AgentServer: Decodable, Equatable, Sendable {
    public let name: String
    public let tools: Int?
    public let changing: Int?

    public init(name: String, tools: Int? = nil, changing: Int? = nil) {
        self.name = name
        self.tools = tools
        self.changing = changing
    }
}

/// Where a session runs, as its hook saw it: the app, its terminal tab and its folder.
public struct DisplayHost: Decodable, Equatable, Sendable {
    public let app: String?
    public let appPath: String?
    public let tty: String?
    public let cwd: String?
    /// The agent's own id for the conversation, which an editor's agent panel opens by.
    public let conversation: String?
    /// Lines only this session's tab shows, so its tab is found by what is in it where the app cannot say.
    public let marks: [String]?

    public init(app: String? = nil, appPath: String? = nil, tty: String? = nil, cwd: String? = nil, conversation: String? = nil, marks: [String]? = nil) {
        self.app = app
        self.appPath = appPath
        self.tty = tty
        self.cwd = cwd
        self.conversation = conversation
        self.marks = marks
    }
}

public enum ChunkKind: String, Sendable {
    case text
    case tool
    case done
    case limited
    case failed
    case cancelled
}

public enum Briefing: String, Sendable {
    case held
    case paused
    case back
    case notice
}

/// How typing an instruction ended, mirrored from the runtime's DELIVERY.
public enum Delivery: String, Sendable {
    /// Typed and sent, though nothing read it back, so it is not known to have landed.
    case typed
    /// Typed and sent, and read back to see it land, which the proof says how.
    case verified
    /// Left for the session's next prompt, since reaching it now would have taken the person's window.
    case waiting
    /// It could not be typed safely, so the words were left on the clipboard.
    case clipboard
    case failed
    /// Memnox is not allowed to press keys until the person turns it on under Accessibility; the words were left on the clipboard.
    case notAllowed = "not-allowed"
}

/// What was read back after acting, so a claim that something landed carries what was seen.
public struct Proof: Codable, Equatable, Sendable {
    /// What was checked, in a few words, such as "the words in its terminal tab".
    public let checked: String
    /// The excerpt that was seen, when the check read text.
    public let seen: String?
    /// A screenshot of the target taken after acting, by its path on this Mac.
    public let image: String?

    public init(checked: String, seen: String? = nil, image: String? = nil) {
        self.checked = checked
        self.seen = seen
        self.image = image
    }

    /// The same proof with the screenshot taken after it.
    public func with(image: String?) -> Proof { Proof(checked: checked, seen: seen, image: image ?? self.image) }
}

/// One window as the Mac saw it: whose it is, a capture of it, and the labels its controls carry.
public struct Sight: Encodable, Equatable, Sendable {
    public let app: String
    public let window: String?
    /// The capture, by its path on this Mac; absent when Memnox may not record the screen.
    public let image: String?
    /// Roles, titles and values from the window's accessibility tree, one control per line.
    public let outline: String?
    /// The words in the capture, read on this Mac, so the brain reads the screen without the picture leaving it.
    public let text: String?

    public init(app: String, window: String? = nil, image: String? = nil, outline: String? = nil, text: String? = nil) {
        self.app = app
        self.window = window
        self.image = image
        self.outline = outline
        self.text = text
    }
}

/// What the screen showed around an action: the target's window just before and just after, by their
/// paths on this Mac, and the words read off the after one here, so what is said about it has a witness.
public struct Witness: Codable, Equatable, Sendable {
    public let app: String
    public let before: String?
    public let after: String?
    public let text: String?

    public init(app: String, before: String? = nil, after: String? = nil, text: String? = nil) {
        self.app = app
        self.before = before
        self.after = after
        self.text = text
    }

    /// The same window seen again after acting, keeping the before taken earlier.
    public func after(_ seen: Witness?) -> Witness {
        Witness(app: seen?.app ?? app, before: before, after: seen?.after, text: seen?.text)
    }
}

/// When a capture of an action's target is taken, which names its file beside the request it belongs to.
public enum WitnessMoment: String, Sendable {
    case before
    case after
}

/// What became of typing an instruction, and why when it did not land.
public struct Typed: Equatable, Sendable {
    public let outcome: Delivery
    public let reason: String?
    /// What was read back, which only a verified outcome may carry.
    public let proof: Proof?
    /// An editor extension from an older memnox answered before the Mac typed it elsewhere, which the
    /// daemon waits past; never sent, only kept so the person hears how to restart the editor's extensions.
    public let toldFailedFirst: Bool
    /// Something only the person can do before typing works as it should, said to them in plain steps.
    public let hint: TypingHint?

    public init(_ outcome: Delivery, _ reason: String? = nil, toldFailedFirst: Bool = false, hint: TypingHint? = nil, proof: Proof? = nil) {
        self.outcome = outcome
        self.reason = reason
        self.toldFailedFirst = toldFailedFirst
        self.hint = hint
        self.proof = proof
    }

    /// The same outcome, with what the person has to do about it.
    public func with(hint: TypingHint?) -> Typed {
        Typed(outcome, reason, toldFailedFirst: toldFailedFirst, hint: hint ?? self.hint, proof: proof)
    }

    /// Read back and seen to land; without proof it stays typed, since a check with nothing seen is no check.
    public func verified(_ proof: Proof?) -> Typed {
        guard wentIn, let proof else { return self }
        return Typed(.verified, reason, toldFailedFirst: toldFailedFirst, hint: hint, proof: proof)
    }

    /// Typed in either way: sent, whether or not it was read back.
    public var wentIn: Bool { outcome == .typed || outcome == .verified }

    public static let landed = Typed(.typed)
}

/// What the person has to do themselves so typing works, since no app may grant itself these.
public enum TypingHint: Equatable, Hashable, Sendable {
    /// Memnox may not press keys, so a terminal took the words all at once rather than typed.
    case allowTyping
    /// The editor still runs an older Memnox extension until its extensions restart.
    case restartExtensions(app: String)
    /// The editor has no Memnox extension, which the daemon puts in as it starts.
    case installExtension(app: String)
    /// A terminal app with several windows or tabs, so which is the session's could not be told and the words wait on the clipboard.
    case pasteIn(app: String)
    /// Claude's message box in an editor could not be found, so the person clicks into it once and it is learned.
    case clickMessageBox(app: String)
}

extension TypingHint {
    /// About where this typing's words ended up, rather than a setting the person changes once.
    public var isAboutThisTyping: Bool {
        switch self {
        case .pasteIn, .clickMessageBox: true
        case .allowTyping, .restartExtensions, .installExtension: false
        }
    }
}

public enum ProposalAnswer: String, Sendable {
    case confirmed
    case declined
}

/// What a held call takes, the same three words `HOLD_ANSWER` in the runtime accepts from a voice or a button.
public enum HoldAnswer: String, Sendable {
    case once
    case session
    case deny
    /// This call once, and the rule that stops the next identical one asking put on a card to place and sign.
    case always
}

/// How answering a held call from the screen ended, so the island can show it without a voice.
public enum HeldOutcome: Equatable, Sendable {
    case answered
    /// Somebody answered first, from the terminal, the workspace or the voice, and that answer stands.
    case answeredElsewhere(EarlierAnswer)
    /// Touch ID was cancelled, so nothing was sent and the call is still waiting.
    case cancelled
    case failed(String)
}

/// What a daemon answer settled, as the runtime names it in outcome; read through outcomeKind.
/// The wire keeps the raw string, so a word a newer daemon adds reads as nil rather than failing the answer.
public enum Outcome: String, CaseIterable, Sendable {
    /// A pairing was opened and its QR is ready to show.
    case pairing
    case paired
    case declined
    case revoked
    case granted
    /// One capability was taken back, and the device beside it shows what it still may do.
    case ungranted
    /// A phone holds a drive grant until the time beside it.
    case driving
    /// A drive grant ended early, because the phone asked to stop.
    case stopped
    /// It answered no, with the reason beside it.
    case refused
}

/// Where a pairing stands, as the runtime's pair-pending streams it.
public enum PairingState: String, CaseIterable, Sendable {
    /// The QR is up and no phone has reached it yet.
    case waiting
    /// A phone finished the handshake and waits on the person to check its digits.
    case answered
    case paired
    case declined
    case expired

    /// Paired, declined or expired: nothing more comes for this pairing.
    public var isOver: Bool {
        switch self {
        case .waiting, .answered: return false
        case .paired, .declined, .expired: return true
        }
    }
}

/// The phone that reached a pairing: its name, its key's fingerprint, and the digits both screens show.
public struct PairingPhone: Codable, Equatable, Sendable {
    public let name: String
    public let fingerprint: String
    /// Six digits from the handshake, the same on the phone and here when nobody stands between them.
    public let code: String

    public init(name: String, fingerprint: String, code: String) {
        self.name = name
        self.fingerprint = fingerprint
        self.code = code
    }
}

/// A pairing as the daemon answers it: pair-begin carries the QR and its expiry, pair-pending its state and phone.
public struct PairingInvite: Codable, Equatable, Sendable {
    public let id: String
    /// The memnox://pair link the QR encodes.
    public let qr: String?
    public let expiresAt: String?
    public let state: String?
    public let phone: PairingPhone?
    /// Who accepts it: this Mac's Touch ID, or the person typing the digits the device shows.
    public let approver: String?

    public init(id: String, qr: String? = nil, expiresAt: String? = nil, state: String? = nil, phone: PairingPhone? = nil, approver: String? = nil) {
        self.id = id
        self.qr = qr
        self.expiresAt = expiresAt
        self.state = state
        self.phone = phone
        self.approver = approver
    }

    /// The state as a known case, or nil for one this app does not know yet.
    public var pairingState: PairingState? { state.flatMap(PairingState.init(rawValue:)) }
}

/// What kind of device holds a key Memnox trusts.
public enum DeviceKind: String, CaseIterable, Sendable {
    case mac
    case phone
    /// A Mac reaching another machine through the relay, which starts with what a phone holds.
    case desktop
}

/// What a paired device may do from afar, as the runtime's remote allowlist names it.
public enum Capability: String, CaseIterable, Sendable {
    case see
    case ask
    case answer
    case steer
    case rules
    case rewind
    /// Acting on this Mac from afar, such as opening, typing and clicking; off until the person turns it on here with Touch ID.
    case mac
}

/// A device paired with this Mac, as devices-list and pair-accept answer it.
public struct Device: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let kind: String
    public let fingerprint: String
    public let capabilities: [String]
    public let pairedAt: String
    public let revokedAt: String?
    /// How the person said yes: mac-key for Touch ID here, local-shell for digits typed into memnox pair.
    public let approvedBy: String?

    public init(id: String, name: String, kind: String, fingerprint: String, capabilities: [String], pairedAt: String, revokedAt: String? = nil,
                approvedBy: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.fingerprint = fingerprint
        self.capabilities = capabilities
        self.pairedAt = pairedAt
        self.revokedAt = revokedAt
        self.approvedBy = approvedBy
    }

    /// The kind as a known case, or nil for one this app does not know yet.
    public var deviceKind: DeviceKind? { DeviceKind(rawValue: kind) }
    /// The capabilities this app knows, leaving out any a newer daemon added.
    public var granted: [Capability] { capabilities.compactMap(Capability.init(rawValue:)) }
    public var isRevoked: Bool { revokedAt != nil }
}

/// A question the team routed to the person, named on an ask so "allow it" can mean it; the runtime's TeamCallBrief.
public struct TeamCallBrief: Codable, Equatable, Sendable {
    /// The workspace's id for the call, the subject a yes to it is signed over.
    public let id: String
    /// "codex on build-box, from Ana's team", the same label every door shows.
    public let label: String
    /// What it wants, in plain words.
    public let what: String

    public init(id: String, label: String, what: String) {
        self.id = id
        self.label = label
        self.what = what
    }
}

/// The answer the voice heard to a team's question, which this Mac carries out with the workspace; the runtime's TeamAnswerBrief.
public struct TeamAnswerBrief: Codable, Equatable, Sendable {
    public let callId: String
    /// Once, session or deny; read through holdAnswer.
    public let answer: String
    public let label: String

    public init(callId: String, answer: String, label: String) {
        self.callId = callId
        self.answer = answer
        self.label = label
    }

    /// Nil for a word a newer daemon adds, which this Mac then carries out as nothing at all.
    public var holdAnswer: HoldAnswer? { HoldAnswer(rawValue: answer) }
}

/// The paired device an ask came from, as the daemon stamps it from the session.
public struct Origin: Codable, Equatable, Sendable {
    public let deviceId: String

    public init(deviceId: String) {
        self.deviceId = deviceId
    }
}

/// A phone driving this Mac, as a notice names it while the grant is live.
public struct DrivenBy: Codable, Equatable, Sendable {
    public let deviceId: String
    public let name: String
    /// When the grant ends, ISO 8601; absent once it has ended.
    public let until: String?

    public init(deviceId: String, name: String, until: String? = nil) {
        self.deviceId = deviceId
        self.name = name
        self.until = until
    }
}

/// A phone's conversation as the daemon mirrors it to the Mac: what was said when the turn starts,
/// then the answer in chunks, then ended; shown on the island and never spoken.
public struct PhoneTurn: Codable, Equatable, Sendable {
    public let deviceId: String
    public let name: String
    public let said: String?
    /// One more piece of the answer as it streams, to add to what came before.
    public let answer: String?
    public let ended: Bool?

    public init(deviceId: String, name: String, said: String? = nil, answer: String? = nil, ended: Bool? = nil) {
        self.deviceId = deviceId
        self.name = name
        self.said = said
        self.answer = answer
        self.ended = ended
    }
}

/// The phone that holds the voice: while it drives or talks, it speaks and the Mac only shows.
public struct VoiceHolder: Codable, Equatable, Sendable {
    public let deviceId: String
    public let name: String

    public init(deviceId: String, name: String) {
        self.deviceId = deviceId
        self.name = name
    }
}

/// A phone took the voice from the Mac or gave it back, for the Mac island to say where it went.
public struct VoiceOn: Codable, Equatable, Sendable {
    public let deviceId: String
    public let name: String
    public let holding: Bool

    public init(deviceId: String, name: String, holding: Bool) {
        self.deviceId = deviceId
        self.name = name
        self.holding = holding
    }
}

/// One piece of a line speak rendered: base64 of little endian signed 16 bit mono PCM at `rate` hertz.
public struct AudioChunk: Codable, Equatable, Sendable {
    public let rate: Int
    public let samples: String
    /// The line's final piece, which may still carry samples.
    public let last: Bool

    public init(rate: Int, samples: String, last: Bool) {
        self.rate = rate
        self.samples = samples
        self.last = last
    }
}

/// The line a phone speaks once the Mac has done what it asked.
public struct DoneLine: Codable, Equatable, Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public struct DaemonRequest: Encodable, Equatable, Sendable {
    public let id: Int
    public let method: String
    public var subject: String?
    public var answer: String?
    public var signature: String?
    /// On confirm of a draft: the words the person rewrote on its card, which the signature then covers.
    public var edited: String?
    /// On confirm of a mail: the addresses the person typed on its card, joined by commas, which the signature covers too.
    public var editedTo: String?
    /// On confirm of an agent's question: which of its questions the answer is for, from one.
    public var questionNumber: Int?
    /// On person-sign-in: this app's own waiting device code, so one approval in the browser signs the daemon in too.
    public var companionOf: String?
    public var point: String?
    public var said: String?
    /// On ask: they were waited on for the rest and said nothing more, so `said` is the whole of it.
    public var finished: Bool?
    /// On ask: how the person asked, chosen by the keys they held rather than by any word they said.
    public var intent: String?
    /// On ask: the Mac already greeted them out loud this sitting, so the answer does not open with another hello.
    public var greeted: Bool?
    /// On polish: the kind of place the dictation lands, as `DictationFamily` names it.
    public var family: String?
    /// On polish: the person's own words, spelled as they spell them.
    public var vocabulary: [String]?
    /// On polish: text they selected, which what they said is an instruction about.
    public var selection: String?
    /// On ask: the words so far, sent at a pause so the answer can start before they are known to be done.
    public var speculative: Bool?
    /// On ask: the app in front of the person as they spoke, by name, so a misheard word is read against it.
    public var lookingAt: String?
    /// On ask: the title of that app's window in front, which names the project an editor has open.
    public var lookingAtWindow: String?
    /// On ask while signed in to a team: its questions waiting on the person, an empty list forgetting the last ones.
    public var teamCalls: [TeamCallBrief]?
    /// On learn-words: each word as it was typed and as the person corrected it.
    public var learned: [LearnedWord]?
    public var sessionId: String?
    public var owner: String?
    public var briefing: String?
    public var since: String?
    /// On delivered: why typing did not land, in a few words.
    public var reason: String?
    /// On trace: the app's own steps for the question just answered.
    public var spans: [MacSpan]?
    /// On voice-agents: ask every installed agent again rather than answer from the last check.
    public var recheck: Bool?
    /// On choose-voice-agent: the agent's kind, such as cursor.
    public var voiceAgent: String?
    /// On delivered: what was read back after acting, which a verified outcome must carry.
    public var proof: Proof?
    /// On delivered: this Mac says out loud what the person has to do, so the brain adds nothing.
    public var told: Bool?
    /// On seen: what was on screen when the brain asked to look.
    public var sight: Sight?
    /// On delivered: the target's window just before and just after acting, with the words read off it.
    public var evidence: Witness?
    /// On pair-pending, pair-accept and pair-decline: the pairing answered.
    public var pairingId: String?
    /// On pair-accept where no Mac key is kept: the six digits the device shows, typed by the person.
    public var code: String?
    /// On device-revoke, device-grant and device-ungrant: the device it is about.
    public var deviceId: String?
    /// On device-grant and device-ungrant: the capability given or taken back.
    public var capability: String?
    /// On voice-choice: the Kokoro voice id; left out only asks which one is set. On speak: the voice to say it in, left out for this Mac's own.
    public var voice: String?
    /// On pair-begin: what to call this Mac on the phone.
    public var name: String?
    /// On drive: when the grant ends, ISO 8601; left out ends it now.
    public var until: String?
    /// On files-list: the folder relative to the person's home; left out lists the home itself. On session-view: one
    /// file the session changed, whose diff comes back in place of the whole view.
    public var path: String?
    /// On speak: the one sentence to say, cut at the Kokoro server's thousand characters.
    public var line: String?
    /// On speak: how fast to say it, held between half and one and a half; left out is this Mac's unhurried pace.
    public var speed: Double?
    /// On hand-over: the home's ready action, which the daemon refuses unless it is still the one ready.
    public var action: String?
    /// On connections-sign-in and connections-sign-out: the tool, by its lowercase slug, such as notion.
    public var toolkit: String?
    /// On connections-sign-in: open a new sign in even where one already works, to use another account.
    public var again: Bool?
    /// On toolkits-search: the words to match; left out lists the catalogue's first page.
    public var query: String?

    public init(id: Int, method: DaemonMethod) {
        self.id = id
        self.method = method.rawValue
    }
}

/// One correction as the runtime's LEARN_WORDS takes it.
public struct LearnedWord: Encodable, Equatable, Sendable {
    public let heard: String
    public let meant: String

    public init(heard: String, meant: String) {
        self.heard = heard
        self.meant = meant
    }
}

public struct DaemonEvent: Decodable, Equatable, Sendable {
    public let kind: String
    public let subject: String
    public let agent: String
    public let summary: String
    public let at: String
    public let expiresAt: String?
    /// On a held call, the facts to say it with: who, where, doing what, and why.
    public let agentName: String?
    public let what: String?
    public let why: String?
    public let task: String?
    /// On a held call or a notice, the person's latest follow up in that session, beside the task rather than over it.
    public let lastAsk: String?
    public let place: String?
    /// On a show event: open or card, its heading, and where the session runs.
    public let display: String?
    public let title: String?
    public let host: DisplayHost?
    /// On a card: the files the session changed and a few of the changed lines.
    public let files: [CardFile]?
    public let excerpt: CardExcerpt?
    /// On a notice, what happened; read it through noticeKind.
    public let notice: String?
    /// On a finished notice, how its tests stood when it handed back; read it through turnTests.
    public let tests: String?
    /// The session it is about, which an editor needs to open the right conversation.
    public let sessionId: String?
    /// On a walk card, one page per file, in the order the voice says them.
    public let pages: [WalkPage]?
    /// On the scan screen, every agent the scan found.
    public let agents: [AgentNode]?
    /// On a trace card, the waterfall to draw.
    public let trace: TraceData?
    /// On a draft, the message to put in front of the person before it is sent.
    public let draft: MailDraft?
    /// On a proposal of a rule, the rule and where it could hold, so the person picks a place before Touch ID.
    public let rule: RuleDraft?
    /// On a held call, or a proposal answering one, the daemon found it stays inside its session's repository.
    public let withinSession: Bool?
    /// On an app start, the app's own links and what it reads as it opens.
    public let app: AppLinks?
    /// On a launch, a terminal app or an editor's agent panel rather than a terminal tab; on an app start, a new chat first.
    public let via: String?
    /// On a show event, only the Mac app can perform it, so the daemon sent it here even when a phone asked.
    public let needsMac: Bool?
    /// On any event done for a paired device's ask, that device; absent when the person asked on this Mac.
    public let origin: Origin?
    /// On a notice, the phone driving this Mac and until when; no until says the grant ended.
    public let drivenBy: DrivenBy?
    /// On a notice, a turn of a phone's conversation, for the island to show without a sound.
    public let phoneTurn: PhoneTurn?
    /// On any event while a phone holds the voice: that phone says it and the Mac shows it without a sound.
    public let heardOn: VoiceHolder?
    /// On a notice, a phone took the voice from the Mac or gave it back.
    public let voiceOn: VoiceOn?
    /// On a proposal answering a team's question, which this Mac carries out with the workspace before confirming it.
    public let teamAnswer: TeamAnswerBrief?
    /// On a proposal to act in one of the person's tools, what goes out, drawn the way that tool draws it.
    public let work: WorkDraft?
    /// On a sign in display, the tools still to sign in to, each with its page.
    public let signIn: [ToolSignIn]?
    /// On a signed in or stalled notice, which tool, as whom, and what to carry on with.
    public let signedIn: SignedInNotice?
    /// On a proposal that an account is the person's own, answered from the signed in pill and never unasked.
    public let claim: AccountClaim?
    /// On a question notice, what the agent asked in its own picker with its choices, so the island offers them as taps.
    public let questions: [AgentQuestionItem]?
    /// On a question notice, what is already picked by question text, so only what is left is asked.
    public let answers: [String: String]?

    public var eventKind: EventKind? { EventKind(rawValue: kind) }
    public var noticeKind: NoticeKind? { notice.flatMap(NoticeKind.init(rawValue:)) }
    public var turnTests: TurnTests? { tests.flatMap(TurnTests.init(rawValue:)) }
    public var displayKind: Display? { display.flatMap(Display.init(rawValue:)) }
    /// Only a call the daemon placed inside its repository goes without a fingerprint; absent asks for one.
    public var needsTouchID: Bool { withinSession != true }

    /// On a link, the page to open; nil for anything but a web address, so a link never starts an app or signs in as somebody.
    public var webLink: URL? {
        guard displayKind == .link, let text = app?.links.first, let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), Self.webSchemes.contains(scheme),
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }

    /// The session a card is about, or nil for one about none, such as a list of pull requests, so it offers no window.
    public var cardSession: String? { sessionId == Self.noSession ? nil : sessionId }

    /// The same two schemes the runtime's open_link allows.
    private static let webSchemes: Set<String> = ["http", "https"]
    /// What the runtime names as the session of a show that belongs to none.
    private static let noSession = "all"
}

public struct AskChunk: Decodable, Equatable, Sendable {
    public let kind: String
    public let text: String?
    public let tool: String?

    public var chunkKind: ChunkKind? { ChunkKind(rawValue: kind) }

    /// Done, limited, failed or cancelled: the last line of a turn.
    public var endsTurn: Bool {
        chunkKind == .done || chunkKind == .limited || chunkKind == .failed || chunkKind == .cancelled
    }
}

/// One agent as the settings show it: there or not, whether it answered, and whether it is the voice.
public struct VoiceAgentStatus: Decodable, Equatable, Identifiable, Sendable {
    public let kind: String
    public let label: String
    public let installed: Bool
    /// Kept to reading; one that is not is used only when nothing else answered.
    public let sealed: Bool
    /// Nil until it has been asked.
    public let works: Bool?
    /// Why it did not answer, in words a person can act on.
    public let because: String?
    /// Its own account's words when it answered something else, such as a spent plan or a missing model.
    public let reply: String?
    public let checkedAt: String?
    public let chosen: Bool
    /// What to install, or set up, when it is missing or cannot answer.
    public let install: String

    public var id: String { kind }

    public init(kind: String, label: String, installed: Bool, sealed: Bool, works: Bool? = nil,
                because: String? = nil, reply: String? = nil, checkedAt: String? = nil, chosen: Bool = false, install: String = "") {
        self.kind = kind
        self.label = label
        self.installed = installed
        self.sealed = sealed
        self.works = works
        self.because = because
        self.reply = reply
        self.checkedAt = checkedAt
        self.chosen = chosen
        self.install = install
    }
}

/// One of the person's own tools as the cloud holds it: the toolkit's slug, and whether a sign in to it works now.
public struct ToolConnection: Decodable, Equatable, Identifiable, Sendable {
    /// The cloud's lowercase toolkit slug, such as gmail, slack or github.
    public let toolkit: String
    /// False for a sign in that is pending, expired, failed or turned off.
    public let connected: Bool
    /// True for a tool this Mac reaches itself, an MCP server or a signed in command line tool, never disconnected here.
    public let local: Bool?

    public var id: String { toolkit }
    public var isLocal: Bool { local == true }

    public init(toolkit: String, connected: Bool, local: Bool? = nil) {
        self.toolkit = toolkit
        self.connected = connected
        self.local = local
    }
}

/// The sign in page for one tool as connections-sign-in answers it; a paired phone gets opened false and opens it.
public struct ConnectionSignIn: Decodable, Equatable, Sendable {
    /// The cloud's lowercase toolkit slug.
    public let toolkit: String
    public let url: String
    /// True when the daemon opened the page in the Mac's browser itself.
    public let opened: Bool

    public init(toolkit: String, url: String, opened: Bool) {
        self.toolkit = toolkit
        self.url = url
        self.opened = opened
    }
}

/// One tool Memnox Cloud's catalogue offers, by the slug connections-sign-in takes.
public struct ToolkitSummary: Decodable, Equatable, Identifiable, Sendable {
    public let slug: String
    public let name: String
    public let logo: String?

    public var id: String { slug }

    public init(slug: String, name: String, logo: String? = nil) {
        self.slug = slug
        self.name = name
        self.logo = logo
    }
}

/// Where a session's agent runs, for bringing its window forward.
public struct DaemonLocation: Decodable, Equatable, Sendable {
    public let sessionId: String
    public let agent: String
    public let alive: Bool
    public let app: String?
    public let appPath: String?
    public let tty: String?
    public let cwd: String?
}

public struct DaemonResponse: Decodable, Equatable, Sendable {
    public let id: Int
    public let ok: Bool
    public let event: DaemonEvent?
    public let waiting: [DaemonEvent]?
    public let chunk: AskChunk?
    public let outcome: String?
    public let location: DaemonLocation?
    public let words: [String]?
    /// On session-view: the session as it is right now.
    public let session: SessionView?
    /// On session-view with a path: that file's diff, its hunks with the lines around each change.
    public let diff: CardExcerpt?
    /// On sessions-list: the sessions lately, most recently active first.
    public let sessions: [SessionCard]?
    /// On voice-agents and choose-voice-agent: every agent the voice knows, preferred first.
    public let voiceAgents: [VoiceAgentStatus]?
    /// On ping, which memnox answered; a daemon from before it said so leaves it out.
    public let version: String?
    public let error: String?
    /// Why it answered refused, in words the person can be told.
    public let reason: String?
    /// On pair-begin and pair-pending: the pairing as it stands.
    public let pairing: PairingInvite?
    /// On devices-list: every device paired with this Mac.
    public let devices: [Device]?
    /// On pair-accept and device-ungrant: the device as it now stands.
    public let device: Device?
    /// On voice-choice: the Kokoro voice the daemon holds.
    public let voice: String?
    /// On a remote ask: the device it came from, which the daemon set and nobody else may.
    public let origin: Origin?
    /// On a device's ping: whether the machine has a Kokoro voice to lend, left out by a runtime too old to say.
    public let speaks: Bool?
    /// On a device's ping: what that device may do on this machine, left out by a runtime too old to say.
    public let capabilities: [String]?
    /// On a refused pair-accept with digits: how many more the pairing takes before it closes.
    public let triesLeft: Int?
    /// To a phone: the one line a Mac action ended with, for the phone to speak.
    public let done: DoneLine?
    /// On drive: when the grant it answered ends.
    public let until: String?
    /// On files-list: the folder listed, relative to the person's home and empty for the home itself.
    public let path: String?
    /// On files-list: folders first and then files, each by name, hidden entries left out.
    public let files: [FileEntry]?
    /// On speak: one piece of the rendered line, in order until the one whose last is true.
    public let audio: AudioChunk?
    /// On home: the five blocks, as the runtime's home.ts gathers them.
    public let home: DaemonHome?
    /// On connections-list: one per tool the person signed in to, sorted by tool.
    public let connections: [ToolConnection]?
    /// On connections-sign-in: the page that connects the tool, and whether the daemon already opened it.
    public let signIn: ConnectionSignIn?
    /// On toolkits-search: at most thirty tools the catalogue matched.
    public let toolkits: [ToolkitSummary]?
    /// On hand-over: the rule proposal the person now confirms, by its id.
    public let proposed: String?
    /// On person, person-sign-in and person-sign-out: where the daemon's own sign in stands.
    public let person: PersonStanding?
    /// On machine, machine-sign-in and machine-sign-out: whether this machine is connected to a workspace.
    public let machine: MachineStanding?
    /// On polish: the dictation as it should be typed.
    public let polished: String?

    /// The outcome as a known case, or nil for one this app does not know yet.
    public var outcomeKind: Outcome? { outcome.flatMap(Outcome.init(rawValue:)) }
}

/// Where a sign in on the daemon's side stands, the same for the person and for this machine, so one piece of
/// code shows both: whether it is in, the name to say, a code under way, and why the last one stopped.
public protocol SignInStanding: Sendable {
    var signedIn: Bool { get }
    var name: String? { get }
    var code: PersonSignInCode? { get }
    var failed: String? { get }
}

/// Whether this machine is connected to a workspace, the credential memnox login writes, which is what carries rules,
/// workspace memory and phone pairing to it. The workspace's name stands where a person's would.
public struct MachineStanding: Decodable, Equatable, Sendable, SignInStanding {
    public let signedIn: Bool
    public let name: String?
    public let workspaceId: String?
    public let machineId: String?
    /// A connection under way: the code to approve and where.
    public let code: PersonSignInCode?
    /// Why the last connection stopped, or that the workspace let this machine go.
    public let failed: String?

    public init(signedIn: Bool, name: String? = nil, workspaceId: String? = nil, machineId: String? = nil,
                code: PersonSignInCode? = nil, failed: String? = nil) {
        self.signedIn = signedIn
        self.name = name
        self.workspaceId = workspaceId
        self.machineId = machineId
        self.code = code
        self.failed = failed
    }
}

/// Whether a person is signed in on the daemon's side, which is what the voice and the terminal act through.
public struct PersonStanding: Decodable, Equatable, Sendable, SignInStanding {
    public let signedIn: Bool
    public let name: String?
    public let workspaceId: String?
    /// A sign in under way: the code to approve and where.
    public let code: PersonSignInCode?
    /// Why the last sign in stopped, until the next one starts.
    public let failed: String?

    public init(signedIn: Bool, name: String? = nil, workspaceId: String? = nil, code: PersonSignInCode? = nil, failed: String? = nil) {
        self.signedIn = signedIn
        self.name = name
        self.workspaceId = workspaceId
        self.code = code
        self.failed = failed
    }
}

/// The code the daemon's sign in waits on, for the person to approve in the console.
public struct PersonSignInCode: Decodable, Equatable, Sendable {
    public let userCode: String
    public let page: String?
    /// Epoch milliseconds.
    public let expiresAt: Double

    public init(userCode: String, page: String? = nil, expiresAt: Double) {
        self.userCode = userCode
        self.page = page
        self.expiresAt = expiresAt
    }
}

/// An agent's desktop app as an app start names it: its links, opened in order once the app is open,
/// and what it reads as it opens, for an app that takes its folder from nowhere else.
public struct AppLinks: Decodable, Equatable, Sendable {
    public let links: [String]
    public let env: [String: String]?
}

/// The home every surface opens on, mirrored from the runtime's HomeView in daemon/home.ts: what waits on the
/// person, what is working, what happened today, the one thing that could be handed over, and what nothing covers.
public struct DaemonHome: Decodable, Equatable, Sendable {
    public let machine: String
    /// observe or enforce, as the daemon says it.
    public let mode: String
    /// How many calls are held on this machine.
    public let waiting: Int
    public let working: [HomeWorking]
    public let today: HomeToday
    /// Absent while nothing has been said yes to often enough, and never refused, to run on its own.
    public let ready: HomeReady?
    public let notCovered: HomeNotCovered
    /// What only the person can do for what is here to be in force, word for word; absent when nothing is owed.
    public let needsYou: [String]?

    public init(machine: String, mode: String, waiting: Int, working: [HomeWorking], today: HomeToday,
                ready: HomeReady? = nil, notCovered: HomeNotCovered, needsYou: [String]? = nil) {
        self.machine = machine
        self.mode = mode
        self.waiting = waiting
        self.working = working
        self.today = today
        self.ready = ready
        self.notCovered = notCovered
        self.needsYou = needsYou
    }
}

/// An agent at work right now, as one line on the home.
public struct HomeWorking: Decodable, Equatable, Identifiable, Sendable {
    public let sessionId: String
    public let agent: String
    public let agentName: String
    public let task: String?
    public let repository: String?

    public var id: String { sessionId }

    public init(sessionId: String, agent: String, agentName: String, task: String? = nil, repository: String? = nil) {
        self.sessionId = sessionId
        self.agent = agent
        self.agentName = agentName
        self.task = task
        self.repository = repository
    }
}

/// What the ledger says since local midnight; allowed counts a person's yes, never an agent's own allowed call.
public struct HomeToday: Decodable, Equatable, Sendable {
    public let actions: Int
    public let asked: Int
    public let allowed: Int
    public let refused: Int

    public init(actions: Int, asked: Int, allowed: Int, refused: Int) {
        self.actions = actions
        self.asked = asked
        self.allowed = allowed
        self.refused = refused
    }
}

/// The one action people have said yes to often enough, and never refused, to let it run on its own.
public struct HomeReady: Decodable, Equatable, Sendable {
    /// What hand-over is sent, word for word.
    public let action: String
    public let approvals: Int
    /// Who was asked, present only when every yes came from one agent.
    public let agentName: String?
    /// What the yeses were about; the rule it becomes names these and no others.
    public let targets: [String]
    public let because: String

    public init(action: String, approvals: Int, agentName: String? = nil, targets: [String] = [], because: String) {
        self.action = action
        self.approvals = approvals
        self.agentName = agentName
        self.targets = targets
        self.because = because
    }
}

/// What no rule or seam covers here, as counts.
public struct HomeNotCovered: Decodable, Equatable, Sendable {
    /// Agents found on this machine that run outside Memnox.
    public let unprotected: Int
    /// Agents silent for a month that still hold reach.
    public let dormant: Int

    public init(unprotected: Int, dormant: Int) {
        self.unprotected = unprotected
        self.dormant = dormant
    }
}

/// The oldest memnox this app works with: the first to say its version on ping, so any daemon that
/// says none is older. Raised whenever the app comes to need something a newer runtime added.
public enum MinimumRuntime: Sendable {
    public static let version = "0.13.14"
}

/// Whether a version is this one or newer, by major, minor and patch as numbers; none at all is older.
public func isAtLeast(_ found: String?, _ needed: String) -> Bool {
    guard let found else { return false }
    func parts(_ version: String) -> [Int] {
        version.split(separator: "-").first.map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? []
    }
    let have = parts(found), want = parts(needed)
    for index in 0..<max(have.count, want.count) {
        let a = index < have.count ? have[index] : 0, b = index < want.count ? want[index] : 0
        if a != b { return a > b }
    }
    return true
}

/// What a confirmation signs, byte for byte what the runtime's `confirmationMessage` builds. Words the person
/// rewrote on a draft card go last and whole, so the fingerprint covers exactly what is sent, and addresses rewritten
/// on a mail go just before them, since an address never holds a colon and words may.
public func confirmationMessage(subject: String, answer: String, edited: String? = nil, editedTo: String? = nil) -> String {
    if let editedTo { return "memnox-confirm:v3:\(subject):\(answer):\(editedTo):\(edited ?? "")" }
    guard let edited else { return "memnox-confirm:v1:\(subject):\(answer)" }
    return "memnox-confirm:v2:\(subject):\(answer):\(edited)"
}

/// What Touch ID signs to pair a phone, byte for byte what the runtime verifies on pair-accept.
public func pairingMessage(pairingId: String, fingerprint: String) -> String {
    "memnox-pair:v1:\(pairingId):\(fingerprint)"
}

/// What Touch ID signs to give a device a capability, byte for byte what the runtime verifies on device-grant.
public func grantMessage(deviceId: String, capability: Capability) -> String {
    "memnox-grant:v1:\(deviceId):\(capability.rawValue)"
}

/// What a phone signs to drive this Mac until a time, byte for byte what the runtime verifies on drive.
/// The Mac never signs it, and it lives here so every signed string is built in one place.
public func driveMessage(deviceId: String, until: String) -> String {
    "memnox-drive:v1:\(deviceId):\(until)"
}

/// What a person signs to type their own words into one session, byte for byte what the runtime verifies on follow-up.
/// The words are inside it, so a signature for one message never carries another.
public func followUpMessage(sessionId: String, words: String) -> String {
    "memnox-follow-up:v1:\(sessionId):\(words)"
}

/// How a follow up reached its session, as the runtime's FOLLOW_UP_OUTCOME names it.
public enum FollowUpOutcome: String, CaseIterable, Sendable {
    /// Working: it reads the words at its next step.
    case queued
    /// Waiting at its prompt: the Mac is typing the words in and sending them.
    case typed
    /// Waiting where nothing can type: it reads the words the next time it is prompted.
    case later
}

/// What a phone signs over its pairing handshake hash to prove it holds its key, byte for byte what the runtime verifies.
/// The Mac never signs it, and it lives here so every signed string is built in one place.
public func deviceProofMessage(handshakeHash: Data) -> String {
    "memnox-device:v1:\(handshakeHash.base64EncodedString())"
}

public enum ProtocolError: Error, Equatable, Sendable {
    case unreadable(String)
    case refused(String)
    /// Nothing listens at the socket, which is a daemon between a stop and launchd starting it again.
    case notRunning(String)
    case disconnected
}

public func encodeLine(_ request: DaemonRequest) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    var data = try encoder.encode(request)
    data.append(lineEnd)
    return data
}

/// The newline that ends every request, since the daemon reads one JSON object per line.
private let lineEnd: UInt8 = 0x0A

public func decodeLine(_ line: String) throws -> DaemonResponse {
    guard let data = line.data(using: .utf8) else { throw ProtocolError.unreadable(line) }
    do {
        return try JSONDecoder().decode(DaemonResponse.self, from: data)
    } catch {
        throw ProtocolError.unreadable(line)
    }
}
