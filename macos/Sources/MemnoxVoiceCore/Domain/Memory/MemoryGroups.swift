import Foundation

// Where each piece of memory came from, in the few groups the map colours, and what the map's overlays count off the
// record. **A piece takes its group from the line that joins it to where it was read**: a document from its source, a
// fact from the document it cites, a rule from the fact it governs, so a fact is always drawn with what it came out of.

/// Where a node's memory came from, in the order the legend lists them and a replay flies them in.
public enum SourceGroup: String, CaseIterable, Sendable {
    /// Notes the person keeps: Obsidian, Markdown folders, a Notion export, Supermemory.
    case notes
    /// The instruction files agents read: CLAUDE.md, AGENTS.md, GEMINI.md, Cursor's rules.
    case instructions
    /// Memory servers in the hub, read through one of their tools.
    case servers
    /// The conversations agents held, and what their calls read.
    case conversations
    /// The project folders memory is kept for.
    case projects
    /// The person's connected apps and the workspace's tools.
    case apps
    /// What came down from the workspace: decisions, the people they name, and what was said.
    case team
    /// A fact that cites nothing and is kept for no project.
    case unsourced
}

/// What the overlays count off the record: memories, the sources they came through, and the lines between.
public struct MemoryStats: Equatable, Sendable {
    public let memories: Int
    public let sources: Int
    public let connections: Int
}

public enum MemoryGroups {
    /// A replay flies one group in after another, this many seconds apart, each flight this long.
    public static let replayStagger: TimeInterval = 0.45
    public static let replayFlight: TimeInterval = 1.3
    /// The statuses a person is asked to look at: waiting to be confirmed, in conflict, or out of date.
    public static let attentionStatuses: Set<String> = [MemoryStatus.candidate.rawValue, MemoryStatus.conflicting.rawValue,
                                                         MemoryStatus.outdated.rawValue]

    /// The lines a node takes its group along, in the order they are asked: what a document was read from first, then
    /// what a fact cites, the rule it governs, the fact it restates, and the project it is kept for last.
    private static let inherits: [MemoryLinkKind] = [.heldIn, .cites, .governs, .restates, .pulledFrom, .within, .reads,
                                                     .worksIn, .linksTo, .relates, .said, .names, .confirmed, .memberOf]

    /// The group a source kind belongs to.
    public static func group(_ kind: MemorySourceKind) -> SourceGroup {
        switch kind {
        case .obsidian, .markdown, .notionExport, .supermemory: .notes
        case .instructions: .instructions
        case .mcp: .servers
        }
    }

    /// The group a node is in by its own kind alone, nil for one that takes its group from what it is linked to.
    private static func own(_ node: MemoryMapNode, sources: [MemorySourceView]) -> SourceGroup? {
        switch node.kind {
        case .app: return .apps
        case .decision, .person: return .team
        case .document, .memory, .rule, .conversation, .source, .workspace, .skill, .standing: break
        }
        if node.home == .workspace { return .team }
        switch node.kind {
        case .conversation: return .conversations
        case .workspace: return .projects
        case .source:
            let known = sources.first { MemoryMaps.sourceId($0.name) == node.id || MemoryMaps.sourceId($0.id) == node.id }
            return known?.sourceKind.map(group) ?? .notes
        case .document, .memory, .rule, .app, .decision, .person, .skill, .standing: return nil
        }
    }

    /// Every node's group: a source, a conversation, a project, an app and the workspace's own by their kind, and every
    /// document, fact and rule by the line that joins it to one of those.
    public static func groups(_ map: MemoryMap, sources: [MemorySourceView]) -> [String: SourceGroup] {
        var seeds: [String: SourceGroup] = [:]
        for node in map.nodes {
            if let own = own(node, sources: sources) { seeds[node.id] = own }
        }
        var groups = inherit(map, from: seeds)
        for node in map.nodes where groups[node.id] == nil { groups[node.id] = .unsourced }
        return groups
    }

