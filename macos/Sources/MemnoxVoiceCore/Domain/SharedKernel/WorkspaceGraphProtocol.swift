import Foundation

// The workspace's memory graph as the runtime's `workspace-graph` answers it, mirroring workspace-graph.ts: what
// arrived from each connected tool, who said it, and what the team settled out of it, read live off the control plane
// by the daemon and folded with the saved facts. This app never reaches the cloud itself.

/// What a node is, as the runtime's WORKSPACE_NODE_KIND writes it.
public enum WorkspaceNodeKind: String, CaseIterable, Sendable {
    /// A connected tool things arrive through: slack, github, notion.
    case source
    /// One thing that arrived: a message, an issue, an uploaded file, or an address several things link to.
    case document
    /// A section of something long enough to have been cut.
    case passage
    /// A thread or a channel, holding the messages in it.
    case conversation
    case person
    /// An account its tool lists as an app, which posts like somebody and is never one.
    case bot
    /// A team, a department or the company, as the directory names it.
    case group
    /// A rule set in force.
    case policy
    /// Something the team settled, in force.
    case decision
    /// Something a connected tool said that nobody approved.
    case candidate
}

/// Where a workspace decision stands; a machine is handed only what is in force and what waits.
public enum WorkspaceNodeStatus: String, CaseIterable, Sendable {
    case verified
    case candidate
}

/// What one line says, as the runtime's WORKSPACE_LINK_KIND writes it.
public enum WorkspaceLinkKind: String, CaseIterable, Sendable {
    case carries
    case contains
    case said
    case mentions
    case memberOf = "member_of"
    case reportsTo = "reports_to"
    case approved
    case linksTo = "links_to"
    case relates
    case readFrom = "read_from"
    case about
    case answersFor = "answers_for"
    case names
}

/// Whether the picture was read live just now or stands on the facts this machine saved.
public enum WorkspaceGraphSource: String, Sendable {
    case live
    case saved
}

/// Why the saved facts stand in for the live graph.
public enum WorkspaceGraphFallback: String, Sendable {
    case notJoined = "not-joined"
    case unreachable
    case refused
}

/// One message an author posted that the cloud counted rather than drew.
public struct WorkspaceSaid: Decodable, Equatable, Sendable {
    public let label: String
    public let href: String?
    public let excerpt: String?
    public let at: String?

    public init(label: String, href: String? = nil, excerpt: String? = nil, at: String? = nil) {
        self.label = label
        self.href = href
        self.excerpt = excerpt
        self.at = at
    }
}

public struct WorkspaceGraphNode: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    /// The kind as sent; `nodeKind` reads it, nil for one this app does not know yet.
    public let kind: String
    public let label: String
    /// The system that delivered it, in its own word: slack, github.
    public let tool: String?
    public let href: String?
    /// The opening of what arrived, already clipped and cleared for this machine by the cloud.
    public let excerpt: String?
    /// The words a decision or a candidate states, verbatim.
    public let statement: String?
    public let saidBy: String?
    public let at: String?
    /// How many times the same person said it, or how many messages an author's mark counts.
    public let count: Int?
    public let status: String?
    public let provenance: String?
    public let untrusted: Bool
    /// How many lines touch it, so the map sizes it and names only the heavy ones.
    public let weight: Int
    public let said: [WorkspaceSaid]

    private enum Field: String, CodingKey {
        case id, kind, label, tool, href, excerpt, statement, saidBy, at, count, status, provenance, untrusted, weight, said
    }

    public init(id: String, kind: WorkspaceNodeKind, label: String, tool: String? = nil, href: String? = nil,
                excerpt: String? = nil, statement: String? = nil, saidBy: String? = nil, at: String? = nil,
                count: Int? = nil, status: WorkspaceNodeStatus? = nil, provenance: String? = nil, untrusted: Bool = false,
                weight: Int = 0, said: [WorkspaceSaid] = []) {
        self.id = id
        self.kind = kind.rawValue
        self.label = label
        self.tool = tool
        self.href = href
        self.excerpt = excerpt
        self.statement = statement
        self.saidBy = saidBy
        self.at = at
        self.count = count
        self.status = status?.rawValue
        self.provenance = provenance
        self.untrusted = untrusted
        self.weight = weight
        self.said = said
    }

    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: Field.self)
        id = try fields.decode(String.self, forKey: .id)
        kind = try fields.decode(String.self, forKey: .kind)
        label = (try? fields.decodeIfPresent(String.self, forKey: .label)) ?? id
        tool = try? fields.decodeIfPresent(String.self, forKey: .tool)
        href = try? fields.decodeIfPresent(String.self, forKey: .href)
        excerpt = try? fields.decodeIfPresent(String.self, forKey: .excerpt)
        statement = try? fields.decodeIfPresent(String.self, forKey: .statement)
        saidBy = try? fields.decodeIfPresent(String.self, forKey: .saidBy)
        at = try? fields.decodeIfPresent(String.self, forKey: .at)
        count = try? fields.decodeIfPresent(Int.self, forKey: .count)
        status = try? fields.decodeIfPresent(String.self, forKey: .status)
        provenance = try? fields.decodeIfPresent(String.self, forKey: .provenance)
        untrusted = (try? fields.decodeIfPresent(Bool.self, forKey: .untrusted)) ?? false
        weight = (try? fields.decodeIfPresent(Int.self, forKey: .weight)) ?? 0
        said = (try? fields.decodeIfPresent([WorkspaceSaid].self, forKey: .said)) ?? []
    }

    public var nodeKind: WorkspaceNodeKind? { WorkspaceNodeKind(rawValue: kind) }
    public var nodeStatus: WorkspaceNodeStatus? { status.flatMap(WorkspaceNodeStatus.init(rawValue:)) }
}

