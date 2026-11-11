import Foundation

/// What a session shows a person at a glance, decided once so the switcher, the live window, Sessions and the side
/// panel agree, in the five statuses every Memnox surface uses (`shared/ux/contract.json`).
public enum SessionStatus: String, CaseIterable, Sendable {
    case needsYou = "needs-you"
    case stopped
    case working
    case finished
    case idle

    /// The first that holds wins, because a pause or a question for the person matters more than activity.
    public init(state: SessionState?, thinking: Bool, paused: Bool = false, waitingOnYou: Int = 0) {
        if paused || state == .paused {
            self = .stopped
        } else if waitingOnYou > 0 {
            self = .needsYou
        } else if thinking {
            self = .working
        } else {
            switch state {
            case .working: self = .working
            // Its turn is over and it handed back, which is news the person has not read yet.
            case .open: self = .finished
            case .ended, .idle, .quiet, .paused, nil: self = .idle
            }
        }
    }

    /// The words on the session's badge.
    public var label: String {
        switch self {
        case .needsYou: "Needs you"
        case .stopped: "Stopped"
        case .working: "Working"
        case .finished: "Finished"
        case .idle: "Idle"
        }
    }

    /// Whether the agent is busy right now, which is what makes a card glow.
    public var isActive: Bool { self == .working }
}

extension SessionCard {
    public var status: SessionStatus { SessionStatus(state: sessionState, thinking: thinking) }
}

extension SessionView {
    public var status: SessionStatus {
        SessionStatus(state: sessionState, thinking: thinking, paused: paused != nil, waitingOnYou: waitingOnYou)
    }
}
