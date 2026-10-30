import Foundation

// Memory on the wire, mirrored from the runtime's daemon/memory.ts: the sources a person pointed Memnox at, the Learn
// queue read out of them, and the facts a person confirmed. A model only proposes; a person's confirm verifies.

/// Where an item stands, as the runtime's MEMORY_STATUS names it.
public enum MemoryStatus: String, CaseIterable, Sendable {
    case candidate
    case verified
    /// A newer confirmed fact restates it.
    case superseded
    case rejected
    /// Every passage it was read from changed or went away.
    case outdated
    case conflicting
}

/// What an item is, as the runtime's MEMORY_KIND names it.
public enum MemoryKind: String, CaseIterable, Sendable {
    case fact
    case convention
    /// Becomes a signed rule proposal once a person confirms it.
    case rule
}

/// Where an item came from, as the runtime's MEMORY_ORIGIN names it.
public enum MemoryOrigin: String, CaseIterable, Sendable {
    case extracted
    case agent
    case person
}

/// Where what memory teaches is kept, as the runtime's MEMORY_SCOPE names it.
public enum MemoryScope: String, CaseIterable, Sendable {
    case personal
    case project
}

/// The kinds of place memory is read from, as the runtime's MEMORY_SOURCE_KIND names them.
public enum MemorySourceKind: String, CaseIterable, Sendable {
    case obsidian
    case markdown
    /// CLAUDE.md, AGENTS.md, GEMINI.md and .cursor/rules in one repository.
    case instructions
    case notionExport = "notion-export"
    case supermemory
    /// An MCP memory server in the hub, read through one of its tools.
    case mcp
}

/// Files the person points at are their own; anything a third party wrote or exported is not.
public enum SourceTrust: String, CaseIterable, Sendable {
    case trusted
    case tainted
}

/// Whether the person's agent CLI read the passages a read found, as the runtime's EXTRACTOR_STATE names it.
public enum ExtractorState: String, CaseIterable, Sendable {
    case answered
    /// No agent CLI could be asked, so the new passages wait for the next read.
    case unavailable
    /// It answered in no shape that could be read.
    case unreadable
    /// Nothing new to read.
    case idle
}

/// A source as a form adds it, sent as `memorySource`; a key is named, never sent, and kept with the hub's secrets.
public struct MemorySourceInput: Encodable, Equatable, Sendable {
    public let kind: String
    /// A folder, absolute, or a repository for instruction files.
    public let location: String?
    public let name: String?
    public let scope: String?
    /// The OS store entry holding an API key.
    public let secret: String?
    /// For an MCP source: the hub server, and the tool that reads it.
    public let server: String?
    public let tool: String?

    public init(kind: MemorySourceKind, location: String? = nil, name: String? = nil, scope: MemoryScope? = nil,
                secret: String? = nil, server: String? = nil, tool: String? = nil) {
        self.kind = kind.rawValue
        self.location = location
        self.name = name
        self.scope = scope?.rawValue
        self.secret = secret
        self.server = server
        self.tool = tool
    }
}

/// How many items a source taught, by where each stands now.
public struct MemorySourceCounts: Decodable, Equatable, Sendable {
    public let candidate: Int
    public let verified: Int
    public let conflicting: Int
    public let outdated: Int
    public let rejected: Int

    public init(candidate: Int = 0, verified: Int = 0, conflicting: Int = 0, outdated: Int = 0, rejected: Int = 0) {
        self.candidate = candidate
        self.verified = verified
        self.conflicting = conflicting
        self.outdated = outdated
        self.rejected = rejected
    }
}

public struct MemorySourceView: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: String
    public let name: String
    /// The folder, or the API's base URL.
    public let location: String
    public let trust: String
    public let scope: String
    public let project: String?
    /// Read again when a file in it changes; false for an API, which is read on request only.
    public let watched: Bool
    /// For a source that needs a key: whether the OS store holds it. Never the value.
    public let keyHeld: Bool?
    public let lastReadAt: String?
    /// Why the last read failed, when it did.
    public let lastError: String?
    public let counts: MemorySourceCounts

    public init(id: String, kind: MemorySourceKind, name: String, location: String, trust: SourceTrust = .trusted,
                scope: MemoryScope = .personal, project: String? = nil, watched: Bool = false, keyHeld: Bool? = nil,
                lastReadAt: String? = nil, lastError: String? = nil, counts: MemorySourceCounts = MemorySourceCounts()) {
        self.id = id
        self.kind = kind.rawValue
        self.name = name
        self.location = location
        self.trust = trust.rawValue
        self.scope = scope.rawValue
        self.project = project
        self.watched = watched
        self.keyHeld = keyHeld
        self.lastReadAt = lastReadAt
        self.lastError = lastError
        self.counts = counts
    }

    /// The kind as a known case, or nil for one this app does not know yet.
    public var sourceKind: MemorySourceKind? { MemorySourceKind(rawValue: kind) }
    public var sourceTrust: SourceTrust? { SourceTrust(rawValue: trust) }
}

public struct MemoryEvidenceView: Decodable, Equatable, Sendable {
    /// As a person reads it: `notes/ops.md#Releases`, or the link.
    public let ref: String
    public let document: String
    public let heading: String?
    public let url: String?
    /// The source's name, or the source id when it was removed.
    public let source: String
    /// The passage changed or went away since it was read.
    public let stale: Bool

