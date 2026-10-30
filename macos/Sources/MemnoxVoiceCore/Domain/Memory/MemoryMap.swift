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
        blank(item.id, item.statement, .memory, item: item.id, status: item.status, memoryKind: item.kind, tainted: item.tainted)
    }

    /// A node before it is placed, sized for its kind. Cards write their own name; a source's hangs below it.
    private static func blank(_ id: String, _ label: String, _ kind: MemoryMapNodeKind, item: String? = nil, status: String? = nil,
                              memoryKind: String? = nil, tainted: Bool = false, detail: String? = nil) -> MemoryMapNode {
        let place: Placed
        switch kind {
        case .source:
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

    /// What travels with a dragged document: the facts that cite it, or the cluster tears in half.
    public static func carriedWith(_ map: MemoryMap, _ id: String) -> [String] {
        guard let node = map.nodes.first(where: { $0.id == id }), node.kind == .document else { return [] }
        return map.edges.filter { $0.to == id && $0.kind == .cites }.map(\.from)
    }

    /// The order the arrow keys walk the map in: facts first, as listed, then what they cite.
    public static func walkOrder(_ map: MemoryMap) -> [String] {
        let rank: [MemoryMapNodeKind: Int] = [.memory: 0, .rule: 1, .document: 2, .source: 3]
        return map.nodes.sorted { left, right in
            let a = rank[left.kind] ?? 0
            let b = rank[right.kind] ?? 0
            return a == b ? left.id < right.id : a < b
        }.map(\.id)
    }
}
