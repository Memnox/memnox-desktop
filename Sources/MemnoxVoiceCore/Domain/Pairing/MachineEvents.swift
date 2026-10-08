import Foundation

/// Which events reach the island from each machine. The chosen one is heard in full, since the voice and
/// the session views talk to it; the others still bring what waits on the person, so a held call is never
/// missed because another machine was picked.
public enum MachineEvents {
    /// Whether an event from a machine is delivered: all of it from the chosen one, and from the rest only
    /// what waits on the person and the word that it settled.
    public static func delivers(_ event: DaemonEvent, chosen: Bool, thisMac: Bool) -> Bool {
        if chosen { return true }
        switch event.eventKind {
        case .held, .settled: return true
        // This Mac's own agents ask and tell here whatever the voice talks to.
        case .proposal, .notice: return thisMac || event.awaitsAnswer
        case .paused, .show, nil: return false
        }
    }
}
