import Foundation

/// What the AI agents list says about a profile: the job, who answers for it, and how Memnox reaches its agents. A
/// profile with no agent behind it says so and shows no activity and no numbers.
public enum AgentProfileLines {
    /// The line under the name: the job's purpose, else what it was kept for, else that it has no job yet.
    public static func purpose(_ profile: ProfileView) -> String {
        if let purpose = AgentWorkLines.filled(profile.purpose) { return purpose }
        if let description = AgentWorkLines.filled(profile.description) { return description }
        return profile.isDefault ? "No job yet." : "No purpose written yet."
    }

    public static func responsible(_ profile: ProfileView) -> String? {
        AgentWorkLines.filled(profile.responsiblePerson).map { "Answers to \($0)" }
    }

    /// The agents with a job first, then the defaults, then the jobs with nobody behind them, each by name.
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
    public static let giveJob = "Give it a job"
}
