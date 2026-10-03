import Foundation

extension NoticeKind {
    /// Said whatever the speak up setting, because the person asked for it or somebody waits on them.
    public var isAlwaysSaid: Bool {
        switch self {
        case .watched, .question, .collision: true
        case .finished, .committed, .pushed, .wouldHave, .ended: false
        }
    }

    /// Keeps the microphone open once said, because only the person can answer it.
    public var awaitsAnswer: Bool {
        switch self {
        case .question, .collision: true
        case .finished, .committed, .pushed, .watched, .wouldHave, .ended: false
        }
    }
}

extension DaemonEvent {
    /// Whether to say this out loud: everything but a notice is, and a notice only when it must be or the person asked for news.
    public func isSaid(speakUp: Bool) -> Bool {
        guard eventKind == .notice else { return true }
        return speakUp || (noticeKind?.isAlwaysSaid ?? false)
    }

    /// Whether the conversation stays open once this is said, because it waits on the person rather than only telling them.
    public var awaitsAnswer: Bool {
        eventKind == .held || (noticeKind?.awaitsAnswer ?? false)
    }
}