    /// Every node that can reach a seeded node takes that seed's value, one kind of line at a time, so a fact waits for
    /// the document it cites before the project it is kept for is asked, and a rule follows the fact it governs. A node
    /// that reaches no seed is left out.
    public static func inherit<Value>(_ map: MemoryMap, from seeds: [String: Value]) -> [String: Value] {
        var values = seeds
        var near: [String: [(other: String, rank: Int)]] = [:]
        for edge in map.edges {
            let rank = inherits.firstIndex(of: edge.kind) ?? inherits.count
            near[edge.from, default: []].append((edge.to, rank))
            near[edge.to, default: []].append((edge.from, rank))
        }
        for id in near.keys { near[id]?.sort { $0.rank < $1.rank } }
        var open = map.nodes.map(\.id).filter { values[$0] == nil }
        for level in 0...inherits.count {
            while !open.isEmpty {
                var settled: [String: Value] = [:]
                for id in open {
                    let found = near[id]?.lazy.filter { $0.rank <= level }.compactMap { values[$0.other] }.first
                    if let found { settled[id] = found }
                }
                if settled.isEmpty { break }
                values.merge(settled) { first, _ in first }
                open.removeAll { settled[$0] != nil }
            }
        }
        return values
    }

    /// How many lines touch each node.
    public static func degrees(_ map: MemoryMap) -> [String: Int] {
        var degree: [String: Int] = [:]
        for edge in map.edges {
            degree[edge.from, default: 0] += 1
            degree[edge.to, default: 0] += 1
        }
        return degree
    }

    /// How far a group has flown in during a replay, from 0 at the middle to 1 in place, eased at both ends; each
    /// group sets off after the one before it.
    public static func arrival(_ index: Int, seconds: Double) -> Double {
        let share = min(max((seconds - Double(index) * replayStagger) / replayFlight, 0), 1)
        return share * share * (3 - 2 * share)
    }

    /// How long a replay of this many groups takes, so the clock stops once the last has landed.
    public static func replayLength(_ groups: Int) -> TimeInterval {
        Double(max(groups - 1, 0)) * replayStagger + replayFlight
    }

    /// Whether a node is one a person is asked to look at.
    public static func needsAttention(_ node: MemoryMapNode) -> Bool {
        node.status.map(attentionStatuses.contains) ?? false
    }

    /// Only what needs attention, with everything one line from it so each stays with what it was read from.
    public static func attention(_ map: MemoryMap) -> MemoryMap {
        var kept = Set(map.nodes.filter(needsAttention).map(\.id))
        let asked = kept
        for edge in map.edges {
            if asked.contains(edge.from) { kept.insert(edge.to) }
            if asked.contains(edge.to) { kept.insert(edge.from) }
        }
        return keeping(map, kept)
    }

    /// The map less the groups taken off it, and only the lines both of whose ends stay.
    public static func without(_ map: MemoryMap, hidden: Set<SourceGroup>, groups: [String: SourceGroup]) -> MemoryMap {
        guard !hidden.isEmpty else { return map }
        return keeping(map, Set(map.nodes.map(\.id).filter { !hidden.contains(groups[$0] ?? .unsourced) }))
    }

    private static func keeping(_ map: MemoryMap, _ kept: Set<String>) -> MemoryMap {
        MemoryMap(nodes: map.nodes.filter { kept.contains($0.id) },
                  edges: map.edges.filter { kept.contains($0.from) && kept.contains($0.to) })
    }

    /// Each present group with how many nodes it holds, in group order, for the legend.
    public static func legend(_ map: MemoryMap, groups: [String: SourceGroup]) -> [(group: SourceGroup, count: Int)] {
        var counts: [SourceGroup: Int] = [:]
        for node in map.nodes { counts[groups[node.id] ?? .unsourced, default: 0] += 1 }
        return SourceGroup.allCases.compactMap { group in counts[group].map { (group, $0) } }
    }

    /// The headline's counts: what was learned or settled, what it was read through, and every line on the map.
    public static func stats(_ map: MemoryMap) -> MemoryStats {
        let memories = map.nodes.filter { $0.kind == .memory || $0.kind == .decision }.count
        let sources = map.nodes.filter { $0.kind == .source || $0.kind == .app }.count
        return MemoryStats(memories: memories, sources: sources, connections: map.edges.count)
    }

    /// How much of what was learned is verified: off the sources' own counts, which every status adds to whatever
    /// the page filters, and off the map's facts where no source counted any.
    public static func growth(_ map: MemoryMap, sources: [MemorySourceView]) -> (verified: Int, total: Int) {
        let counted = sources.map(\.counts)
        let total = counted.reduce(0) { $0 + $1.candidate + $1.verified + $1.conflicting + $1.outdated + $1.rejected }
        if total > 0 { return (counted.reduce(0) { $0 + $1.verified }, total) }
        let facts = map.nodes.filter { $0.kind == .memory || $0.kind == .decision }
        return (facts.filter { $0.status == MemoryStatus.verified.rawValue }.count, facts.count)
    }
}
