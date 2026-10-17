import Foundation

/// Whether a line is the last the daemon sends for a request. Over the socket a closed connection
/// said so; in the tunnel every request shares one session, so the method decides.
public func isLastLine(_ response: DaemonResponse, for method: String) -> Bool {
    switch DaemonMethod(rawValue: method) {
    case .subscribe, .pairPending:
        // Events stream until the caller stops listening.
        return false
    case .ask:
        // A turn ends on its last chunk; an answer with no chunk is a refusal or an error, which ends it too.
        guard let chunk = response.chunk else { return true }
        return chunk.endsTurn
    case .speak:
        // A sentence's audio comes in pieces until the one marked last; an answer with no audio is a refusal, which ends it too.
        guard let audio = response.audio else { return true }
        return audio.last
    default:
        return true
    }
}
