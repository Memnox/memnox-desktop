import Foundation

// The workspace's memory folded into the local graph, as this machine last pulled it: each decision the team settled
// or a connected tool said, the tool it was read out of, and the people it names. **Every line is still a field on the
// record**: a candidate names its tools and who said it, a fact its owner and who confirmed it, and a link's host names
// the tool it lives in. A workspace tool and an app this Mac uses are one node when they are one toolkit slug, which
// is how the team's memory joins this Mac's. Nothing local goes up; this is only what came down.

extension LocalGraphs {
    public static func decisionId(_ id: String) -> String { "wsm:\(id)" }
    /// One person however the record capitalises them, since a tool and a confirm may write the same name two ways.
    public static func personId(_ name: String) -> String { "person:\(name.lowercased())" }

    /// Every settled fact and every candidate, each with its tools and its people, held by the workspace.
    static func addWorkspace(_ memory: WorkspaceMemoryView, apps: [LocalApp], status: MemoryStatus? = nil,
                             into graph: inout Building) {
        let names = Dictionary(apps.map { ($0.slug, $0.name) }, uniquingKeysWith: { first, _ in first })
        for fact in memory.facts.sorted(by: { $0.id < $1.id }) where status == nil || status == .verified {
            let id = decision(.settled(fact), status: .verified, tainted: false, into: &graph)
            if let tool = fact.sourceRef.flatMap(WorkspaceMemoryLines.toolOf) {
                pulled(id, from: tool, names: names, into: &graph)
            }
            if let principal = trimmed(fact.principal) { person(principal, id, .names, into: &graph) }
            if let confirmer = trimmed(fact.verifiedBy) { person(confirmer, id, .confirmed, into: &graph) }
        }
        for candidate in memory.unconfirmed.sorted(by: { $0.id < $1.id }) where status == nil || status == .candidate {
            let id = decision(.unconfirmed(candidate), status: .candidate, tainted: candidate.untrusted, into: &graph)
            var tools = candidate.sources.compactMap(trimmed).map { $0.lowercased() }
            if tools.isEmpty, let tool = candidate.sourceRef.flatMap(WorkspaceMemoryLines.toolOf) { tools = [tool] }
            for tool in tools { pulled(id, from: tool, names: names, into: &graph) }
            for said in candidate.saidBy.compactMap(trimmed) { person(said, id, .said, into: &graph) }
            if let principal = trimmed(candidate.principal) { person(principal, id, .names, into: &graph) }
        }
    }

    private static func decision(_ entry: WorkspaceEntry, status: MemoryStatus, tainted: Bool, into graph: inout Building) -> String {
        let id = decisionId(entry.id)
        let place = Placed(id: id, x: SurfaceGeometry.layoutMiddle, y: SurfaceGeometry.layoutMiddle, depth: SurfaceGeometry.layoutMiddle,
                           width: MemoryMaps.Size.source, label: entry.statement)
        var node = MemoryMapNode(place: place, kind: .decision, item: nil, status: status.rawValue, memoryKind: nil, tainted: tainted,
                                 detail: WorkspaceMemoryLines.standing(entry))
        node.home = .workspace
        node.workspace = entry
        graph.share(node)
        return id
    }

    /// The tool a decision was read out of, the same node as this Mac's app of that slug where it has one.
    static func pulled(_ id: String, from tool: String, names: [String: String], into graph: inout Building) {
        let label = names[tool] ?? WorkspaceMemoryLines.toolName(tool)
        var node = round(appId(tool), label, .app, detail: WorkspaceMemoryLines.toolDetail,
                         mark: WorkspaceMemoryLines.isTool(tool) ? tool : nil)
        node.home = .workspace
        graph.share(node)
        graph.link(id, appId(tool), .pulledFrom)
    }

    /// A person, drawn once, joined to a decision the way the record joins them: who said it and who confirmed it point
    /// at it, and a decision points at whom it names.
    private static func person(_ name: String, _ id: String, _ kind: MemoryLinkKind, into graph: inout Building) {
        var node = round(personId(name), name, .person, detail: WorkspaceMemoryLines.personDetail)
        node.home = .workspace
        graph.share(node)
        switch kind {
        case .names: graph.link(id, personId(name), kind)
        case .said, .confirmed: graph.link(personId(name), id, kind)
        case .cites, .heldIn, .governs, .restates, .worksIn, .reads, .within, .pulledFrom, .memberOf, .linksTo, .relates: return
        }
    }
}
