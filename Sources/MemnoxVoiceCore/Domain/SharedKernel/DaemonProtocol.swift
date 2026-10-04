import Foundation

// The daemon's line protocol, mirrored field for field from memnox-runtime's
// packages/core/src/daemon/protocol.ts, since the two sides only ever meet as JSON.

public enum DaemonMethod: String {
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
    /// Which of the person's agents can be the voice, and why the others cannot.
    case voiceAgents = "voice-agents"
    /// The person picking which agent the voice thinks with.
    case chooseVoiceAgent = "choose-voice-agent"
    /// Words the person fixed in what the app typed for them, kept so they are heard right next time.
    case learnWords = "learn-words"
    /// Which of the person's agents can be the voice, and why the others cannot.
    case voiceAgents = "voice-agents"
    /// The person picking which agent the voice thinks with.
    case chooseVoiceAgent = "choose-voice-agent"
    /// Words the person fixed in what the app typed for them, kept so they are heard right next time.
    case learnWords = "learn-words"
    /// Which of the person's agents can be the voice, and why the others cannot.
    case voiceAgents = "voice-agents"
    /// The person picking which agent the voice thinks with.
    case chooseVoiceAgent = "choose-voice-agent"
    /// Words the person fixed in what the app typed for them, kept so they are heard right next time.
    case learnWords = "learn-words"
    /// Which of the person's agents can be the voice, and why the others cannot.
    case voiceAgents = "voice-agents"
    /// The person picking which agent the voice thinks with.
    case chooseVoiceAgent = "choose-voice-agent"
    /// Words the person fixed in what the app typed for them, kept so they are heard right next time.
    case learnWords = "learn-words"
    /// Which of the person's agents can be the voice, and why the others cannot.
    case voiceAgents = "voice-agents"
    /// The person picking which agent the voice thinks with.
    case chooseVoiceAgent = "choose-voice-agent"
    /// Words the person fixed in what the app typed for them, kept so they are heard right next time.
    case learnWords = "learn-words"
    /// Which of the person's agents can be the voice, and why the others cannot.
    case voiceAgents = "voice-agents"
    /// The person picking which agent the voice thinks with.
    case chooseVoiceAgent = "choose-voice-agent"
}

public enum EventKind: String {
    /// A message from the person's connected mail, drafted for them to read; Send is a signed confirm of the subject.
    case draft
    /// A folder the person named, opened where the title says.
    case folder
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
}

/// Where a rule can be put in force: every agent on this Mac, or only inside one repository.
public enum RuleScopeKind: String, CaseIterable, Sendable {
    case machine
    case repository
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
    case held
    case proposal
    case paused
    case settled
    /// The person asked to see a session: its window brought forward, or its summary on a card.
    case show
    /// A message from the person's connected mail, drafted for them to read; Send is a signed confirm of the subject.
    case draft
    /// A folder the person named, opened where the title says.
    case folder
}

/// Where a folder opens, as the runtime's FOLDER_OPENER names it in a folder display's title.
public enum FolderOpener: String, Sendable {
    case finder
    case editor
    case terminal
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
    /// Worth saying unasked: a session finished, committed or pushed.
    case notice
}

/// How a show event wants to be shown.
public enum Display: String {
    /// A folder the person named, opened where the title says.
    case folder
}

/// Where a folder opens, as the runtime's FOLDER_OPENER names it in a folder display's title.
public enum FolderOpener: String, Sendable {
    case finder
    case editor
    case terminal
    case open
    case card
    /// Type the person's confirmed instruction into the terminal tab the agent waits in.
    case type
    /// Open the session in its editor with the instruction in its input, for the person to send.
    case prefill
    /// A folder the person named, opened where the title says.
    case folder
}

/// Where a folder opens, as the runtime's FOLDER_OPENER names it in a folder display's title.
public enum FolderOpener: String, Sendable {
    case finder
    case editor
    case terminal
    /// Turn through the sessions to this one and bring its own terminal tab or editor forward.
    case focus
    /// Open a new terminal tab in a repository and type the line that starts an agent there.
    case launch
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
    /// Every Memnox card and window off the screen, with every agent and its tab left alone.
    case dismiss
}

/// A session as one card in the switcher: who, on what, in what state, and where it runs.
public struct SessionCard: Decodable, Equatable, Identifiable {
    public let sessionId: String
    /// Which agent it is, such as claude-code; absent from a daemon older than the field.
    public let agent: String?
    public let agentName: String
    public let task: String?
    public let state: String
    public let thinking: Bool
    public let repository: String?
    public let runningIn: String?
    public let lastActive: String?
    public let host: DisplayHost?

