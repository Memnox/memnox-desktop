import Foundation

// What this Mac learned, drawn as what it was read out of: the console's memory map, built from the runtime's own
// memory views. **Every line is a field on a record, never a score or a guess**: a fact cites a passage of a document,
// the document sits in a source, a rule is the one its fact governs, and a restatement names the fact it repeats. A
// fact that cites nothing hangs off nothing. Mirrors memory-map.ts in the Tauri core.

public enum MemoryMapNodeKind: String, Sendable {
    /// One fact, convention or rule, as the person's agents are told it.
    case memory
    /// A file or page a fact cites, from `evidence.document`.
    case document
    /// Where the document was read from, from `evidence.source`.
    case source
    /// The rule a fact governs, from `item.rule`.
    case rule
    /// One conversation an agent held: what was said and worked on, which memory was read into.
    case conversation
    /// One of the person's own connected apps whose calls fed memory.
    case app
    /// A project folder a source, a fact or a conversation names.
    case workspace
    /// One thing the workspace settled, or that a connected tool said and nobody approved, as this machine pulled it.
    case decision
    /// Somebody a workspace decision names, confirmed or said: the owner, the approver, who said it.
    case person
    /// A skill the Skills Hub keeps or an agent folder holds, which the brain draws at its core.
    case skill
    /// A rule in force or a standing permission, which runs without the person and rings the brain.
    case standing
}

/// Where a node's memory is held: learned on this Mac, pulled down from the workspace, or a thing both name, such as
/// an app this Mac uses that the workspace also reads from.
public enum MemoryHome: String, CaseIterable, Sendable {
    case thisMac
    case workspace
    case both
}

/// Which memory the map shows: everything, only what this Mac learned, or only what the workspace settled.
public enum MemoryHomeFilter: String, CaseIterable, Sendable {
    case everything
    case thisMac
    case workspace

    /// Whether a node held there is shown; a node both name is shown under either.
    public func shows(_ home: MemoryHome) -> Bool {
        switch (self, home) {
        case (.everything, _), (_, .both), (.thisMac, .thisMac), (.workspace, .workspace): true
        case (.thisMac, .workspace), (.workspace, .thisMac): false
        }
    }
}

/// The workspace record a decision node stands for, kept whole so its details say its source and who said it.
public enum WorkspaceEntry: Equatable, Sendable {
    case settled(WorkspaceFact)
    case unconfirmed(WorkspaceCandidate)

    public var id: String {
        switch self {
        case .settled(let fact): fact.id
        case .unconfirmed(let candidate): candidate.id
        }
    }

    public var statement: String {
        switch self {
        case .settled(let fact): fact.statement
        case .unconfirmed(let candidate): candidate.statement
        }
    }
}

public enum MemoryLinkKind: String, CaseIterable, Sendable {
    /// A fact and the document its evidence cites.
    case cites
    /// A document and the source it was read from.
    case heldIn = "held_in"
    /// A fact and the rule it governs.
    case governs
    /// A fact and the earlier fact it restates, through `duplicateOf`.
    case restates
    /// A conversation and the project its folder is in, from `host.cwd` or its repository.
    case worksIn = "works_in"
    /// A conversation and what it read: a document from a call it made, or an app it worked in.
    case reads
    /// A source or a fact and the project it is kept for, from `project`.
    case within
    /// A workspace decision and the connected tool it was read out of, from `sources` or the host of `sourceRef`.
    case pulledFrom = "pulled_from"
    /// A person and what they said that a decision was read out of, from `saidBy`.
    case said
    /// A decision and the person it names as owner, approver or party, from `principal`.
    case names
    /// A person and the decision they confirmed, from `verifiedBy`.
    case confirmed
    /// A person and the team the directory puts them on, or the person they report to.
    case memberOf = "member_of"
    /// A thing and what its words link to, often in another tool.
    case linksTo = "links_to"
    /// Two things that say something alike, proposed by comparison and stated by nobody.
    case relates
}

