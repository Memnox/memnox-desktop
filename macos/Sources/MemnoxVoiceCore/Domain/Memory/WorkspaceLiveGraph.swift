import Foundation

// The workspace's graph as the console draws it, folded into the local graph: each tool things arrived through, what
// arrived, who said it and how often, and what the team settled out of it. **Every line is still a line the runtime
// sent**, mapped onto the lines this map already draws, and a tool is the same node as this Mac's app of that slug, which
// is how the team's memory joins this Mac's. The status chip narrows the decisions; what arrived stays drawn, since the
// console shows it before anything is settled.

extension LocalGraphs {
    /// A live node's id on the map, apart from every id this Mac's own memory uses.
    public static func liveId(_ id: String) -> String { "wsg:\(id)" }

    static func addLive(_ view: WorkspaceGraphView, apps: [LocalApp], status: MemoryStatus?, into graph: inout Building) {
        let names = Dictionary(apps.map { ($0.slug, $0.name) }, uniquingKeysWith: { first, _ in first })
        var ids: [String: String] = [:]
        var tools: Set<String> = []
        for node in view.nodes.sorted(by: { $0.id < $1.id }) {
            guard let kind = node.nodeKind, WorkspaceLiveLines.shows(node, under: status) else { continue }
            var drawn = liveNode(node, kind: kind, names: names)
            drawn.home = .workspace
            graph.share(drawn)
            ids[node.id] = drawn.id
            if kind == .source { tools.insert(drawn.id) }
        }
        for link in view.links {
            guard let kind = link.linkKind, let from = ids[link.from], let to = ids[link.to] else { continue }
            let line = mapLine(kind, from: from, to: to, toolTarget: tools.contains(to))
            graph.link(line.from, line.to, line.kind)
        }
        // A decision read out of a link whose host names a tool hangs off that tool, as the saved facts do.
        for node in view.nodes {
            guard let id = ids[node.id], node.nodeKind == .decision || node.nodeKind == .candidate,
                  let tool = node.href.flatMap(WorkspaceMemoryLines.toolOf) else { continue }
            pulled(id, from: tool, names: names, into: &graph)
        }
    }

    private static func liveNode(_ node: WorkspaceGraphNode, kind: WorkspaceNodeKind, names: [String: String]) -> MemoryMapNode {
        let tool = trimmed(node.tool)?.lowercased()
        let mapKind = mapKind(kind)
        let id = kind == .source ? appId(tool ?? node.label.lowercased()) : liveId(node.id)
        let label: String
        switch kind {
        case .source: label = names[tool ?? ""] ?? WorkspaceMemoryLines.toolName(tool ?? node.label.lowercased())
        case .decision, .candidate: label = trimmed(node.statement) ?? node.label
        case .document, .passage, .conversation, .person, .bot, .group, .policy: label = node.label
        }
        let place = Placed(id: id, x: SurfaceGeometry.layoutMiddle, y: SurfaceGeometry.layoutMiddle,
                           depth: SurfaceGeometry.layoutMiddle, width: MemoryMaps.Size.source, label: label)
        let mark = tool.flatMap { WorkspaceMemoryLines.isTool($0) ? $0 : nil }
        var drawn = MemoryMapNode(place: place, kind: mapKind, item: nil, status: liveStatus(node)?.rawValue, memoryKind: nil,
                                  tainted: node.untrusted, detail: WorkspaceLiveLines.detail(node, kind: kind), mark: mark)
        drawn.live = node
        drawn.count = node.count
        drawn.weight = node.weight
        return drawn
    }

    /// The map kind each live kind is drawn as: a tool beside this Mac's apps, what arrived as a document, and people
    /// and what the team settled as the workspace's own.
    static func mapKind(_ kind: WorkspaceNodeKind) -> MemoryMapNodeKind {
        switch kind {
        case .source: .app
        case .document, .passage, .conversation: .document
        case .person, .bot, .group: .person
        case .policy, .decision, .candidate: .decision
        }
    }

    /// A live decision's standing as this map's status, nil for what is no decision.
    static func liveStatus(_ node: WorkspaceGraphNode) -> MemoryStatus? {
        switch node.nodeStatus {
        case .verified: .verified
        case .candidate: .candidate
        case nil: nil
        }
    }

    /// The runtime's line as one this map draws, turned to read the way the map's own lines read.
    static func mapLine(_ kind: WorkspaceLinkKind, from: String, to: String,
                        toolTarget: Bool) -> (from: String, to: String, kind: MemoryLinkKind) {
        switch kind {
        // A tool carries a thing and a thing contains a passage; the map says the piece was read out of the whole.
        case .carries, .contains: (to, from, .heldIn)
        case .said: (from, to, .said)
        case .mentions, .answersFor, .names: (from, to, .names)
        case .memberOf, .reportsTo: (from, to, .memberOf)
        case .approved: (from, to, .confirmed)
        case .linksTo: (from, to, .linksTo)
        case .relates: (from, to, .relates)
        case .readFrom, .about: (from, to, toolTarget ? .pulledFrom : .cites)
        }
    }
}
