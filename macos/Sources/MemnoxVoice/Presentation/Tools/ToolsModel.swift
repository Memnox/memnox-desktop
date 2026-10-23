import MemnoxVoiceCore
import SwiftUI

/// The person's agents on this Mac and their own connected apps, read from the daemon once for the menu, the notch
/// and Settings, so all three always show the same list.
@MainActor
final class ToolsModel: ObservableObject {
    /// The agents installed on this Mac, the voice's own first.
    @Published private(set) var agents: [VoiceAgentStatus] = []
    @Published private(set) var connections: [ToolConnection] = []
    /// Why the connected apps could not be read, said where they would be.
    @Published private(set) var connectionsNote: String?
    /// True until the first read lands, so an empty list is not mistaken for none.
    @Published private(set) var loading = true

    /// The daemon's own words for an add, sign in or disconnect it refused, shown on the Apps card until the next one.
    @Published private(set) var actionNote: String?
    /// The tool being signed in to or disconnected, so its row waits rather than taking a second press.
    @Published private(set) var busy: String?
    /// The tool whose sign in is open in the browser, read again until it shows up.
    @Published private(set) var waitingFor: String?

    /// The words typed in the add an app sheet and the catalogue's tools for them.
    @Published var query = ""
    @Published private(set) var found: [ToolkitSummary] = []
    @Published private(set) var searchNote: String?
    @Published private(set) var searching = false

    private let readAgents: () async -> VoiceAgentsAnswer
    private let readConnections: () async -> ConnectionsAnswer
    private let searchToolkits: (String) async -> ToolkitsAnswer
    private let signIn: (String, Bool) async -> ConnectionSignInAnswer
    private let signOut: (String) async -> ConnectionsAnswer
    private let watch: ([ToolConnection]) async -> ConnectionsAnswer
    private let open: (URL) -> Bool
    /// Makes one agent the one the voice answers through, as setup does, from its tile in the notch.
    private let chooseAgent: (String) async -> VoiceAgentsAnswer
    private var reading: Task<Void, Never>?
    private var looking: Task<Void, Never>?
    private var watching: Task<Void, Never>?
    private var connecting: Task<Void, Never>?

    /// Said when the daemon does not answer at all.
    private static let unreachable = "Memnox is not running"
    /// Long enough to let a word be finished before the catalogue is asked, short enough to feel live.
    private static let typingPause: UInt64 = 300_000_000

    init(
        readAgents: @escaping () async -> VoiceAgentsAnswer = { .unreachable },
        readConnections: @escaping () async -> ConnectionsAnswer = { .unreachable },
        searchToolkits: @escaping (String) async -> ToolkitsAnswer = { _ in .unreachable },
        signIn: @escaping (String, Bool) async -> ConnectionSignInAnswer = { _, _ in .unreachable },
        signOut: @escaping (String) async -> ConnectionsAnswer = { _ in .unreachable },
        watch: @escaping ([ToolConnection]) async -> ConnectionsAnswer = { _ in .unreachable },
        open: @escaping (URL) -> Bool = { _ in false },
        chooseAgent: @escaping (String) async -> VoiceAgentsAnswer = { _ in .unreachable }
    ) {
        self.chooseAgent = chooseAgent
        self.readAgents = readAgents
        self.readConnections = readConnections
        self.searchToolkits = searchToolkits
        self.signIn = signIn
        self.signOut = signOut
        self.watch = watch
        self.open = open
    }

