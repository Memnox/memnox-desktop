import Foundation

/// Where an item on Today stands, as its pill says it.
public enum TodayState: String, CaseIterable, Sendable {
    case needsYou
    case stopped
    case working
    case upNext
    case done

    public var label: String {
        switch self {
        case .needsYou: "Needs you"
        case .stopped: "Stopped"
        case .working: "Working"
        case .upNext: "Up next"
        case .done: "Done"
        }
    }
}

/// The Overview's sections, in the order they are read.
public enum TodaySection: String, CaseIterable, Sendable {
    case needsYou
    case next
    case working

    public var title: String {
        switch self {
        case .needsYou: "Needs you, most urgent first"
        case .next: "Next"
        case .working: "Working now"
        }
    }
}

/// The tabs across Today.
public enum TodayTab: String, CaseIterable, Sendable {
    case overview
    case done
    case handoffs
    case log

    public var title: String {
        switch self {
        case .overview: "Overview"
        case .done: "Done today"
        case .handoffs: "Handoffs"
        case .log: "Log"
        }
    }
}

/// What an item came from, which decides how urgent it is and what can be done about it.
public enum TodayKind: Equatable, Sendable {
    /// A held call, its agent stopped until somebody answers. `team` for one the workspace routed from a teammate.
    case held(team: Bool)
    /// The rules refused something today, as many times as `count` says.
    case refused(count: Int)
    /// Something ran and failed, with the exit code of its latest run.
    case failed(exit: Int, count: Int)
    /// A person paused the session.
    case paused
    /// The session handed back and waits on the person.
    case handedBack
    /// A step only the person can take, word for word as the runtime says it.
    case owed
    /// An agent found here that runs outside Memnox.
    case unprotected
    /// The one action said yes to often enough, and never refused, to run on its own.
    case handOver
    case working
    case done
}

/// What a choice in the panel does. Every answer to a held call goes through the island's own path.
public enum TodayAction: Equatable, Sendable {
    case answer(HoldAnswer)
    case handOver
    case protect
    case openConversation
    case findInApp
    case openActivity
}

/// One choice in the panel, pressed by its letter.
public struct TodayChoice: Equatable, Sendable {
    public let key: Character
    public let title: String
    public let action: TodayAction
    /// Marked only where the runtime or the agent recommended it; this app never picks one itself.
    public let recommended: Bool
}

/// One line of Today: what it is, who it is from, since when, and where it stands.
public struct TodayItem: Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: TodayKind
    public let title: String
    /// One muted line under the title: why it asks, where it runs, or what the rule said.
    public let detail: String?
    /// What the runtime or the agent recommends, word for word; nil where neither said anything.
    public let recommendation: String?
    public let agent: String?
    public let agentName: String
    public let since: Date?
    public let sessionId: String?
    public let state: TodayState
    public let choices: [TodayChoice]

    public init(id: String, kind: TodayKind, title: String, detail: String? = nil, recommendation: String? = nil,
                agent: String? = nil, agentName: String, since: Date? = nil, sessionId: String? = nil,
                state: TodayState, choices: [TodayChoice] = []) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.recommendation = recommendation
        self.agent = agent
        self.agentName = agentName
        self.since = since
        self.sessionId = sessionId
        self.state = state
        self.choices = choices
    }

    /// Lower is more urgent: what blocks an agent first, then what stopped, then what waits, then what is next.
    public var urgency: Int {
        switch kind {
        case .held, .refused: 0
        case .failed, .paused: 1
        case .handedBack: 2
        case .owed: 3
        case .unprotected: 4
        case .handOver: 5
        case .working: 6
        case .done: 7
        }
    }

    /// Whether an agent is stopped until somebody acts on it.
    public var blocksAgent: Bool { urgency == 0 }

    /// The Overview section it sits in; nil for what is only in the record.
    public var section: TodaySection? {
        switch kind {
        case .held, .refused, .failed, .paused, .handedBack: .needsYou
        case .owed, .unprotected, .handOver: .next
        case .working: .working
        case .done: nil
        }
    }
}

/// A held call as Today reads it off the island, so the core never sees the island's own card.
public struct TodayHeld: Equatable, Sendable {
    public let subject: String
    public let agent: String
    public let who: String
    public let what: String
    public let why: String?
    /// When it started waiting, as the runtime wrote it.
    public let at: String?
    public let team: Bool
    public let sessionId: String?

    public init(subject: String, agent: String, who: String, what: String, why: String? = nil, at: String? = nil,
                team: Bool = false, sessionId: String? = nil) {
        self.subject = subject
        self.agent = agent
        self.who = who
        self.what = what
        self.why = why
        self.at = at
        self.team = team
        self.sessionId = sessionId
    }
}

/// Everything Today is read from, each already held by the window.
public struct TodaySources: Equatable, Sendable {
    public var held: [TodayHeld]
    public var sessions: [SessionCard]
    public var activity: [ActivityRow]
    public var agents: [AgentStanding]
    /// What only the person can do, word for word as the home says it.
    public var owed: [String]
    public var ready: HomeReady?