    public var id: String { sessionId }
    /// The state as a known case, or nil for one this app does not know yet.
    public var sessionState: SessionState? { SessionState(rawValue: state) }

    public init(sessionId: String, agent: String? = nil, agentName: String, task: String? = nil, state: String, thinking: Bool = false,
                repository: String? = nil, runningIn: String? = nil, lastActive: String? = nil, host: DisplayHost? = nil) {
        self.sessionId = sessionId
        self.agent = agent
        self.agentName = agentName
        self.task = task
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
public struct SessionViewStep: Decodable, Equatable {
    public let at: String
    public let surface: String
    public let text: String
    public let failed: Bool?
    public let refused: Bool?

    /// The surface as a known case, or nil for one this app does not know yet.
    public var stepSurface: StepSurface? { StepSurface(rawValue: surface) }
}

/// A session as it is right now: what it is on, what it just did, and what it changed.
public struct SessionView: Decodable, Equatable {
    public let sessionId: String
    public let agent: String
    public let agentName: String
    public let task: String?
    public let state: String
    public let thinking: Bool
    public let repository: String?
    public let runningIn: String?
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

    /// The state as a known case, or nil for one this app does not know yet.
    public var sessionState: SessionState? { SessionState(rawValue: state) }
}

/// A line of a session's conversation: what the person asked, what the agent said, or a tool it ran.
public struct ConversationLine: Decodable, Equatable {
    public let at: String
    /// person, agent or tool.
    public let who: String
    public let text: String
}

/// A file on a summary card, with its lines added and removed; a binary file has no counts.
public struct CardFile: Decodable, Equatable {
    public let path: String
    public let added: Int?
    public let removed: Int?

    public init(path: String, added: Int? = nil, removed: Int? = nil) {
        self.path = path
        self.added = added
        self.removed = removed
    }
}

/// A few changed lines of one file, so the card shows the code and not only its name.
public struct CardExcerpt: Decodable, Equatable {
    public let path: String
    public let lines: [String]

    public init(path: String, lines: [String]) {
        self.path = path
        self.lines = lines
    }
}

/// One file of a walk through: what the voice says about it and the lines it is about.
public struct WalkPage: Decodable, Equatable {
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
public struct MacSpan: Encodable, Equatable {
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
public struct TraceData: Decodable, Equatable {
    public struct Row: Decodable, Equatable {
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
public struct AgentNode: Decodable, Equatable, Identifiable {
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

    public init(id: String, kind: String, name: String, servers: Int = 0, reaches: [String] = [], working: Int = 0, open: Int = 0,
                mcp: [AgentServer]? = nil, clis: [String]? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.servers = servers
        self.reaches = reaches
        self.working = working
        self.open = open
        self.mcp = mcp
        self.clis = clis
    }
}

/// One MCP server on the scan screen; the counts are absent where no scan has asked it.
    /// On ask: how the person asked, chosen by the keys they held rather than by any word they said.
    public var intent: String?
public struct AgentServer: Decodable, Equatable {
    public let name: String
    /// On ask: the app in front of the person as they spoke, by name, so a misheard word is read against it.
    public var lookingAt: String?
    /// On learn-words: each word as it was typed and as the person corrected it.
    public var learned: [LearnedWord]?
    public let tools: Int?
    public let changing: Int?

    public init(name: String, tools: Int? = nil, changing: Int? = nil) {
        self.name = name
        self.tools = tools
        self.changing = changing
    }
    /// On voice-agents: ask every installed agent again rather than answer from the last check.
    public var recheck: Bool?
    /// On choose-voice-agent: the agent's kind, such as cursor.
    public var voiceAgent: String?
}

/// Where a session runs, as its hook saw it: the app, its terminal tab and its folder.
public struct DisplayHost: Decodable, Equatable, Sendable {
    public let app: String?
    public let appPath: String?
    public let tty: String?
/// One correction as the runtime's LEARN_WORDS takes it.
public struct LearnedWord: Encodable, Equatable, Sendable {
    public let heard: String
    public let meant: String

    public init(heard: String, meant: String) {
        self.heard = heard
        self.meant = meant
    }
}

    public let cwd: String?
    /// The agent's own id for the conversation, which an editor's agent panel opens by.
    public let conversation: String?

    public init(app: String? = nil, appPath: String? = nil, tty: String? = nil, cwd: String? = nil, conversation: String? = nil) {
        self.app = app
        self.appPath = appPath
        self.tty = tty
        self.cwd = cwd
        self.conversation = conversation
    }
}

public enum ChunkKind: String {
    case text
    case tool
    case done
    case limited
    case failed
    case cancelled
}

public enum Briefing: String {
    case held
    case paused
    case back
    case notice
}

/// How typing an instruction ended, mirrored from the runtime's DELIVERY.
    /// On a draft, the message to put in front of the person before it is sent.
    public let draft: MailDraft?
    /// On a proposal of a rule, the rule and where it could hold, so the person picks a place before Touch ID.
    public let rule: RuleDraft?
    /// On a held call, or a proposal answering one, the daemon found it stays inside its session's repository.
    public let withinSession: Bool?
public enum Delivery: String {
    case typed
    /// It could not be typed safely, so the words were left on the clipboard.
    case clipboard
    /// Only a call the daemon placed inside its repository goes without a fingerprint; absent asks for one.
    public var needsTouchID: Bool { withinSession != true }
    case failed
    /// Memnox is not allowed to press keys until the person turns it on under Accessibility; the words were left on the clipboard.
    case notAllowed = "not-allowed"
}
    /// On ask: the app in front of the person as they spoke, by name, so a misheard word is read against it.
    public var lookingAt: String?
    /// On learn-words: each word as it was typed and as the person corrected it.
    public var learned: [LearnedWord]?

/// What became of typing an instruction, and why when it did not land.
public struct Typed: Equatable {
    public let outcome: Delivery
    public let reason: String?

    public init(_ outcome: Delivery, _ reason: String? = nil) {
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
    public let checkedAt: String?
    public let chosen: Bool
    /// What to install, or set up, when it is missing or cannot answer.
    public let install: String

    public var id: String { kind }

    public init(kind: String, label: String, installed: Bool, sealed: Bool, works: Bool? = nil,
                because: String? = nil, checkedAt: String? = nil, chosen: Bool = false, install: String = "") {
        self.kind = kind
        self.label = label
        self.installed = installed
        self.sealed = sealed
        self.works = works
        self.because = because
        self.checkedAt = checkedAt
        self.chosen = chosen
        self.install = install
    }
}

        self.outcome = outcome
    /// On voice-agents: ask every installed agent again rather than answer from the last check.
    public var recheck: Bool?
    /// On choose-voice-agent: the agent's kind, such as cursor.
    public var voiceAgent: String?
        self.reason = reason
    }

    public static let landed = Typed(.typed)
}

public enum ProposalAnswer: String {
/// One correction as the runtime's LEARN_WORDS takes it.
public struct LearnedWord: Encodable, Equatable, Sendable {
    public let heard: String
    public let meant: String

    public init(heard: String, meant: String) {
        self.heard = heard
        self.meant = meant
    }
}

    /// On ask: the app in front of the person as they spoke, by name, so a misheard word is read against it.
    /// On voice-agents and choose-voice-agent: every agent the voice knows, preferred first.
    public let voiceAgents: [VoiceAgentStatus]?
    public var lookingAt: String?
    /// On learn-words: each word as it was typed and as the person corrected it.
    public var learned: [LearnedWord]?
    case confirmed
    case declined
}

/// What a held call takes, the same three words `HOLD_ANSWER` in the runtime accepts from a voice or a button.
public enum HoldAnswer: String, Sendable {
    case once
    case session
    /// On voice-agents: ask every installed agent again rather than answer from the last check.
    public var recheck: Bool?
    /// On choose-voice-agent: the agent's kind, such as cursor.
    public var voiceAgent: String?
    case deny
}

/// How answering a held call from the screen ended, so the island can show it without a voice.
public enum HeldOutcome: Equatable, Sendable {
    case answered
    /// Touch ID was cancelled, so nothing was sent and the call is still waiting.
/// One correction as the runtime's LEARN_WORDS takes it.
public struct LearnedWord: Encodable, Equatable, Sendable {
    public let heard: String
    public let meant: String

    public init(heard: String, meant: String) {
        self.heard = heard
    /// On a draft, the message to put in front of the person before it is sent.
    public let draft: MailDraft?
    /// On a held call, or a proposal answering one, the daemon found it stays inside its session's repository.
    public let withinSession: Bool?
        self.meant = meant
    }
}

    /// Only a call the daemon placed inside its repository goes without a fingerprint; absent asks for one.
    public var needsTouchID: Bool { withinSession != true }
    /// On ask: the app in front of the person as they spoke, by name, so a misheard word is read against it.
    public var lookingAt: String?
    /// On learn-words: each word as it was typed and as the person corrected it.
    public var learned: [LearnedWord]?
    case cancelled
    case failed(String)
}

public struct DaemonRequest: Encodable, Equatable {
    public let id: Int
    /// On ask: the app in front of the person as they spoke, by name, so a misheard word is read against it.
    public var lookingAt: String?
    /// On voice-agents: ask every installed agent again rather than answer from the last check.
    public var recheck: Bool?
    /// On choose-voice-agent: the agent's kind, such as cursor.
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
    public let checkedAt: String?
    public let chosen: Bool
    /// What to install, or set up, when it is missing or cannot answer.
    public let install: String

    public var id: String { kind }

    public init(kind: String, label: String, installed: Bool, sealed: Bool, works: Bool? = nil,
                because: String? = nil, checkedAt: String? = nil, chosen: Bool = false, install: String = "") {
        self.kind = kind
        self.label = label
        self.installed = installed
        self.sealed = sealed
        self.works = works
        self.because = because
        self.checkedAt = checkedAt
        self.chosen = chosen
        self.install = install
    }
}

    public var voiceAgent: String?
    /// On learn-words: each word as it was typed and as the person corrected it.
    public var learned: [LearnedWord]?
    public let method: String
    public var subject: String?
    public var answer: String?
    public var signature: String?
    public var point: String?
/// One correction as the runtime's LEARN_WORDS takes it.
public struct LearnedWord: Encodable, Equatable, Sendable {
    public let heard: String
    public let meant: String

    public init(heard: String, meant: String) {
        self.heard = heard
    /// On a held call, or a proposal answering one, the daemon found it stays inside its session's repository.
    public let withinSession: Bool?
        self.meant = meant
    }
}

    /// Only a call the daemon placed inside its repository goes without a fingerprint; absent asks for one.
    public var needsTouchID: Bool { withinSession != true }
    public var said: String?
    /// On voice-agents and choose-voice-agent: every agent the voice knows, preferred first.
    public let voiceAgents: [VoiceAgentStatus]?
    /// On learn-words: each word as it was typed and as the person corrected it.
    public var learned: [LearnedWord]?
    /// On voice-agents: ask every installed agent again rather than answer from the last check.
    public var recheck: Bool?
    /// On choose-voice-agent: the agent's kind, such as cursor.
    public var voiceAgent: String?
    /// On ask: they were waited on for the rest and said nothing more, so `said` is the whole of it.
    public var finished: Bool?
    /// On ask: the words so far, sent at a pause so the answer can start before they are known to be done.
    public var speculative: Bool?
    public var sessionId: String?
    public var owner: String?
    public var briefing: String?
/// One correction as the runtime's LEARN_WORDS takes it.
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
    public let checkedAt: String?
    public let chosen: Bool
    /// What to install, or set up, when it is missing or cannot answer.
    public let install: String

    public var id: String { kind }

    public init(kind: String, label: String, installed: Bool, sealed: Bool, works: Bool? = nil,
                because: String? = nil, checkedAt: String? = nil, chosen: Bool = false, install: String = "") {
        self.kind = kind
        self.label = label
        self.installed = installed
        self.sealed = sealed
        self.works = works
        self.because = because
        self.checkedAt = checkedAt
        self.chosen = chosen
        self.install = install
    }
}

public struct LearnedWord: Encodable, Equatable, Sendable {
    public let heard: String
    public let meant: String

    public init(heard: String, meant: String) {
        self.heard = heard
        self.meant = meant
    }
}

    public var since: String?
    /// On voice-agents: ask every installed agent again rather than answer from the last check.
    public var recheck: Bool?
    /// On choose-voice-agent: the agent's kind, such as cursor.
    public var voiceAgent: String?
    /// On delivered: why typing did not land, in a few words.
    public var reason: String?
    /// On trace: the app's own steps for the question just answered.
    public var spans: [MacSpan]?
    /// On voice-agents: ask every installed agent again rather than answer from the last check.
    public var recheck: Bool?
    /// On choose-voice-agent: the agent's kind, such as cursor.
/// One correction as the runtime's LEARN_WORDS takes it.
public struct LearnedWord: Encodable, Equatable, Sendable {
    /// On voice-agents and choose-voice-agent: every agent the voice knows, preferred first.
    public let voiceAgents: [VoiceAgentStatus]?
    public let heard: String
    public let meant: String

    public init(heard: String, meant: String) {
        self.heard = heard
        self.meant = meant
    }
}

    public var voiceAgent: String?
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
    public let checkedAt: String?
    public let chosen: Bool
    /// What to install, or set up, when it is missing or cannot answer.
    public let install: String

    public var id: String { kind }

    public init(kind: String, label: String, installed: Bool, sealed: Bool, works: Bool? = nil,
                because: String? = nil, checkedAt: String? = nil, chosen: Bool = false, install: String = "") {
        self.kind = kind
        self.label = label
        self.installed = installed
        self.sealed = sealed
        self.works = works
        self.because = because
        self.checkedAt = checkedAt
        self.chosen = chosen
        self.install = install
    }
}


    public init(id: Int, method: DaemonMethod) {
        self.id = id
        self.method = method.rawValue
    }
}

public struct DaemonEvent: Decodable, Equatable {
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
    public let place: String?
    /// On a show event: open or card, its heading, and where the session runs.
    public let display: String?
    public let title: String?
    public let host: DisplayHost?
    /// On voice-agents and choose-voice-agent: every agent the voice knows, preferred first.
    public let voiceAgents: [VoiceAgentStatus]?
    /// On a card: the files the session changed and a few of the changed lines.
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
    public let checkedAt: String?
    public let chosen: Bool
    /// What to install, or set up, when it is missing or cannot answer.
    public let install: String

    public var id: String { kind }

    public init(kind: String, label: String, installed: Bool, sealed: Bool, works: Bool? = nil,
                because: String? = nil, checkedAt: String? = nil, chosen: Bool = false, install: String = "") {
        self.kind = kind
        self.label = label
        self.installed = installed
        self.sealed = sealed
        self.works = works
        self.because = because
        self.checkedAt = checkedAt
        self.chosen = chosen
        self.install = install
    }
}

    public let files: [CardFile]?
    public let excerpt: CardExcerpt?
    /// On a notice, what happened; read it through noticeKind.
    public let notice: String?
    /// The session it is about, which an editor needs to open the right conversation.
    public let sessionId: String?
    /// On a walk card, one page per file, in the order the voice says them.
    public let pages: [WalkPage]?
    /// On the scan screen, every agent the scan found.
    public let agents: [AgentNode]?
    /// On a trace card, the waterfall to draw.
    public let trace: TraceData?

    public var eventKind: EventKind? { EventKind(rawValue: kind) }
    public var noticeKind: NoticeKind? { notice.flatMap(NoticeKind.init(rawValue:)) }
    public var displayKind: Display? { display.flatMap(Display.init(rawValue:)) }
}

public struct AskChunk: Decodable, Equatable {
    public let kind: String
    public let text: String?
    public let tool: String?

/// One agent as the settings show it: there or not, whether it answered, and whether it is the voice.
    /// On voice-agents and choose-voice-agent: every agent the voice knows, preferred first.
    public let voiceAgents: [VoiceAgentStatus]?
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
    public let checkedAt: String?
    public let chosen: Bool
    /// What to install, or set up, when it is missing or cannot answer.
    public let install: String

