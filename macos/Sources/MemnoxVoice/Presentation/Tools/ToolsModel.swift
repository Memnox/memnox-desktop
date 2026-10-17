import MemnoxVoiceCore
import SwiftUI

/// The person's agents on this Mac and their own connected apps, read from the daemon once for the menu, the notch
/// and Settings, so all three always show the same list.
@MainActor
final class ToolsModel: ObservableObject {
    /// The agents installed on this Mac, the voice's own first.
    @Published private(set) var agents: [VoiceAgentStatus] = []
    @Published private(set) var connections: [ToolConnection] = []
    /// Why the connected apps could not be read, said where they would be.
    @Published private(set) var connectionsNote: String?
    /// True until the first read lands, so an empty list is not mistaken for none.
    @Published private(set) var loading = true

    private let readAgents: () async -> VoiceAgentsAnswer
    private let readConnections: () async -> ConnectionsAnswer
    private var reading: Task<Void, Never>?

    /// Said when the daemon does not answer at all.
    private static let unreachable = "Memnox is not running"

    init(
        readAgents: @escaping () async -> VoiceAgentsAnswer = { .unreachable },
        readConnections: @escaping () async -> ConnectionsAnswer = { .unreachable }
    ) {
        self.readAgents = readAgents
        self.readConnections = readConnections
    }

    /// Reads both lists again; a read already under way is the one that answers.
    func refresh() {
        guard reading == nil else { return }
        reading = Task { [weak self] in
            guard let self else { return }
            async let agents = readAgents()
            async let connections = readConnections()
            apply(await agents)
            apply(await connections)
            loading = false
            reading = nil
        }
    }

    var connectedCount: Int { connections.filter(\.connected).count }

    private func apply(_ answer: VoiceAgentsAnswer) {
        guard case .agents(let all) = answer else { return }
        agents = all.filter(\.installed).sorted { $0.chosen && !$1.chosen }
    }

    private func apply(_ answer: ConnectionsAnswer) {
        switch answer {
        case .connections(let all):
            connections = all
            connectionsNote = nil
        case .refused(let why):
            connections = []
            connectionsNote = why
        case .unreachable:
            connectionsNote = Self.unreachable
        }
    }
}

/// What a tool's tile says under its name.
enum ToolStatus {
    static func agent(_ agent: VoiceAgentStatus) -> String {
        if agent.chosen { return "Voice" }
        if agent.works == false { return "Not the voice yet" }
        return "Ready"
    }

    static func connection(_ connection: ToolConnection) -> String {
        connection.connected ? "Connected" : "Sign in again"
    }
}