    public init(held: [TodayHeld] = [], sessions: [SessionCard] = [], activity: [ActivityRow] = [],
                agents: [AgentStanding] = [], owed: [String] = [], ready: HomeReady? = nil) {
        self.held = held
        self.sessions = sessions
        self.activity = activity
        self.agents = agents
        self.owed = owed
        self.ready = ready
    }
}

public enum TodayBoard {
    /// How many of what needs the person the Overview shows before it folds the rest behind a press.
    public static let urgentShown = 5

    /// Everything on the Overview, most urgent first and the oldest first within the same urgency.
    public static func overview(_ sources: TodaySources, now: Date, calendar: Calendar = .current) -> [TodayItem] {
        let today = ofToday(sources.activity, now: now, calendar: calendar)
        let items = held(sources.held) + stopped(today) + sessions(sources.sessions) + next(sources)
        return ordered(items)
    }

    /// The urgency rule: what blocks an agent first, then age, oldest first, an item with no age after those with one.
    public static func ordered(_ items: [TodayItem]) -> [TodayItem] {
        items.enumerated().sorted { left, right in
            let a = left.element, b = right.element
            if a.urgency != b.urgency { return a.urgency < b.urgency }
            switch (a.since, b.since) {
            case let (x?, y?) where x != y: return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return left.offset < right.offset
            }
        }.map(\.element)
    }

    /// The Overview's items under their sections, an empty section dropped.
    public static func sections(_ items: [TodayItem]) -> [(section: TodaySection, items: [TodayItem])] {
        TodaySection.allCases.compactMap { section in
            let held = items.filter { $0.section == section }
            return held.isEmpty ? nil : (section, held)
        }
    }

    /// What went through today and ran, newest first.
    public static func done(_ activity: [ActivityRow], now: Date, calendar: Calendar = .current) -> [TodayItem] {
        newestFirst(ofToday(activity, now: now, calendar: calendar).filter { $0.ruleEffect == .allow && $0.failed == nil })
            .map { record($0, state: .done) }
    }

    /// What agents handed back to the person, and what the runtime offers to let run on its own.
    public static func handoffs(_ sources: TodaySources) -> [TodayItem] {
        ordered(sessions(sources.sessions).filter { $0.kind == .handedBack } + (sources.ready.map { [handOver($0)] } ?? []))
    }

    /// Every action today, newest first, each with what came of it.
    public static func log(_ activity: [ActivityRow], now: Date, calendar: Calendar = .current) -> [TodayItem] {
        newestFirst(ofToday(activity, now: now, calendar: calendar)).map { row in
            let state: TodayState
            if row.failed != nil {
                state = .stopped
            } else {
                switch row.ruleEffect {
                case .deny: state = .stopped
                case .ask: state = row.answeredBy == nil ? .needsYou : .done
                case .allow, nil: state = .done
                }
            }
            return record(row, state: state)
        }
    }

    /// The item `offset` places from the one open, stopping at either end; the first when none is open.
    public static func step(from id: String?, by offset: Int, in items: [TodayItem]) -> String? {
        guard let last = items.indices.last else { return nil }
        guard let id, let at = items.firstIndex(where: { $0.id == id }) else { return items.first?.id }
        return items[min(max(at + offset, 0), last)].id
    }

    /// The choice a letter presses, in either case.
    public static func choice(for key: Character, in item: TodayItem) -> TodayChoice? {
        let pressed = Character(key.uppercased())
        return item.choices.first { $0.key == pressed }
    }

    /// The answers a held call takes, as the island offers them. A teammate's call has no rule here to relax, so from
    /// now on is left off it, since the runtime would take it as once.
    public static func heldChoices(team: Bool) -> [TodayChoice] {
        var answers: [(String, HoldAnswer)] = [("Allow once", .once), ("Allow this session", .session)]
        if !team { answers.append(("Allow from now on", .always)) }
        answers.append(("Deny", .deny))
        return lettered(answers.map { ($0.0, TodayAction.answer($0.1), false) })
    }

    // MARK: Reading each source

    private static func held(_ calls: [TodayHeld]) -> [TodayItem] {
        calls.map { call in
            TodayItem(id: "held:\(call.subject)", kind: .held(team: call.team), title: call.what, detail: call.why,
                      agent: call.agent, agentName: call.who, since: call.at.flatMap(moment), sessionId: call.sessionId,
                      state: .needsYou, choices: heldChoices(team: call.team))
        }
    }

