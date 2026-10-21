/// A short sound at a moment the person should notice without looking, the way a Mac
/// confirms a sent message: what happened is heard before a word of it is said.
public enum Cue: String, Sendable, CaseIterable {
    /// The orb opened and the microphone is on.
    case listening
    /// What they said went to the brain.
    case sent
    /// An agent is waiting on them.
    case held
    /// An allow was signed and taken.
    case allowed
    /// Something was left as it was.
    case declined
    /// Words were typed in or a session was started, as asked.
    case done
    /// An agent finished its work, heard by somebody who is not looking at it.
    case finished
    /// Memnox could not be reached, or the turn broke.
    case failed
    /// The question was answered somewhere else.
    case settled
    /// The orb closed.
    case closed
}

/// Plays a cue; the app decides the sound and whether the person turned them off.
public protocol Chimes: AnyObject {
    func play(_ cue: Cue)
}
