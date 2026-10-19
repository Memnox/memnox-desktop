import Foundation

/// What this Mac may ask of a machine it reaches over the relay, mirrored from the runtime's remote
/// allowlist in packages/core/src/gate/capabilities.ts. Anything else stays on this Mac's own daemon,
/// since a server refuses it anyway and asking only spends a round trip to hear no.
public enum RemoteReach {
    public static let methods: Set<DaemonMethod> = [
        .ping, .sessionsList, .sessionView, .waiting, .subscribe, .trace, .voiceAgents, .voiceChoice, .filesList, .home, .connectionsList,
        .toolkitsSearch, .connectionsSignIn, .connectionsSignOut,
        .ask, .cancel, .warm, .brief, .speak, .handOver, .drive, .confirm,
    ]

    /// Whether a request may go to another machine: on the list, and a voice choice only when it asks rather than sets.
    public static func allows(_ request: DaemonRequest) -> Bool {
        guard let method = DaemonMethod(rawValue: request.method), methods.contains(method) else { return false }
        // Setting the voice is the machine's own; from afar it may only be asked which one is set.
        if method == .voiceChoice { return request.voice == nil }
        return true
    }
}