    /// Asks the catalogue once typing pauses; a newer search replaces one still waiting.
    func search() {
        looking?.cancel()
        let words = query
        searching = true
        looking = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.typingPause)
            guard !Task.isCancelled, let self else { return }
            let answer = await searchToolkits(words)
            guard !Task.isCancelled else { return }
            switch answer {
            case .toolkits(let all):
                found = all
                searchNote = nil
            case .refused(let why):
                found = []
                searchNote = why
            case .unreachable:
                found = []
                searchNote = Self.unreachable
            }
            searching = false
        }
    }

    /// Starts the tool's own sign in; again opens a fresh one for a tool that already has one, to use another account.
    /// A press of Connect on any tool starts afresh, so one left unfinished in the browser never holds the others back.
    func connect(_ toolkit: String, again: Bool = false) {
        connecting?.cancel()
        actionNote = nil
        connecting = Task { [weak self] in
            guard let self else { return }
            // No Memnox account is asked for: the daemon acts for the person at this Mac, so only the tool's own sign in opens.
            busy = toolkit
            let answer = await signIn(toolkit, again)
            busy = nil
            guard !Task.isCancelled else { return }
            switch answer {
            case .started(let page):
                // The daemon opens the page itself over this Mac's socket; only a server's answer is left to open here.
                if !page.opened {
                    guard let url = URL(string: page.url), url.scheme == "https", open(url) else {
                        actionNote = "The browser would not open the \(ToolkitName.of(toolkit)) sign in"
                        return
                    }
                }
                waitUntilSignedIn(toolkit)
            case .refused(let why):
                actionNote = why
            case .unreachable:
                actionNote = Self.unreachable
            }
        }
    }

    /// The voice answers through this agent from now on; one that cannot answer says why under the tiles.
    func useForVoice(_ agent: VoiceAgentStatus) {
        guard busy == nil, !agent.chosen else { return }
        busy = agent.kind
        actionNote = nil
        Task { [weak self] in
            guard let self else { return }
            let answer = await chooseAgent(agent.kind)
            busy = nil
            apply(answer)
            if case .agents(let all) = answer, let now = all.first(where: { $0.kind == agent.kind }), !now.chosen {
                actionNote = now.because ?? "\(agent.label) could not answer just now"
            } else if case .unreachable = answer {
                actionNote = Self.unreachable
            }
        }
    }

    /// Takes the tool's sign in away and shows the list the daemon answers with.
    func disconnect(_ toolkit: String) {
        guard busy == nil else { return }
        busy = toolkit
        actionNote = nil
        Task { [weak self] in
            guard let self else { return }
            let answer = await signOut(toolkit)
            busy = nil
            if case .connections = answer { apply(answer) } else { actionNote = Self.words(answer) }
        }
    }

    /// Reads the list while the browser sign in finishes, so the tool turns up without a press of Check again.
    private func waitUntilSignedIn(_ toolkit: String) {
        watching?.cancel()
        waitingFor = toolkit
        let before = connections
        watching = Task { [weak self] in
            guard let self else { return }
            let answer = await watch(before)
            guard !Task.isCancelled else { return }
            if case .connections = answer { apply(answer) }
            waitingFor = nil
        }
    }

    private static func words(_ answer: ConnectionsAnswer) -> String {
        switch answer {
        case .refused(let why): why
        case .connections, .unreachable: unreachable
        }
    }

    /// Reads both lists again; a read already under way is the one that answers.
    func refresh() {
        guard reading == nil else { return }
        reading = Task { [weak self] in
            guard let self else { return }
            async let agents = readAgents()
            async let connections = readConnections()
            apply(await agents)
            apply(await connections)
            loading = false
            reading = nil
        }
    }

    var connectedCount: Int { connections.filter(\.connected).count }

    /// The person's own tools as the Your apps screen draws them, those on this Mac first.
    var yourApps: [YourAppCard] { YourApps.yours(connections) }

    /// The catalogue's cards for what was typed, or the featured tools where the catalogue could not be read.
    var offered: [YourAppCard] {
        YourApps.offered(found: found, searchFailed: searchNote != nil, query: query, connections: connections)
    }

    /// The featured tools not connected yet, offered with Connect, which needs no Memnox account.
    var suggested: [String] { FeaturedToolkits.suggested(excluding: connections) }

    private func apply(_ answer: VoiceAgentsAnswer) {
        guard case .agents(let all) = answer else { return }
        agents = all.filter(\.installed).sorted { $0.chosen && !$1.chosen }
    }

    private func apply(_ answer: ConnectionsAnswer) {
        switch answer {
        case .connections(let all):
            connections = all
            connectionsNote = nil
        case .refused(let why):
            connections = []
            connectionsNote = why
        case .unreachable:
            connectionsNote = Self.unreachable
        }
    }
}

/// What a tool's tile says under its name.
enum ToolStatus {
    static func agent(_ agent: VoiceAgentStatus) -> String {
        if agent.chosen { return "Voice" }
        if agent.works == false { return "Not ready" }
        return "Use for voice"
    }

    static func connection(_ connection: ToolConnection) -> String {
        if connection.isLocal { return YourAppStanding.onThisMac.line }
        return connection.connected ? "Connected" : "Not signed in"
    }
}
