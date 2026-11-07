import Foundation

/// A repository an agent has worked in, as the sessions tell it.
public struct SeenWorkspace: Equatable, Identifiable, Sendable {
    public struct Agent: Equatable, Sendable {
        public let kind: String
        public let name: String
    }

    public let path: String
    public let name: String
    /// Each agent that worked here once, in the order they were met.
    public let agents: [Agent]
    public let sessions: Int
    public let lastActiveAt: String?
    /// "2 h ago", taken at the moment the list was made.
    public let lastActive: String?

    public var id: String { path }
}

public enum SeenWorkspaces {
    /// Sessions grouped by the repository they ran in, newest first; a session with none belongs to no workspace.
    public static func from(_ cards: [SessionCard], now: Date) -> [SeenWorkspace] {
        var order: [String] = []
        var byPath: [String: [SessionCard]] = [:]
        for card in cards {
            guard let path = card.repository, !path.isEmpty else { continue }
            if byPath[path] == nil { order.append(path) }
            byPath[path, default: []].append(card)
        }
        let seen = order.map { workspace($0, cards: byPath[$0] ?? [], now: now) }
        // Newest first, and two equally recent keep the order they were met in.
        return seen.enumerated().sorted { left, right in
            let a = left.element.lastActiveAt ?? ""
            let b = right.element.lastActiveAt ?? ""
            return a == b ? left.offset < right.offset : a > b
        }.map(\.element)
    }

    private static func workspace(_ path: String, cards: [SessionCard], now: Date) -> SeenWorkspace {
        var kinds: [String] = []
        var names: [String: String] = [:]
        for card in cards {
            let kind = card.agent ?? card.agentName
            if names[kind] == nil { kinds.append(kind) }
            names[kind] = card.agentName
        }
        // ISO 8601 moments in one zone sort as text, which is how the runtime writes them.
        let lastActiveAt = cards.compactMap(\.lastActive).max()
        return SeenWorkspace(
            path: path,
            name: SessionReading.repository(path) ?? path,
            agents: kinds.map { SeenWorkspace.Agent(kind: $0, name: names[$0] ?? $0) },
            sessions: cards.count,
            lastActiveAt: lastActiveAt,
            lastActive: SessionText.ago(lastActiveAt, now: now)
        )
    }
}
