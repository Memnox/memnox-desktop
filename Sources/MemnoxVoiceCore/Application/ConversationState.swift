import Foundation

/// Where the confirmation key stands with the daemon.
public enum KeyStatus: Equatable {
    case registered
    /// Somebody else's key is trusted, so nothing can be confirmed from here.
    case anotherKey
    case unreachable
    /// The daemon answers but does not know voice: an older Memnox than this app.
    case tooOld
    /// The daemon said no in its own words, shown as given rather than read as an older Memnox.
    case refused(String)
}

/// Whether the daemon can hold a conversation, which setup checks before saying it is ready.
public enum DaemonVoice: Equatable {
    case ready
    case tooOld
    case unreachable
    /// The daemon answers, but said no with a reason a person can act on, such as not listening yet.
    case refused(String)
}

/// What the daemon said about the agents the voice can think with.
public enum VoiceAgentsAnswer: Equatable, Sendable {
    case agents([VoiceAgentStatus])
    /// It answered no, with why: an agent not on this Mac, or a daemon that knows no voice agents.
    case refused(String)
    case unreachable
}

/// What became of handing the home's ready action over: a rule proposal now waiting on the person, or why not.
public enum HandOver: Equatable, Sendable {
    /// The proposal's id; it arrives on the stream and is confirmed where it holds with Touch ID, like any rule.
    case proposed(String)
    /// The daemon said no, with why: no longer ready, ever refused, or a runtime that knows no home.
    case refused(String)
    case unreachable
}

/// What the orb shows. Each state looks and moves differently, so a glance says which it is.
public enum VoiceState: Equatable, Sendable {
    case idle
    case listening
    case thinking
    case speaking
    /// Apple's Touch ID sheet is up, which is the one state that wants a hand and not a voice.
    case needsYou
}