public struct MemoryMapNode: Equatable, Sendable, SurfacePlaced {
    public var place: Placed
    public let kind: MemoryMapNodeKind
    /// The memory item the node is, or names: a rule node carries the item it came from.
    public let item: String?
    public let status: String?
    public let memoryKind: String?
    /// Read from a source outside the person's trust.
    public let tainted: Bool
    /// What the node is, said under its name: the source's kind, a rule's effect, a document's source.
    public let detail: String?
    /// What draws its logo: an app's slug, nil for a node drawn with its kind's icon.
    public var mark: String? = nil
    /// The agents that read, wrote or worked in it, by name: said in its details, never drawn as nodes of their own.
    public var usedBy: [String] = []
    /// Learned on this Mac, pulled from the workspace, or named by both.
    public var home: MemoryHome = .thisMac
    /// The workspace record a decision stands for, nil for every other node.
    public var workspace: WorkspaceEntry? = nil
    /// The node of the workspace's live graph this one is, whole, so its details say what arrived, who said it and where.
    public var live: WorkspaceGraphNode? = nil
    /// How many times the same thing was said, or how many messages an author's mark counts, worn as a badge.
    public var count: Int? = nil
    /// How many lines the record says touch it, so the heavy ones are named before anything is hovered.
    public var weight = 0
    /// When it was learned, written or last used, as the runtime writes a time, which lays it along the Timeline.
    public var at: String? = nil

    public var id: String { place.id }
    public var label: String { place.label }
}

public struct MemoryMapEdge: Equatable, Sendable {
    public let id: String
    public let from: String
    public let to: String
    public let kind: MemoryLinkKind
    /// The cited passage changed or went away since it was read, from `evidence.stale`.
    public let stale: Bool

    public init(from: String, to: String, kind: MemoryLinkKind, stale: Bool = false) {
        self.id = MemoryMaps.edgeId(from, to, kind)
        self.from = from
        self.to = to
        self.kind = kind
        self.stale = stale
    }
}

public struct MemoryMap: Equatable, Sendable {
    public let nodes: [MemoryMapNode]
    public let edges: [MemoryMapEdge]

    public init(nodes: [MemoryMapNode], edges: [MemoryMapEdge]) {
        self.nodes = nodes
        self.edges = edges
    }
}

public enum MemoryMaps {
    /// How big each mark is, in world points; lines are trimmed against these.
    public enum Size {
        public static let memory = (width: 188.0, height: 58.0)
        public static let document = (width: 164.0, height: 44.0)
        public static let rule = (width: 176.0, height: 48.0)
        public static let source = 48.0
    }

    private static let fullTurn = 2 * Double.pi
    private static let middle = (x: 0.5, y: 0.5)
    /// One document's ring grows with what cites it, the console's orbit numbers.
    private static let orbitLeast = 0.12
    private static let orbitPer = 0.014
    private static let orbitMost = 0.26
    /// Where the hubs sit around the middle, and the loose ring outside them all.
    private static let hubRing = 0.3
    private static let looseRing = 0.5
    /// Every second node on a ring is pulled in, so two names never land together.
    private static let stagger = 0.86
    private static let separator = "|"

    public static func edgeId(_ from: String, _ to: String, _ kind: MemoryLinkKind) -> String {
        [from, to, kind.rawValue].joined(separator: separator)
    }

    public static func documentId(source: String, document: String) -> String { "doc:\(source)\(separator)\(document)" }
    public static func sourceId(_ source: String) -> String { "src:\(source)" }
    public static func ruleId(_ item: String) -> String { "rule:\(item)" }

    /// A document said by its last part, since the folders above it identify nothing on a map.
    public static func documentLabel(_ document: String) -> String {
        let parts = document.split(whereSeparator: { $0 == "/" || $0 == "\\" }).map(String.init)
        return parts.last ?? document
    }

    private struct Gathered {
        var documents: [MemoryMapNode] = []
        var sources: [MemoryMapNode] = []
        var orbits: [String: [MemoryMapNode]] = [:]
        var loose: [MemoryMapNode] = []
        var edges: [MemoryMapEdge] = []
    }