    public var id: String { kind }

    public init(kind: String, label: String, installed: Bool, sealed: Bool, works: Bool? = nil,
                because: String? = nil, checkedAt: String? = nil, chosen: Bool = false, install: String = "") {
        self.kind = kind
        self.label = label
        self.installed = installed
        self.sealed = sealed
        self.works = works
        self.because = because
        self.checkedAt = checkedAt
        self.chosen = chosen
        self.install = install
    }
}

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
    public let checkedAt: String?
    public let chosen: Bool
    /// What to install, or set up, when it is missing or cannot answer.
    public let install: String

    /// On voice-agents and choose-voice-agent: every agent the voice knows, preferred first.
    public let voiceAgents: [VoiceAgentStatus]?
    public var id: String { kind }

    public init(kind: String, label: String, installed: Bool, sealed: Bool, works: Bool? = nil,
                because: String? = nil, checkedAt: String? = nil, chosen: Bool = false, install: String = "") {
        self.kind = kind
        self.label = label
        self.installed = installed
        self.sealed = sealed
        self.works = works
        self.because = because
        self.checkedAt = checkedAt
        self.chosen = chosen
        self.install = install
    }
}

/// Where a session's agent runs, for bringing its window forward.
public struct DaemonLocation: Decodable, Equatable {
    public let sessionId: String
    public let agent: String
    public let alive: Bool
    public let app: String?
    public let appPath: String?
    public let tty: String?
    public let cwd: String?
}

public struct DaemonResponse: Decodable, Equatable {
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
    /// On sessions-list: the sessions lately, most recently active first.
    public let sessions: [SessionCard]?
    /// On voice-agents and choose-voice-agent: every agent the voice knows, preferred first.
    public let voiceAgents: [VoiceAgentStatus]?
    public let error: String?
}

/// What a confirmation signs, byte for byte what the runtime's `confirmationMessage` builds.
public func confirmationMessage(subject: String, answer: String) -> String {
    "memnox-confirm:v1:\(subject):\(answer)"
}

public enum ProtocolError: Error, Equatable {
    case unreadable(String)
    case refused(String)
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
