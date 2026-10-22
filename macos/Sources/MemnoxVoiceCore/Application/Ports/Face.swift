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
    /// A proposed rule with the places it could hold, for the person to pick one and sign.
    func rule(subject: String, _ rule: RuleDraft)
    /// Something about to go out in the person's name in one of their tools, which only a signed Send lets go.
    func work(subject: String, _ draft: WorkDraft)
    /// The tools the person asked for and has not signed in to, for their icons in the notch.
    func signIns(_ tools: [ToolSignIn])
    /// A sign in finished, or never did: whose account it reached, and whether to carry on with what was asked.
    func signedIn(_ notice: SignedInNotice)
    /// A short gesture the orb makes at an answer or at something an agent did.
    func react(_ reaction: Reaction)
    /// What was read back after an action, shown beside the answer as the evidence for it.
    func proof(_ proof: Proof)
    /// Something the turn did in the world, kept for the side panel's list of what was done.
    func acted(_ action: TakenAction)
    /// A phone is driving this Mac until the grant's time, or nil once it stopped, so somebody at the Mac always knows.
    func driven(_ grant: DriveGrant?)
    /// A phone's turn as it stands, shown without a sound since the phone speaks its own answer.
    func phone(_ turn: PhoneExchange)
    /// The phone that took the voice, or nil once it gave it back, so somebody at the Mac knows why it stays silent.
    func voiceOn(_ phone: PhoneVoice?)
}

extension Face {
    public func asked(_ words: String) {}
    public func replying(_ text: String) {}
    public func replied(failure: String?) {}
    public func draft(subject: String, _ draft: MailDraft) {}
    public func rule(subject: String, _ rule: RuleDraft) {}
    public func work(subject: String, _ draft: WorkDraft) {}
    public func signIns(_ tools: [ToolSignIn]) {}
    public func signedIn(_ notice: SignedInNotice) {}
    public func react(_ reaction: Reaction) {}
    public func proof(_ proof: Proof) {}
    public func acted(_ action: TakenAction) {}
    public func driven(_ grant: DriveGrant?) {}
    public func phone(_ turn: PhoneExchange) {}
    public func voiceOn(_ phone: PhoneVoice?) {}
}
