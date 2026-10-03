import Foundation

/// What a session shows a person at a glance, decided once so the switcher and the live window agree.
public enum SessionStatus: Equatable, Sendable {
    case paused
    case needsYou
    case thinking
    case working
    case waitingOnYou
    case ended
    case quiet

    /// The first that holds wins, because a pause or a question for the person matters more than activity.
    public init(state: SessionState?, thinking: Bool, paused: Bool = false, waitingOnYou: Int = 0) {
        if paused || state == .paused {
            self = .paused
        } else if waitingOnYou > 0 {
            self = .needsYou
        } else if thinking {
            self = .thinking
        } else {
            switch state {
            case .working: self = .working
            case .open: self = .waitingOnYou
            case .ended: self = .ended
            case .idle, .quiet, .paused, nil: self = .quiet
            }
        }
    }

    /// The words on the session's badge.
    public var label: String {
        switch self {
        case .paused: "Paused"
        case .needsYou: "Needs you"
        case .thinking: "Thinking"
        case .working: "Working"
        case .waitingOnYou: "Waiting on you"
        case .ended: "Ended"
        case .quiet: "Quiet"
        }
    }

    /// Whether the agent is busy right now, which is what makes a card glow.
    public var isActive: Bool { self == .working || self == .thinking }
}

extension SessionCard {
    public var status: SessionStatus { SessionStatus(state: sessionState, thinking: thinking) }
}

extension SessionView {
    public var status: SessionStatus {
        SessionStatus(state: sessionState, thinking: thinking, paused: paused != nil, waitingOnYou: waitingOnYou)
    }
}
