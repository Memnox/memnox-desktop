import Foundation

/// A short gesture the orb makes at something that happened, read from the daemon's facts and never
/// from words, so it celebrates only work the ledger shows was checked.
public enum Reaction: Equatable, Sendable {
    /// Particles fling out and settle: a turn ended with its tests passing after the last change.
    case burst
    /// A jitter that drains the colour for a moment: tests failed, a session paused, two agents met on one file.
    case stumble
    /// A small swell: a turn ended or work shipped, with nothing proving it either way.
    case settle
    /// A ring out from the orb: the person let something happen.
    case allowed
    /// The orb pulls in: the person said no.
    case refused
    /// The orb looks aside: the screen was captured because the brain asked to look.
    case glance
}

/// What the orb does at an event from the daemon; nil for one that only the voice or a card answers.
public func reaction(to event: DaemonEvent) -> Reaction? {
    switch event.eventKind {
    case .paused:
        return .stumble
    case .notice:
        switch event.noticeKind {
        case .finished:
            switch event.turnTests {
            case .passed: return .burst
            case .failed: return .stumble
            // A pass followed by more writes, or no run at all, proves nothing, so it is only marked.
            case .stale, .untested, nil: return .settle
            }
        case .committed, .pushed: return .settle
        case .collision, .gone, .signInStalled: return .stumble
        case .signedIn: return .settle
        // Seen as it comes and goes, so a session appearing or closing is never only in a list.
        case .started, .closed: return .settle
        case .watched, .wouldHave, .question, .asking, .message, .ended, nil: return nil
        }
    case .held, .settled, .proposal, .show, nil:
        return nil
    }
}
