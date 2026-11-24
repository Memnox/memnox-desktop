import Foundation

/// What the agents list says about a profile: who answers for it and how Memnox reaches its agents.
/// A profile with no agent behind it says so and shows no activity and no numbers.
public enum AgentProfileLines {
    /// The line under the name is whether Memnox can stop it or only watch it, never a purpose, because the person gives purpose.
    public static func summary(_ profile: ProfileView) -> String {
        guard profile.hasAgent else { return noAgent }
        return CapabilityLevelLines.canStop(profile.levels) ? "Memnox can stop it." : "Memnox can only watch it."
    }

    public static func responsible(_ profile: ProfileView) -> String? {
        AgentWorkLines.filled(profile.responsiblePerson).map { "Answers to \($0)" }
    }

    /// The agents under a kept profile first, then the defaults, then the profiles with nobody behind them, each by name.
    public static func ordered(_ profiles: [ProfileView]) -> [ProfileView] {
        func rank(_ profile: ProfileView) -> Int {
            if profile.isDefault { return 1 }
            return profile.hasAgent ? 0 : 2
        }
        return profiles.sorted { (rank($0), $0.name.lowercased()) < (rank($1), $1.name.lowercased()) }
    }

    /// The connections a card shows: every one not gone, then the gone ones, which say they are not found any more.
    public static func shownConnections(_ profile: ProfileView) -> [AgentConnection] {
        profile.connections.filter { $0.connectionStatus != .gone } + profile.connections.filter { $0.connectionStatus == .gone }
    }

    /// Whether any of its agents is working now.
    public static func working(_ profile: ProfileView) -> Bool {
        profile.connections.contains { $0.connectionStatus == .live }
    }

    public static let noAgent = "No agent behind it yet"
}
