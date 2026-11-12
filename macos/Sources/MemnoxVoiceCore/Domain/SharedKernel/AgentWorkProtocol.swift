import Foundation

// Agent work on the wire, mirrored from the runtime's daemon/work.ts and coordination/agent-work.ts. The issue lives
// in its tracker and only a reference to it is kept; a person starts, stops and closes work and answers a handoff,
// each an unsigned steer, and only the daemon decides whether one is allowed.

/// Where the issue lives.
public enum Tracker: String, CaseIterable, Sendable {
    case linear
    case jira
    case github
    case asana
}

public enum WorkStatus: String, CaseIterable, Sendable {
    case active
    case blocked
    case handoffRequested = "handoff_requested"
    /// The agent says it is done; only a person closes it.
    case doneClaimed = "done_claimed"
    case done
    case stopped
}

/// A person's answer to a handoff, as handoff-answer takes it.
public enum HandoffAnswerWord: String, CaseIterable, Sendable {
    case accept
    case decline
}

public enum HandoffState: String, CaseIterable, Sendable {
    case requested
    case accepted
    case declined
}

/// The tracker's own issue, named and never duplicated: its title is a label, not a copy.
public struct ExternalTaskRef: Decodable, Equatable, Sendable {
    public let source: String
    /// `LIN-123`, `PAY-42`, `acme/api#17` or an Asana task id.
    public let externalId: String
    public let url: String?
    public let title: String?

    public init(source: String, externalId: String, url: String? = nil, title: String? = nil) {
        self.source = source
        self.externalId = externalId
        self.url = url
        self.title = title
    }

    public var tracker: Tracker? { Tracker(rawValue: source) }
}

/// Context that moves by reference, each opened through the reader's own clearance.
public struct WorkRef: Decodable, Equatable, Sendable {
    public let kind: String
    public let id: String

    public init(kind: String, id: String) {
        self.kind = kind
        self.id = id
    }
}

/// One line an agent said about its work.
public struct WorkProgress: Decodable, Equatable, Sendable {
    public let at: String
    /// The session or agent that said it, never a person.
    public let by: String
    public let note: String
    public let state: String?
    public let refs: [WorkRef]

    public init(at: String, by: String, note: String, state: String? = nil, refs: [WorkRef] = []) {
        self.at = at
        self.by = by
        self.note = note
        self.state = state
        self.refs = refs
    }
}

/// One side of a handoff: an agent by its profile, or a person.
public struct HandoffParty: Decodable, Equatable, Sendable {
    public let profileId: String?
    public let person: String?

    public init(profileId: String? = nil, person: String? = nil) {
        self.profileId = profileId
        self.person = person
    }
}

public struct WorkHandoff: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let from: HandoffParty
    public let to: HandoffParty
    public let reason: String
    public let refs: [WorkRef]
    public let state: String
    public let requestedAt: String
    /// The person who answered, and only a person ever does.
    public let decidedBy: String?
    public let decidedAt: String?

    public init(id: String, from: HandoffParty, to: HandoffParty, reason: String, refs: [WorkRef] = [], state: String,
                requestedAt: String, decidedBy: String? = nil, decidedAt: String? = nil) {
        self.id = id
        self.from = from
        self.to = to
        self.reason = reason
        self.refs = refs
        self.state = state
        self.requestedAt = requestedAt
        self.decidedBy = decidedBy
        self.decidedAt = decidedAt
    }

    public var handoffState: HandoffState? { HandoffState(rawValue: state) }
}

/// An agent carrying a piece of work a person pointed it at.
public struct AgentWork: Decodable, Equatable, Identifiable, Sendable {
    /// `agw_` and a uuid.
    public let id: String
    public let profileId: String
    /// Who answers for this work: asks go to them, and the agent never holds their authority.
    public let responsiblePerson: String
    public let assignedBy: String?
    public let target: ExternalTaskRef
    /// The repository it is scoped to, absolute.
    public let projectRoot: String?
    public let sessions: [String]
    /// How many agents have carried it: one at the start, one more per accepted handoff.
    public let attempts: Int
    public let status: String
    public let progress: [WorkProgress]
    public let handoffs: [WorkHandoff]
    public let createdAt: String
    public let updatedAt: String

    public init(id: String, profileId: String, responsiblePerson: String, assignedBy: String? = nil, target: ExternalTaskRef,
                projectRoot: String? = nil, sessions: [String] = [], attempts: Int = 1, status: String,
                progress: [WorkProgress] = [], handoffs: [WorkHandoff] = [], createdAt: String, updatedAt: String) {
        self.id = id
        self.profileId = profileId
        self.responsiblePerson = responsiblePerson
        self.assignedBy = assignedBy
        self.target = target
        self.projectRoot = projectRoot
        self.sessions = sessions
        self.attempts = attempts
        self.status = status
        self.progress = progress
        self.handoffs = handoffs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var workStatus: WorkStatus? { WorkStatus(rawValue: status) }
    /// The handoff waiting on a person, of which there is at most one.
    public var waitingHandoff: WorkHandoff? { handoffs.first { $0.handoffState == .requested } }
    public var latestProgress: WorkProgress? { progress.last }
}
