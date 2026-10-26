import Foundation

// Memory as layers on the wire, mirrored from the runtime's daemon/memory-layers.ts: MEMORY.md read in every chat, the
// router file that sends each department to its own file, the SKILL.md skills that say where live data is, and the
// cold cache count over recent chats. A plan is a preview; the runtime writes it only once the person confirms it.

/// Which layer a planned file is, as the runtime's MEMORY_LAYER names it.
public enum MemoryLayerKind: String, CaseIterable, Sendable {
    /// MEMORY.md, one line per memory.
    case index
    /// An agent's router file, one line per department.
    case router
    /// One memory written as its own file.
    case memory
}

/// MEMORY.md as it stands.
public struct MemoryIndexLayerView: Decodable, Equatable, Sendable {
    public let path: String
    public let present: Bool
    public let lines: Int
    /// Lines that say something and link to no file.
    public let unlinked: Int

    public init(path: String, present: Bool, lines: Int, unlinked: Int) {
        self.path = path
        self.present = present
        self.lines = lines
        self.unlinked = unlinked
    }
}

/// One agent's router file as it stands.
public struct MemoryRouterLayerView: Decodable, Equatable, Sendable {
    public let agent: String
    public let path: String
    public let present: Bool
    public let lines: Int
    public let chars: Int
    /// Folders that keep their own instruction file.
    public let departments: [String]
    /// How many of those the router names.
    public let routed: Int

    public init(agent: String, path: String, present: Bool, lines: Int, chars: Int, departments: [String], routed: Int) {
        self.agent = agent
        self.path = path
        self.present = present
        self.lines = lines
        self.chars = chars
        self.departments = departments
        self.routed = routed
    }
}

/// A SKILL.md the project keeps, and whether it says where live data is.
public struct MemorySkillLayerView: Decodable, Equatable, Sendable {
    public let name: String
    public let path: String
    public let liveData: Bool

    public init(name: String, path: String, liveData: Bool) {
        self.name = name
        self.path = path
        self.liveData = liveData
    }
}

/// One project's three layers.
public struct ProjectLayersView: Decodable, Equatable, Identifiable, Sendable {
    public let name: String
    public let path: String
    public let agents: [String]
    public let index: MemoryIndexLayerView
    public let routers: [MemoryRouterLayerView]
    public let skills: [MemorySkillLayerView]
    /// What the router keeps when a chat compacts, as last written.
    public let keep: [String]

    public var id: String { path }

    public init(name: String, path: String, agents: [String], index: MemoryIndexLayerView,
                routers: [MemoryRouterLayerView], skills: [MemorySkillLayerView], keep: [String]) {
        self.name = name
        self.path = path
        self.agents = agents
        self.index = index
        self.routers = routers
        self.skills = skills
        self.keep = keep
    }
}

/// What memory measured about itself; every field is absent where nothing was measured.
public struct MemoryValueView: Decodable, Equatable, Sendable {
    public let searchMedianMs: Double?
    public let searches: Int?
    public let contextTokensSaved: Int?

    public init(searchMedianMs: Double? = nil, searches: Int? = nil, contextTokensSaved: Int? = nil) {
        self.searchMedianMs = searchMedianMs
        self.searches = searches
        self.contextTokensSaved = contextTokensSaved
    }
}

public struct MemoryLayersView: Decodable, Equatable, Sendable {
    public let projects: [ProjectLayersView]
    public let value: MemoryValueView

    public init(projects: [ProjectLayersView], value: MemoryValueView) {
        self.projects = projects
        self.value = value
    }
}

/// One file a plan writes, its block before and after by line.
public struct MemoryLayerFilePlan: Decodable, Equatable, Identifiable, Sendable {
    public let path: String
    public let layer: String
    public let agent: String?
    public let whole: Bool
    public let before: [String]
    public let after: [String]
    public let changed: Bool

    public var id: String { path }
    /// The layer as a known case, or nil for one this app does not know yet.
    public var layerKind: MemoryLayerKind? { MemoryLayerKind(rawValue: layer) }

    public init(path: String, layer: MemoryLayerKind, agent: String? = nil, whole: Bool, before: [String],
                after: [String], changed: Bool) {
        self.path = path
        self.layer = layer.rawValue
        self.agent = agent
        self.whole = whole
        self.before = before
        self.after = after
        self.changed = changed
    }
}

/// The preview the person confirms; apply is refused once its digest no longer matches the files.
public struct MemoryLayersPlan: Decodable, Equatable, Sendable {
    public let project: String
    public let digest: String
    public let files: [MemoryLayerFilePlan]

    public init(project: String, digest: String, files: [MemoryLayerFilePlan]) {
        self.project = project
        self.digest = digest
        self.files = files
    }
}

public struct MemoryLayersApplied: Decodable, Equatable, Sendable {
    public let written: [String]
    public let unchanged: [String]
}

/// One model's API prices in US dollars per million tokens.
public struct ModelPriceView: Decodable, Equatable, Sendable {
    public let model: String
    public let input: Double
    public let cacheWrite: Double
    public let cacheRead: Double
}

/// The last days of chats as the runtime counted them; the money fields are absent where a price is unknown.
public struct SessionCostView: Decodable, Equatable, Sendable {
    public let days: Int
    public let sessions: Int
    public let turns: Int
    public let coldReloads: Int
    public let reloadedTokens: Int
    public let reloadCostUsd: Double?
    public let warmSavingUsd: Double?
    public let warmHours: Double
    public let unpricedModels: [String]
    public let prices: [ModelPriceView]

    public init(days: Int, sessions: Int, turns: Int, coldReloads: Int, reloadedTokens: Int, reloadCostUsd: Double? = nil,
                warmSavingUsd: Double? = nil, warmHours: Double, unpricedModels: [String] = [], prices: [ModelPriceView] = []) {
        self.days = days
        self.sessions = sessions
        self.turns = turns
        self.coldReloads = coldReloads
        self.reloadedTokens = reloadedTokens
        self.reloadCostUsd = reloadCostUsd
        self.warmSavingUsd = warmSavingUsd
        self.warmHours = warmHours
        self.unpricedModels = unpricedModels
        self.prices = prices
    }
}

/// A passage of a read document that a search matched.
public struct MemoryPassageView: Decodable, Equatable, Sendable {
    public let sourceId: String
    public let document: String
    public let heading: String?
    public let snippet: String
}
