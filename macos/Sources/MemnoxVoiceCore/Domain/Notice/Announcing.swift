import Foundation

extension NoticeKind {
    /// Said whatever the speak up setting, because the person asked for it or somebody waits on them.
    public var isAlwaysSaid: Bool {
        switch self {
        case .watched, .question, .asking, .collision, .message, .gone, .signedIn, .signInStalled: true
        case .finished, .committed, .pushed, .wouldHave, .ended, .started, .closed: false
        }
    }

    /// Keeps the microphone open once said, because only the person can answer it.
    public var awaitsAnswer: Bool {
        switch self {
        case .question, .asking, .collision, .message: true
        case .finished, .committed, .pushed, .watched, .wouldHave, .ended, .started, .closed, .gone, .signedIn, .signInStalled: false
        }
    }
}

extension DaemonEvent {
    /// Whether to say this out loud: everything but a notice is, and a notice only when it must be or the person asked for news.
    /// Anything a phone holds or asked for is never said here, since its words go back to that phone.
    public func isSaid(speakUp: Bool) -> Bool {
        if quietOnMac || isShownOnly { return false }
        guard eventKind == .notice else { return true }
        return speakUp || (noticeKind?.isAlwaysSaid ?? false)
    }

    /// A drive grant, a phone's turn or the voice moving to a phone: put on the island at once and never said.
    public var isShownOnly: Bool {
        drivenBy != nil || phoneTurn != nil || voiceOn != nil
    }

    /// Whether the conversation stays open once this is said, because it waits on the person rather than only telling them.
    /// A phone holding the voice hears the answer itself, so the Mac never opens its microphone for it.
    public var awaitsAnswer: Bool {
        !quietOnMac && (eventKind == .held || (noticeKind?.awaitsAnswer ?? false))
    }
}