public struct WorkspaceGraphLink: Decodable, Equatable, Sendable {
    public let from: String
    public let to: String
    /// The kind as sent; `linkKind` reads it, nil for one this app does not know yet.
    public let kind: String
    public let basis: String?

    public init(from: String, to: String, kind: WorkspaceLinkKind, basis: String? = nil) {
        self.from = from
        self.to = to
        self.kind = kind.rawValue
        self.basis = basis
    }

    public var linkKind: WorkspaceLinkKind? { WorkspaceLinkKind(rawValue: kind) }
}

/// The picture, sent as `workspaceGraph` on `workspace-graph`: live where the cloud answered, the saved facts where not.
public struct WorkspaceGraphView: Decodable, Equatable, Sendable {
    public let nodes: [WorkspaceGraphNode]
    public let links: [WorkspaceGraphLink]
    /// How many this machine's clearance kept back, always said, or a partial picture reads as whole.
    public let withheld: Int
    public let truncated: Bool
    public let source: String
    public let fallback: String?
    public let readAt: String?
    public let syncedAt: String?

    private enum Field: String, CodingKey {
        case nodes, links, withheld, truncated, source, fallback, readAt, syncedAt
    }

    public init(nodes: [WorkspaceGraphNode] = [], links: [WorkspaceGraphLink] = [], withheld: Int = 0, truncated: Bool = false,
                source: WorkspaceGraphSource = .live, fallback: WorkspaceGraphFallback? = nil, readAt: String? = nil,
                syncedAt: String? = nil) {
        self.nodes = nodes
        self.links = links
        self.withheld = withheld
        self.truncated = truncated
        self.source = source.rawValue
        self.fallback = fallback?.rawValue
        self.readAt = readAt
        self.syncedAt = syncedAt
    }

    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: Field.self)
        // One node or line this app cannot read is dropped rather than losing the whole picture.
        nodes = ((try? fields.decodeIfPresent([Lenient<WorkspaceGraphNode>].self, forKey: .nodes)) ?? []).compactMap(\.value)
        links = ((try? fields.decodeIfPresent([Lenient<WorkspaceGraphLink>].self, forKey: .links)) ?? []).compactMap(\.value)
        withheld = (try? fields.decodeIfPresent(Int.self, forKey: .withheld)) ?? 0
        truncated = (try? fields.decodeIfPresent(Bool.self, forKey: .truncated)) ?? false
        source = (try? fields.decodeIfPresent(String.self, forKey: .source)) ?? WorkspaceGraphSource.saved.rawValue
        fallback = try? fields.decodeIfPresent(String.self, forKey: .fallback)
        readAt = try? fields.decodeIfPresent(String.self, forKey: .readAt)
        syncedAt = try? fields.decodeIfPresent(String.self, forKey: .syncedAt)
    }

    public var graphSource: WorkspaceGraphSource? { WorkspaceGraphSource(rawValue: source) }
    public var graphFallback: WorkspaceGraphFallback? { fallback.flatMap(WorkspaceGraphFallback.init(rawValue:)) }
}

/// One element of a list decoded on its own, so a malformed one is nil rather than failing its neighbours.
private struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}
