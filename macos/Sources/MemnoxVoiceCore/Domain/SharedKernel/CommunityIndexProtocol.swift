import Foundation

// The community index on the wire, mirrored from the runtime's daemon/community-index.ts: skills and rule packs read
// from Memnox Cloud's marketplace or a git repository's index.json. A download is checked against its digest before it
// is written, and an install is only a skill held for acceptance or a pack's rules proposed.

/// What a listing is, in the marketplace's own words.
public enum IndexKind: String, Sendable, CaseIterable {
    case skill
    case rulePack = "rule_pack"
}

/// Who published a listing: an organization or a member, as the marketplace says.
public struct IndexPublisher: Decodable, Equatable, Sendable {
    public let kind: String
    public let name: String

    public init(kind: String, name: String) {
        self.kind = kind
        self.name = name
    }
}

/// The newest version not marked unsafe, and the digest its content must match.
public struct IndexVersion: Decodable, Equatable, Sendable {
    public let version: String
    public let digest: String

    public init(version: String, digest: String) {
        self.version = version
        self.digest = digest
    }
}

/// The source named by a word rather than an address, as the runtime's INDEX_SOURCE names it.
public enum IndexSource {
    /// Memnox Cloud's marketplace, of the workspace this machine is on: the default.
    public static let marketplace = "marketplace"
}

/// What a listing declares it needs, as its manifest in the index says; read before anything is installed.
public struct IndexNeedsView: Decodable, Equatable, Sendable {
    /// Paths it reads or writes.
    public let filesystem: [String]
    /// Hosts it reaches.
    public let network: [String]
    /// Commands it runs.
    public let commands: [String]
    /// MCP servers it uses, by name.
    public let mcpServers: [String]
    /// Tools it asks its agent for, by name.
    public let tools: [String]

    public init(filesystem: [String] = [], network: [String] = [], commands: [String] = [], mcpServers: [String] = [],
                tools: [String] = []) {
        self.filesystem = filesystem
        self.network = network
        self.commands = commands
        self.mcpServers = mcpServers
        self.tools = tools
    }
}

/// One listing as a screen browses it.
public struct IndexEntryView: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    /// Kept as written, so a kind this app does not know yet still decodes.
    public let kind: String
    public let description: String
    public let category: String?
    public let publisher: IndexPublisher
    public let license: String?
    /// Agent kinds it supports; empty is every agent.
    public let agents: [String]
    public let latest: IndexVersion?
    /// Versions marked unsafe since they were published, which nothing installs.
    public let yanked: [String]
    /// Every published version is marked unsafe, so the listing offers nothing to install.
    public let unsafe: Bool
    /// The version of this skill the Skills Hub holds here, where it holds one.
    public let installed: String?
    /// What it declares it needs; nil where the index carries no manifest for it.
    public let needs: IndexNeedsView?
    /// What a person should know before installing it, each in a sentence; empty where nothing stands out.
    public let warnings: [String]

    public var indexKind: IndexKind? { IndexKind(rawValue: kind) }

    public init(id: String, name: String, kind: IndexKind, description: String, category: String? = nil,
                publisher: IndexPublisher, license: String? = nil, agents: [String] = [], latest: IndexVersion? = nil,
                yanked: [String] = [], unsafe: Bool = false, installed: String? = nil, needs: IndexNeedsView? = nil,
                warnings: [String] = []) {
        self.id = id
        self.name = name
        self.kind = kind.rawValue
        self.description = description
        self.category = category
        self.publisher = publisher
        self.license = license
        self.agents = agents
        self.latest = latest
        self.yanked = yanked
        self.unsafe = unsafe
        self.installed = installed
        self.needs = needs
        self.warnings = warnings
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, description, category, publisher, license, agents, latest, yanked, unsafe, installed, needs, warnings
    }

    /// A runtime from before needs and warnings sends neither, which reads as nothing declared and nothing to know.
    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        id = try fields.decode(String.self, forKey: .id)
        name = try fields.decode(String.self, forKey: .name)
        kind = try fields.decode(String.self, forKey: .kind)
        description = try fields.decode(String.self, forKey: .description)
        category = try fields.decodeIfPresent(String.self, forKey: .category)
        publisher = try fields.decode(IndexPublisher.self, forKey: .publisher)
        license = try fields.decodeIfPresent(String.self, forKey: .license)
        agents = try fields.decode([String].self, forKey: .agents)
        latest = try fields.decodeIfPresent(IndexVersion.self, forKey: .latest)
        yanked = try fields.decode([String].self, forKey: .yanked)
        unsafe = try fields.decode(Bool.self, forKey: .unsafe)
        installed = try fields.decodeIfPresent(String.self, forKey: .installed)
        needs = try fields.decodeIfPresent(IndexNeedsView.self, forKey: .needs)
        warnings = try fields.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }
}

public struct CommunityIndexView: Decodable, Equatable, Sendable {
    /// Where the index was read from.
    public let source: String
    /// Whether that is a Memnox Cloud marketplace, the default, rather than an index somebody named.
    public let marketplace: Bool
    /// When it was read; absent before it was ever read.
    public let fetchedAt: String?
    /// False where the index held more than it carries.
    public let complete: Bool
    public let entries: [IndexEntryView]
    /// Why what is shown is not fresh, or why there is nothing, in a sentence.
    public let said: String?

    public init(source: String, marketplace: Bool = true, fetchedAt: String? = nil, complete: Bool = true,
                entries: [IndexEntryView] = [], said: String? = nil) {
        self.source = source
        self.marketplace = marketplace
        self.fetchedAt = fetchedAt
        self.complete = complete
        self.entries = entries
        self.said = said
    }

    private enum CodingKeys: String, CodingKey {
        case source, marketplace, fetchedAt, complete, entries, said
    }

    /// A runtime from before the source could be named only ever read the marketplace.
    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        source = try fields.decode(String.self, forKey: .source)
        marketplace = try fields.decodeIfPresent(Bool.self, forKey: .marketplace) ?? true
        fetchedAt = try fields.decodeIfPresent(String.self, forKey: .fetchedAt)
        complete = try fields.decode(Bool.self, forKey: .complete)
        entries = try fields.decode([IndexEntryView].self, forKey: .entries)
        said = try fields.decodeIfPresent(String.self, forKey: .said)
    }
}

/// What an install did, so a screen says it in a line and opens what waits on the person.
public struct IndexInstalled: Decodable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let kind: String
    public let version: String
    public let digest: String
    /// For a pack: one proposal per rule, each signed on its own.
    public let proposed: [String]
    /// For a skill: it is in the Skills Hub, held until the person accepts it.
    public let held: Bool
    public let said: String

    public init(id: String, name: String, kind: IndexKind, version: String, digest: String, proposed: [String] = [],
                held: Bool = false, said: String = "") {
        self.id = id
        self.name = name
        self.kind = kind.rawValue
        self.version = version
        self.digest = digest
        self.proposed = proposed
        self.held = held
        self.said = said
    }
}