    public init(ref: String, document: String, heading: String? = nil, url: String? = nil, source: String, stale: Bool = false) {
        self.ref = ref
        self.document = document
        self.heading = heading
        self.url = url
        self.source = source
        self.stale = stale
    }
}

/// The rule half of a rule candidate, read back in one plain sentence before any field.
public struct MemoryRuleView: Decodable, Equatable, Sendable {
    public let effect: String
    public let actions: [String]
    public let targets: [String]?
    public let agents: [String]?
    public let reason: String
    public let sentence: String

    public init(effect: String, actions: [String], targets: [String]? = nil, agents: [String]? = nil, reason: String, sentence: String) {
        self.effect = effect
        self.actions = actions
        self.targets = targets
        self.agents = agents
        self.reason = reason
        self.sentence = sentence
    }
}

/// The earlier item a candidate restates, so the queue says so rather than offering it as news.
public struct MemoryDuplicateView: Decodable, Equatable, Sendable {
    public let id: String
    public let statement: String

    public init(id: String, statement: String) {
        self.id = id
        self.statement = statement
    }
}

public struct MemoryItemView: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: String
    /// Verbatim as it was read or suggested.
    public let statement: String
    public let subject: String
    public let status: String
    public let scope: String
    public let project: String?
    public let origin: String
    /// Read from a source outside the person's trust.
    public let tainted: Bool
    /// The extractor's own confidence, from 0 to 1, never a person's.
    public let extractorConfidence: Double?
    /// The agent that suggested it.
    public let suggestedBy: String?
    public let rule: MemoryRuleView?
    public let duplicateOf: MemoryDuplicateView?
    /// The rule proposal waiting on the person's signature.
    public let proposalId: String?
    public let evidence: [MemoryEvidenceView]
    public let createdAt: String
    public let decidedAt: String?
    public let decidedBy: String?

    public init(id: String, kind: MemoryKind = .fact, statement: String, subject: String = "", status: MemoryStatus = .candidate,
                scope: MemoryScope = .personal, project: String? = nil, origin: MemoryOrigin = .extracted, tainted: Bool = false,
                extractorConfidence: Double? = nil, suggestedBy: String? = nil, rule: MemoryRuleView? = nil,
                duplicateOf: MemoryDuplicateView? = nil, proposalId: String? = nil, evidence: [MemoryEvidenceView] = [],
                createdAt: String, decidedAt: String? = nil, decidedBy: String? = nil) {
        self.id = id
        self.kind = kind.rawValue
        self.statement = statement
        self.subject = subject
        self.status = status.rawValue
        self.scope = scope.rawValue
        self.project = project
        self.origin = origin.rawValue
        self.tainted = tainted
        self.extractorConfidence = extractorConfidence
        self.suggestedBy = suggestedBy
        self.rule = rule
        self.duplicateOf = duplicateOf
        self.proposalId = proposalId
        self.evidence = evidence
        self.createdAt = createdAt
        self.decidedAt = decidedAt
        self.decidedBy = decidedBy
    }

    /// Each as a known case, or nil for one this app does not know yet.
    public var memoryKind: MemoryKind? { MemoryKind(rawValue: kind) }
    public var memoryStatus: MemoryStatus? { MemoryStatus(rawValue: status) }
    public var memoryScope: MemoryScope? { MemoryScope(rawValue: scope) }
    public var memoryOrigin: MemoryOrigin? { MemoryOrigin(rawValue: origin) }
}

public struct MemoryItemsView: Decodable, Equatable, Sendable {
    public let items: [MemoryItemView]
    /// Matching items past the ones listed, so a cut list never reads as whole.
    public let more: Int

    public init(items: [MemoryItemView], more: Int = 0) {
        self.items = items
        self.more = more
    }
}

/// What one read came to, so an empty read and a failed one are told apart.
public struct MemoryReadSummary: Decodable, Equatable, Sendable {
    public let sourceId: String
    public let documents: Int
    public let passages: Int
    public let added: Int
    /// Said again by another passage, which only added evidence.
    public let merged: Int
    /// Words a person rejected before, not proposed again.
    public let rejectedBefore: Int
    /// Citations naming no passage shown, dropped and never repaired.
    public let droppedCitations: Int
    /// Candidates that did not survive validation.
    public let discarded: Int
    public let outdated: Int
    public let extractor: String
    public let error: String?

    public init(sourceId: String, documents: Int = 0, passages: Int = 0, added: Int = 0, merged: Int = 0, rejectedBefore: Int = 0,
                droppedCitations: Int = 0, discarded: Int = 0, outdated: Int = 0, extractor: ExtractorState = .idle, error: String? = nil) {
        self.sourceId = sourceId
        self.documents = documents
        self.passages = passages
        self.added = added
        self.merged = merged
        self.rejectedBefore = rejectedBefore
        self.droppedCitations = droppedCitations
        self.discarded = discarded
        self.outdated = outdated
        self.extractor = extractor.rawValue
        self.error = error
    }

    public var extractorState: ExtractorState? { ExtractorState(rawValue: extractor) }
}

/// An edit before confirming, sent as `memoryEdit`; a rule goes through the same draft as any other rule.
public struct MemoryEditInput: Encodable, Equatable, Sendable {
    public let statement: String?
    public let subject: String?
    public let rule: RuleDraftInput?

    public init(statement: String? = nil, subject: String? = nil, rule: RuleDraftInput? = nil) {
        self.statement = statement
        self.subject = subject
        self.rule = rule
    }
}