    /// Refusals and failures, the same action by the same agent folded into one line with its count.
    private static func stopped(_ rows: [ActivityRow]) -> [TodayItem] {
        var groups: [(key: String, rows: [ActivityRow])] = []
        for row in rows where row.ruleEffect == .deny || row.failed != nil {
            let key = [row.ruleEffect == .deny ? "refused" : "failed", row.agent, row.operation, row.target ?? ""].joined(separator: "\u{0}")
            if let at = groups.firstIndex(where: { $0.key == key }) { groups[at].rows.append(row) } else { groups.append((key, [row])) }
        }
        return groups.compactMap { group in
            guard let latest = newestFirst(group.rows).first else { return nil }
            let refused = latest.ruleEffect == .deny
            let kind: TodayKind = refused ? .refused(count: group.rows.count) : .failed(exit: latest.failed ?? 0, count: group.rows.count)
            let reason = refused ? latest.rule.map { "Refused by \($0)" } ?? latest.reason : "Failed, exit \(latest.failed ?? 0)"
            let times = group.rows.count > 1 ? "\(reason), \(group.rows.count) times today" : reason
            return TodayItem(id: "stopped:\(latest.id)", kind: kind,
                             title: StudioLines.activityLine(operation: latest.operation, target: latest.target), detail: times,
                             agent: latest.agent, agentName: latest.agentName, since: moment(latest.at), sessionId: latest.session,
                             state: .stopped, choices: lettered([("See why in Activity", .openActivity, false)]))
        }
    }

    private static func sessions(_ cards: [SessionCard]) -> [TodayItem] {
        cards.compactMap { card in
            let kind: TodayKind
            let state: TodayState
            switch card.status {
            case .paused: (kind, state) = (.paused, .stopped)
            case .waitingOnYou, .needsYou: (kind, state) = (.handedBack, .needsYou)
            case .working, .thinking: (kind, state) = (.working, .working)
            case .quiet, .ended: return nil
            }
            var ways: [(String, TodayAction, Bool)] = [("Open conversation", .openConversation, false)]
            if card.host?.app != nil { ways.append(("Find in app", .findInApp, false)) }
            let detail = kind == .paused ? "Paused, so nothing it asks for runs" : SessionReading.repository(card.repository)
            return TodayItem(id: "session:\(card.sessionId)", kind: kind, title: card.title, detail: detail, agent: card.agent,
                             agentName: card.agentName, since: card.lastActive.flatMap(moment), sessionId: card.sessionId,
                             state: state, choices: lettered(ways))
        }
    }

    private static func next(_ sources: TodaySources) -> [TodayItem] {
        let owed = sources.owed.compactMap(SessionReading.readable).map { line in
            TodayItem(id: "owed:\(line)", kind: .owed, title: line, detail: "Only you can do this", agentName: "Memnox", state: .upNext)
        }
        let outside = sources.agents.filter { $0.agentStatus == .unprotected }.map { agent in
            TodayItem(id: "unprotected:\(agent.kind)", kind: .unprotected, title: "Put \(agent.name) under Memnox",
                      detail: "It runs outside Memnox, so nothing it does is ruled on", agent: agent.kind, agentName: agent.name,
                      state: .upNext, choices: lettered([("Protect it", .protect, false)]))
        }
        return owed + outside + (sources.ready.map { [handOver($0)] } ?? [])
    }

    /// The runtime's own suggestion, so its because is a recommendation and Hand over the choice it recommends.
    private static func handOver(_ ready: HomeReady) -> TodayItem {
        TodayItem(id: "ready:\(ready.action)", kind: .handOver, title: HomeLines.ready(ready), recommendation: ready.because,
                  agentName: ready.agentName ?? "Memnox", state: .upNext,
                  choices: lettered([("Hand it over", .handOver, true)]))
    }

    private static func record(_ row: ActivityRow, state: TodayState) -> TodayItem {
        let detail = [StudioLines.verdict(row.effect), row.rule, StudioLines.answeredWords(by: row.answeredBy, how: row.answeredHow)]
            .compactMap { $0 }.joined(separator: SessionText.separator)
        return TodayItem(id: "row:\(row.id)", kind: .done, title: StudioLines.activityLine(operation: row.operation, target: row.target),
                         detail: detail, agent: row.agent, agentName: row.agentName, since: moment(row.at), sessionId: row.session,
                         state: state, choices: lettered([("See why in Activity", .openActivity, false)]))
    }

    // MARK: Helpers

    private static let letters = Array("ABCDEFGHIJ")

    private static func lettered(_ choices: [(String, TodayAction, Bool)]) -> [TodayChoice] {
        zip(letters, choices).map { TodayChoice(key: $0, title: $1.0, action: $1.1, recommended: $1.2) }
    }

    /// Rows since local midnight, since a page of the ledger may reach further back.
    public static func ofToday(_ rows: [ActivityRow], now: Date, calendar: Calendar) -> [ActivityRow] {
        let start = calendar.startOfDay(for: now)
        return rows.filter { row in moment(row.at).map { $0 >= start } ?? false }
    }

    private static func newestFirst(_ rows: [ActivityRow]) -> [ActivityRow] {
        rows.sorted { (moment($0.at) ?? .distantPast) > (moment($1.at) ?? .distantPast) }
    }

    /// Reads a moment with or without fractional seconds, since the runtime writes both.
    static func moment(_ iso: String) -> Date? {
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return precise.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }
}
