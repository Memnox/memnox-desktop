import Foundation

/// Where the confirmation key stands with the daemon.
public enum KeyStatus: Equatable {
    case registered
    /// Somebody else's key is trusted, so nothing can be confirmed from here.
    case anotherKey
    case unreachable
    /// The daemon answers but does not know voice: an older Memnox than this app.
    case tooOld
}

/// Whether the daemon can hold a conversation, which setup checks before saying it is ready.
public enum DaemonVoice: Equatable {
    case ready
    case tooOld
    case unreachable
}

/// What the daemon said about the agents the voice can think with.
public enum VoiceAgentsAnswer: Equatable, Sendable {
    case agents([VoiceAgentStatus])
    /// It answered no, with why: an agent not on this Mac, or a daemon that knows no voice agents.
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
