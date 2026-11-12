import Foundation

/// The five capability levels in plain words on every screen, with the technical names kept for Advanced. Every level
/// is the daemon's or the cloud's; nothing here works one out, so a screen can only say less than it was told.
public enum CapabilityLevelLines {
    /// What the level means for the person, as every surface words it.
    public static func plain(_ level: CapabilityLevel) -> String {
        switch level {
        case .enforced: "Memnox stops this"
        case .mediated: "Memnox checks this"
        case .advisory: "The agent asks Memnox"
        case .observed: "Memnox only sees this"
        case .noEvidence: "Outside Memnox"
        }
    }

    /// The runtime's own word, shown under Advanced.
    public static func technical(_ level: CapabilityLevel) -> String { level.rawValue }

    /// The strategy's seven capabilities as a person reads them.
    public static let capabilities: [(key: String, title: String, level: KeyPath<CapabilityLevels, CapabilityLevel>)] = [
        ("context", "What it knows", \.context),
        ("instructions", "Its instructions", \.instructions),
        ("tools", "Its tools", \.tools),
        ("activity", "What it did", \.activity),
        ("coordination", "Working beside others", \.coordination),
        ("approval", "Asking you first", \.approval),
    ]

    /// Each seam enforcement is broken down by, as a person reads it.
    public static func seamTitle(_ seam: String) -> String {
        // Memnox Cloud states enforcement as one level for everything an agent runs.
        seam == WorkspaceAgentsLines.everySeam ? "Everything it runs" : knownSeamTitle(seam)
    }

    private static func knownSeamTitle(_ seam: String) -> String {
        switch EnforcementSeam(rawValue: seam) {
        case .shell: "Commands"
        case .filesystem: "Files"
        case .git: "Git"
        case .network: "The network"
        case .browser: "The browser"
        case .mcp: "MCP tools"
        case nil: seam
        }
    }

    /// One line of the strip: a title, the level, and the technical names for Advanced.
    public struct Row: Equatable, Identifiable, Sendable {
        public let key: String
        public let title: String
        public let level: CapabilityLevel

        public var id: String { key }
        public var plain: String { CapabilityLevelLines.plain(level) }
        public var technical: String { "\(key): \(level.rawValue)" }
    }

    /// The six capabilities as the strip reads them, enforcement apart.
    public static func rows(_ levels: CapabilityLevels) -> [Row] {
        capabilities.map { Row(key: $0.key, title: $0.title, level: levels[keyPath: $0.level]) }
    }

    /// Enforcement by seam, in the runtime's seam order, then any seam this app does not know yet by name.
    public static func seamRows(_ levels: CapabilityLevels) -> [Row] {
        let known = EnforcementSeam.allCases.map(\.rawValue)
        let order = known + levels.enforcement.keys.filter { !known.contains($0) }.sorted()
        return order.compactMap { seam in
            levels.enforcement[seam].map { Row(key: "enforcement.\(seam)", title: seamTitle(seam), level: $0) }
        }
    }

    /// Weakest first, so the lower index is the one a summary must not hide.
    private static let order: [CapabilityLevel] = [.noEvidence, .observed, .advisory, .mediated, .enforced]

    public static func weaker(_ one: CapabilityLevel, _ two: CapabilityLevel) -> CapabilityLevel {
        (order.firstIndex(of: one) ?? 0) <= (order.firstIndex(of: two) ?? 0) ? one : two
    }

    /// The one level a pill wears: the weakest of the six, so a pill never says more than every line of the strip.
    public static func headline(_ levels: CapabilityLevels) -> CapabilityLevel {
        rows(levels).map(\.level).reduce(.enforced, weaker)
    }

    /// The level a connection's pill wears: its own levels, or, from a runtime that sends none, what its mediation says.
    public static func headline(_ connection: AgentConnection) -> CapabilityLevel {
        if let levels = connection.levels { return headline(levels) }
        switch connection.mediationKind {
        case .interposed: return .mediated
        case .advisory: return .advisory
        case .observed, nil: return .observed
        }
    }

    /// What a connection is, in plain words: how Memnox reaches the agent.
    public static func connectionKind(_ connection: AgentConnection) -> String {
        switch connection.connectionKind {
        case .runtimeHook: "Its own hook on this computer"
        case .runtimeMcpProxy: "Its MCP servers through Memnox"
        case .guardWrapper: "The Memnox guard in its code"
        case .gateway: "The Memnox gateway"
        case .mcp: "It talks to Memnox over MCP"
        case .observed: "Seen here, nothing in front of it"
        case nil: connection.kind
        }
    }

    /// Whether the connection is working now, idle, or gone.
    public static func status(_ connection: AgentConnection) -> String {
        switch connection.connectionStatus {
        case .live: "Working now"
        case .idle: "Idle"
        case .gone: "Not found any more"
        case nil: connection.status
        }
    }
}