    /// The map of the items listed, laid out as the console seeds its own: each document with the facts that cite it on
    /// a ring around it, and the sources, the rules and the facts citing nothing outside them all. No randomness, so
    /// the same record seeds the same picture twice.
    public static func map(_ items: [MemoryItemView], sources: [MemorySourceView], kindLabel: (String) -> String) -> MemoryMap {
        var gathered = Gathered()
        let sorted = items.sorted { $0.id < $1.id }
        for item in sorted { gather(item, sources: sources, kindLabel: kindLabel, into: &gathered) }
        let listed = Set(sorted.map(\.id))
        for item in sorted {
            // A restatement is drawn only where the fact it repeats is on the map too, or the line leads off it.
            if let earlier = item.duplicateOf, listed.contains(earlier.id) {
                gathered.edges.append(MemoryMapEdge(from: item.id, to: earlier.id, kind: .restates))
            }
        }
        let nodes = placeAll(gathered.documents, orbits: gathered.orbits, loose: gathered.sources + gathered.loose)
        return MemoryMap(nodes: SurfaceGeometry.centred(nodes), edges: gathered.edges)
    }

    /// One item's node, its rule, and what its evidence cites, each line read off a field of the item.
    private static func gather(_ item: MemoryItemView, sources: [MemorySourceView], kindLabel: (String) -> String, into: inout Gathered) {
        let memory = memoryNode(item)
        var hung = false
        for evidence in item.evidence {
            let document = documentId(source: evidence.source, document: evidence.document)
            let source = sourceId(evidence.source)
            if !into.documents.contains(where: { $0.id == document }) {
                into.documents.append(blank(document, documentLabel(evidence.document), .document, detail: evidence.source))
                into.edges.append(MemoryMapEdge(from: document, to: source, kind: .heldIn))
            }
            if !into.sources.contains(where: { $0.id == source }) {
                let known = sources.first { $0.name == evidence.source || $0.id == evidence.source }
                into.sources.append(blank(source, evidence.source, .source, detail: known.map { kindLabel($0.kind) }))
            }
            let cite = edgeId(item.id, document, .cites)
            // Two passages of one document are one line, stale only when every passage it cites changed.
            if let already = into.edges.firstIndex(where: { $0.id == cite }) {
                let before = into.edges[already]
                into.edges[already] = MemoryMapEdge(from: before.from, to: before.to, kind: .cites, stale: before.stale && evidence.stale)
                continue
            }
            into.edges.append(MemoryMapEdge(from: item.id, to: document, kind: .cites, stale: evidence.stale))
            if !hung {
                into.orbits[document, default: []].append(memory)
                hung = true
            }
        }
        if !hung { into.loose.append(memory) }
        if let rule = item.rule {
            let id = ruleId(item.id)
            into.loose.append(blank(id, rule.sentence, .rule, item: item.id, detail: rule.effect))
            into.edges.append(MemoryMapEdge(from: item.id, to: id, kind: .governs))
        }
    }

    private static func memoryNode(_ item: MemoryItemView) -> MemoryMapNode {
        var node = blank(item.id, item.statement, .memory, item: item.id, status: item.status, memoryKind: item.kind, tainted: item.tainted)
        node.at = item.decidedAt ?? item.createdAt
        return node
    }

    /// A node before it is placed, sized for its kind. Cards write their own name; a source's hangs below it.
    private static func blank(_ id: String, _ label: String, _ kind: MemoryMapNodeKind, item: String? = nil, status: String? = nil,
                              memoryKind: String? = nil, tainted: Bool = false, detail: String? = nil) -> MemoryMapNode {
        let place: Placed
        switch kind {
        case .source, .conversation, .app, .workspace, .decision, .person, .skill, .standing:
            place = Placed(id: id, x: middle.x, y: middle.y, depth: middle.y, width: Size.source, label: label)
        case .memory, .document, .rule:
            let box = kind == .memory ? Size.memory : kind == .document ? Size.document : Size.rule
            place = Placed(id: id, x: middle.x, y: middle.y, depth: middle.y, width: box.width, height: box.height, captioned: false, label: label)
        }
        return MemoryMapNode(place: place, kind: kind, item: item, status: status, memoryKind: memoryKind, tainted: tainted, detail: detail)
    }

