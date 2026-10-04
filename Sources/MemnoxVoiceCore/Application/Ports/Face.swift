import Foundation

/// The orb and the pill, told what to show.
public protocol Face: AnyObject {
    func show(_ state: VoiceState, caption: String)
    /// What the person's turn sent to their brain, whole, for the question above the answer.
    func asked(_ words: String)
    /// More of the reply as written, markdown and all, since the notch lays it out rather than reading it.
    func replying(_ text: String)
    /// The reply is over, so the answer can be kept; the failure says why none came, when none did.
    func replied(failure: String?)
    /// A drafted message to put in front of the person, which only a signed Send lets go.
    func draft(subject: String, _ draft: MailDraft)
}

extension Face {
    public func asked(_ words: String) {}
    public func replying(_ text: String) {}
    public func replied(failure: String?) {}
    public func draft(subject: String, _ draft: MailDraft) {}
    /// What the person's turn sent to their brain, whole, for the question above the answer.
    func asked(_ words: String)
    /// More of the reply as written, markdown and all, since the notch lays it out rather than reading it.
    func replying(_ text: String)
    /// The reply is over, so the answer can be kept; the failure says why none came, when none did.
    func replied(failure: String?)
}

extension Face {
    public func asked(_ words: String) {}
    public func replying(_ text: String) {}
    public func replied(failure: String?) {}
}
