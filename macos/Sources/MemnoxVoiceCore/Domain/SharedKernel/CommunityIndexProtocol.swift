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

    public var indexKind: IndexKind? { IndexKind(rawValue: kind) }

    public init(id: String, name: String, kind: IndexKind, description: String, category: String? = nil,
                publisher: IndexPublisher, license: String? = nil, agents: [String] = [], latest: IndexVersion? = nil,
                yanked: [String] = [], unsafe: Bool = false, installed: String? = nil) {
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
    }
}

public struct CommunityIndexView: Decodable, Equatable, Sendable {
    /// Where the index was read from.
    public let source: String
    /// When it was read; absent before it was ever read.
    public let fetchedAt: String?
    /// False where the index held more than it carries.
    public let complete: Bool
    public let entries: [IndexEntryView]
    /// Why what is shown is not fresh, or why there is nothing, in a sentence.
    public let said: String?

    public init(source: String, fetchedAt: String? = nil, complete: Bool = true, entries: [IndexEntryView] = [], said: String? = nil) {
        self.source = source
        self.fetchedAt = fetchedAt
        self.complete = complete
        self.entries = entries
        self.said = said
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