    /// Every hub with its own ring around it, then the loose nodes outside them all.
    private static func placeAll(_ hubs: [MemoryMapNode], orbits: [String: [MemoryMapNode]], loose: [MemoryMapNode]) -> [MemoryMapNode] {
        var placed: [MemoryMapNode] = []
        for (index, hub) in hubs.enumerated() {
            let centre: (x: Double, y: Double, depth: Double)
            if hubs.count == 1 {
                centre = (middle.x, middle.y, middle.y)
            } else {
                let angle = SurfaceGeometry.start + (Double(index) / Double(hubs.count)) * fullTurn
                centre = SurfaceGeometry.at(angle, staggered(hubRing, index))
            }
            placed.append(moved(hub, to: centre))
            let held = orbits[hub.id] ?? []
            placed += ringAround(held, radius: orbitOf(held.count), centre: (centre.x, centre.y))
        }
        placed += ringAround(loose, radius: hubs.isEmpty ? hubRing : looseRing, centre: middle)
        return placed
    }

    private static func ringAround(_ members: [MemoryMapNode], radius: Double, centre: (x: Double, y: Double)) -> [MemoryMapNode] {
        let angles = SurfaceGeometry.fan(SurfaceGeometry.start, fullTurn, members.count, whole: true)
        return zip(members, angles).enumerated().map { spoke, pair in
            moved(pair.0, to: SurfaceGeometry.at(pair.1, staggered(radius, spoke), centre: centre))
        }
    }

    private static func moved(_ node: MemoryMapNode, to spot: (x: Double, y: Double, depth: Double)) -> MemoryMapNode {
        var node = node
        node.place.x = spot.x
        node.place.y = spot.y
        node.place.depth = spot.depth
        return node
    }

    private static func staggered(_ radius: Double, _ index: Int) -> Double {
        index % 2 == 1 ? radius * stagger : radius
    }

    private static func orbitOf(_ memories: Int) -> Double {
        min(orbitMost, max(orbitLeast, orbitLeast + Double(memories) * orbitPer))
    }

    /// The map under a filter of where memory is held: the nodes it shows, and only the lines both of whose ends stay.
    public static func held(_ map: MemoryMap, _ filter: MemoryHomeFilter) -> MemoryMap {
        guard filter != .everything else { return map }
        let nodes = map.nodes.filter { filter.shows($0.home) }
        let kept = Set(nodes.map(\.id))
        return MemoryMap(nodes: nodes, edges: map.edges.filter { kept.contains($0.from) && kept.contains($0.to) })
    }

    /// What travels with a dragged hub: a document's citing facts and a project's conversations, or the cluster tears.
    public static func carriedWith(_ map: MemoryMap, _ id: String) -> [String] {
        guard let node = map.nodes.first(where: { $0.id == id }) else { return [] }
        let held: MemoryLinkKind
        switch node.kind {
        case .document: held = .cites
        case .workspace: held = .worksIn
        case .memory, .source, .rule, .conversation, .app, .decision, .person, .skill, .standing: return []
        }
        return map.edges.filter { $0.to == id && $0.kind == held }.map(\.from)
    }

    /// Every node one line from a node, with the line joining them, in walk order, so its details list what it is
    /// linked to.
    public static func linked(_ map: MemoryMap, _ id: String) -> [(node: MemoryMapNode, kind: MemoryLinkKind)] {
        var found: [String: MemoryLinkKind] = [:]
        for edge in map.edges {
            if edge.from == id, found[edge.to] == nil { found[edge.to] = edge.kind }
            if edge.to == id, found[edge.from] == nil { found[edge.from] = edge.kind }
        }
        let order = walkOrder(map)
        let byId = Dictionary(map.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return order.compactMap { other in
            guard let kind = found[other], let node = byId[other] else { return nil }
            return (node, kind)
        }
    }

    /// The order the arrow keys walk the map in: facts first, as listed, then what they cite, then where they were said.
    public static func walkOrder(_ map: MemoryMap) -> [String] {
        let rank: [MemoryMapNodeKind: Int] = [.memory: 0, .rule: 1, .document: 2, .source: 3, .conversation: 4,
                                              .workspace: 5, .app: 6, .decision: 7, .person: 8, .skill: 9, .standing: 10]
        return map.nodes.sorted { left, right in
            let a = rank[left.kind] ?? 0
            let b = rank[right.kind] ?? 0
            return a == b ? left.id < right.id : a < b
        }.map(\.id)
    }
}
