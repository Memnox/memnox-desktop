import Foundation

// The memory map widened to everything memory is made of on this Mac: what was learned and what it was read out of,
// the conversations agents held, the projects those ran in, and the person's own apps whose calls fed memory. **The
// agents are never nodes**: memory is the content, and an agent is only who used a piece of it, said in that piece's
// details. **Every line is still a field on a record**: a fact cites a document, a conversation's folder sits inside
// a project's path, a call names the conversation that made it and the app it read. Nothing is linked because two
// things merely look alike. Every node is placed on the memory sphere by the group it came from.

/// An agent found on this Mac, as the graph needs it: only to name who used a piece of memory.
public struct LocalAgent: Equatable, Sendable {
    public let kind: String
    public let name: String
    public let status: String?
    /// The hub's servers given to it, by name.
    public let mcpServers: [String]

    public init(kind: String, name: String, status: String? = nil, mcpServers: [String] = []) {
        self.kind = kind
        self.name = name
        self.status = status
        self.mcpServers = mcpServers
    }

    public init(_ standing: AgentStanding) {
        self.init(kind: standing.kind, name: standing.name, status: standing.status, mcpServers: standing.mcpServers)
    }
}

/// One session of an agent, which is both the work it is doing and the conversation it is having.
public struct LocalSession: Equatable, Sendable {
    public let id: String
    /// The agent's kind, or its name from a daemon older than the kind.
    public let agent: String
    public let agentName: String
    /// What the session is about, as its agent titles it or as the person declared it.
    public let title: String?
    public let state: String
    /// The folder it runs in, as its hook saw it.
    public let folder: String?

    public init(id: String, agent: String, agentName: String, title: String? = nil, state: String, folder: String? = nil) {
        self.id = id
        self.agent = agent
        self.agentName = agentName
        self.title = title
        self.state = state
        self.folder = folder
    }

    public init(_ card: SessionCard) {
        let title = [card.focus, card.task].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
        self.init(id: card.sessionId, agent: card.agent ?? card.agentName, agentName: card.agentName, title: title,
                  state: card.state, folder: card.host?.cwd)
    }
}

/// One of the person's own connected apps.
public struct LocalApp: Equatable, Sendable {
    public let slug: String
    public let name: String
    /// The agents that worked in it through Memnox lately, and in which session, from the connections list.
    public let uses: [AppUse]

    public init(slug: String, name: String, uses: [AppUse] = []) {
        self.slug = slug
        self.name = name
        self.uses = uses
    }

    public init(_ card: YourAppCard) {
        self.init(slug: card.slug, name: card.name, uses: card.uses)
    }
}

/// Everything the local graph is drawn from, each list as this Mac already reads it.
public struct LocalGraphInputs: Equatable, Sendable {
    public var items: [MemoryItemView]
    public var sources: [MemorySourceView]
    /// Read only to name who used what; an agent is never drawn.
    public var agents: [LocalAgent]
    public var sessions: [LocalSession]
    public var apps: [LocalApp]
    /// What the workspace settled and its tools said, as this machine last pulled it; nil where none was pulled.
    public var workspace: WorkspaceMemoryView?
    /// The workspace's graph as the console draws it, which stands in for `workspace` wherever the runtime answered it.
    public var workspaceGraph: WorkspaceGraphView?
    /// The status chip chosen, which narrows the workspace's decisions as it narrows this Mac's facts; nil shows all.
    public var workspaceStatus: MemoryStatus?
    /// The skills the hub keeps and the agent folders hold, drawn at the brain's core.
    public var skills: [LocalSkill] = []
    /// The rules in force and standing permissions, the ring of what runs without the person.
    public var standings: [LocalStanding] = []
    /// The MCP servers the hub holds, drawn with the apps around the brain.
    public var servers: [LocalServer] = []

    public init(items: [MemoryItemView] = [], sources: [MemorySourceView] = [], agents: [LocalAgent] = [],
                sessions: [LocalSession] = [], apps: [LocalApp] = [], workspace: WorkspaceMemoryView? = nil,
                workspaceGraph: WorkspaceGraphView? = nil, workspaceStatus: MemoryStatus? = nil, skills: [LocalSkill] = [],
                standings: [LocalStanding] = [], servers: [LocalServer] = []) {
        self.skills = skills
        self.standings = standings
        self.servers = servers
        self.items = items
        self.sources = sources
        self.agents = agents
        self.sessions = sessions
        self.apps = apps
        self.workspace = workspace
        self.workspaceGraph = workspaceGraph
        self.workspaceStatus = workspaceStatus
    }
}

public enum LocalGraphs {
    /// An MCP source's location names its hub server after this, as the runtime writes it.
    public static let hubScheme = "mcp://"
    /// What the runtime calls an agent it could not tell, which names nobody and so is never said as a name.
    public static let unnamedAgent = "unknown"

    public static func conversationId(_ session: String) -> String { "conv:\(session)" }
    public static func appId(_ slug: String) -> String { "app:\(slug)" }
    public static func workspaceId(_ path: String) -> String { "ws:\(path)" }

    /// The local graph: the memory map with the conversations, projects and apps memory came through, and each line read
    /// off a field.
    public static func map(_ inputs: LocalGraphInputs, kindLabel: (String) -> String) -> MemoryMap {
        let memory = MemoryMaps.map(inputs.items, sources: inputs.sources, kindLabel: kindLabel)
        var graph = Building(nodes: memory.nodes, edges: memory.edges)
        let name = namer(inputs)
        let workspaces = addWorkspaces(inputs, into: &graph)
        addConversations(inputs.sessions, workspaces: workspaces, name: name, into: &graph)
        addSources(inputs, workspaces: workspaces, kindLabel: kindLabel, name: name, into: &graph)
        addFacts(inputs, workspaces: workspaces, name: name, into: &graph)
        addApps(inputs, name: name, into: &graph)
        addCalls(inputs, name: name, into: &graph)
        addLayers(inputs, name: name, into: &graph)
        if let live = inputs.workspaceGraph {
            addLive(live, apps: inputs.apps, status: inputs.workspaceStatus, into: &graph)
        } else if let workspace = inputs.workspace {
            addWorkspace(workspace, apps: inputs.apps, status: inputs.workspaceStatus, into: &graph)
        }
        return MemoryMap(nodes: graph.finished(), edges: graph.edges)
    }

    /// The nodes and lines so far, each id once, a line only between two nodes on the map, and who used each node.
    struct Building {
        var nodes: [MemoryMapNode]
        var edges: [MemoryMapEdge]
        var known: Set<String>
        var joined: Set<String>
        var used: [String: [String]] = [:]

        init(nodes: [MemoryMapNode], edges: [MemoryMapEdge]) {
            self.nodes = nodes
            self.edges = edges
            known = Set(nodes.map(\.id))
            joined = Set(edges.map(\.id))
        }

        mutating func add(_ node: MemoryMapNode) {
            guard known.insert(node.id).inserted else { return }
            nodes.append(node)
        }

        /// Adds a node the workspace holds, or marks the one this Mac already drew as named by both.
        mutating func share(_ node: MemoryMapNode) {
            guard known.contains(node.id) else { return add(node) }
            guard let at = nodes.firstIndex(where: { $0.id == node.id }), nodes[at].home != node.home else { return }
            nodes[at].home = .both
        }

        mutating func link(_ from: String, _ to: String, _ kind: MemoryLinkKind) {
            guard known.contains(from), known.contains(to) else { return }
            let edge = MemoryMapEdge(from: from, to: to, kind: kind)
            guard joined.insert(edge.id).inserted else { return }
            edges.append(edge)
        }

        /// Says an agent used a node, once, in the order it was first seen doing so.
        mutating func use(_ id: String, by agent: String?) {
            guard let agent, known.contains(id), !(used[id] ?? []).contains(agent) else { return }
            used[id, default: []].append(agent)
        }

        mutating func relabel(_ id: String, _ label: String, detail: String?) {
            guard let at = nodes.firstIndex(where: { $0.id == id }) else { return }
            let node = nodes[at]
            let place = node.place
            nodes[at] = MemoryMapNode(place: Placed(id: place.id, x: place.x, y: place.y, depth: place.depth, width: place.width,
                                                    height: place.height, captioned: place.captioned, label: label, lift: place.lift),
                                      kind: node.kind, item: node.item, status: node.status, memoryKind: node.memoryKind,
                                      tainted: node.tainted, detail: detail, mark: node.mark)
            nodes[at].at = node.at
        }

        /// Every node carrying who used it; where it sits is the sphere's to say, from its group.
        func finished() -> [MemoryMapNode] {
            nodes.map { node in
                var finished = node
                finished.usedBy = used[node.id] ?? []
                return finished
            }
        }
    }

    /// Every project a source, a listed fact or a conversation names, drawn once each. A conversation's folder makes a
    /// project of its own only where no project already holds it. Answers the paths.
    private static func addWorkspaces(_ inputs: LocalGraphInputs, into graph: inout Building) -> [String] {
        let named = inputs.sources.compactMap(\.project) + inputs.items.compactMap(\.project)
        var paths = Set(named.compactMap(trimmed))
        // Shallowest first, so a session in a project's subfolder lands in the project another session opened.
        for folder in inputs.sessions.compactMap({ trimmed($0.folder) }).sorted(by: { $0.count < $1.count })
            where workspaceHolding(folder, Array(paths)) == nil {
            paths.insert(folder)
        }
        let sorted = paths.sorted()
        for path in sorted {
            graph.add(round(workspaceId(path), MemoryMaps.documentLabel(path), .workspace, detail: path))
        }
        return sorted
    }

    /// Each conversation that can be named, in the project its folder is in, used by the agent holding it.
    private static func addConversations(_ sessions: [LocalSession], workspaces: [String], name: (String?) -> String?,
                                         into graph: inout Building) {
        for session in sessions.sorted(by: { $0.id < $1.id }) {
            let agent = name(session.agent) ?? name(session.agentName)
            guard let label = conversationLabel(session, agent: agent) else { continue }
            let id = conversationId(session.id)
            graph.add(round(id, label, .conversation, detail: session.state))
            graph.use(id, by: agent)
            if let folder = trimmed(session.folder), let path = workspaceHolding(folder, workspaces) {
                graph.link(id, workspaceId(path), .worksIn)
                graph.use(workspaceId(path), by: agent)
            }
        }
    }

    /// What a conversation is called: its title, else the project it ran in, else whose it was. One with none of these
    /// says nothing anybody could find again, so it is left off.
    public static func conversationLabel(_ session: LocalSession, agent: String?) -> String? {
        if let title = trimmed(session.title) { return title }
        if let folder = trimmed(session.folder) { return "Work in \(MemoryMaps.documentLabel(folder))" }
        return agent.map { "\($0) conversation" }
    }

    /// Every listed source, cited or not, kept for its project, and used by the agents its hub server is given to.
    private static func addSources(_ inputs: LocalGraphInputs, workspaces: [String], kindLabel: (String) -> String,
                                   name: (String?) -> String?, into graph: inout Building) {
        let sources = inputs.sources.sorted { $0.id < $1.id }
        for source in sources where !graph.known.contains(MemoryMaps.sourceId(source.name)) && !graph.known.contains(MemoryMaps.sourceId(source.id)) {
            graph.add(round(MemoryMaps.sourceId(source.name), source.name, .source, detail: kindLabel(source.kind)))
        }
        for source in sources {
            let id = graph.known.contains(MemoryMaps.sourceId(source.name)) ? MemoryMaps.sourceId(source.name) : MemoryMaps.sourceId(source.id)
            if let project = trimmed(source.project), workspaces.contains(project) { graph.link(id, workspaceId(project), .within) }
            guard let server = hubServer(source) else { continue }
            for agent in inputs.agents where agent.mcpServers.contains(server) { graph.use(id, by: name(agent.kind)) }
        }
    }

    /// A fact's project where no source it cites already carries it there, and the agents that suggested it or that
    /// its rule binds.
    private static func addFacts(_ inputs: LocalGraphInputs, workspaces: [String], name: (String?) -> String?,
                                 into graph: inout Building) {
        for item in inputs.items {
            graph.use(item.id, by: name(item.suggestedBy))
            for bound in item.rule?.agents ?? [] { graph.use(MemoryMaps.ruleId(item.id), by: name(bound)) }
            guard let project = trimmed(item.project), workspaces.contains(project) else { continue }
            let cited = Set(item.evidence.map(\.source))
            let carried = inputs.sources.contains { ($0.project == project) && (cited.contains($0.name) || cited.contains($0.id)) }
            if !carried { graph.link(item.id, workspaceId(project), .within) }
        }
    }

    /// The apps whose calls fed memory: one an agent worked in through Memnox, or one a fact's evidence was read from.
    /// An app nothing has used yet holds no memory, so it is not drawn.
    private static func addApps(_ inputs: LocalGraphInputs, name: (String?) -> String?, into graph: inout Building) {
        let cited = Set(inputs.items.flatMap(\.evidence).compactMap { $0.call?.app })
        for app in inputs.apps.sorted(by: { $0.slug < $1.slug }) where !app.uses.isEmpty || cited.contains(app.slug) {
            let id = appId(app.slug)
            graph.add(round(id, app.name, .app, mark: app.slug))
            for use in app.uses {
                graph.use(id, by: name(use.agent))
                if let session = use.sessionId { graph.link(conversationId(session), id, .reads) }
            }
        }
    }

    /// A document read from an agent's call is the call itself, so it is named for its tool and joined to the
    /// conversation that made it and the app it read.
    private static func addCalls(_ inputs: LocalGraphInputs, name: (String?) -> String?, into graph: inout Building) {
        for item in inputs.items {
            for evidence in item.evidence {
                guard let call = evidence.call else { continue }
                let document = MemoryMaps.documentId(source: evidence.source, document: evidence.document)
                let agent = name(call.agent)
                graph.relabel(document, call.tool, detail: call.app ?? call.server ?? evidence.source)
                graph.use(document, by: agent)
                graph.use(item.id, by: agent)
                graph.use(MemoryMaps.sourceId(evidence.source), by: agent)
                if let app = call.app {
                    graph.link(document, appId(app), .heldIn)
                    graph.use(appId(app), by: agent)
                }
                if let session = call.sessionId { graph.link(conversationId(session), document, .reads) }
            }
        }
    }

    /// An agent said by its name, from its kind or its name as any record writes it; nil for one the runtime could not
    /// tell, which names nobody.
    private static func namer(_ inputs: LocalGraphInputs) -> (String?) -> String? {
        var names: [String: String] = [:]
        for agent in inputs.agents {
            names[agent.kind] = agent.name
            names[agent.name] = agent.name
        }
        for session in inputs.sessions {
            if names[session.agent] == nil { names[session.agent] = session.agentName }
            if names[session.agentName] == nil { names[session.agentName] = session.agentName }
        }
        return { key in
            guard let key = trimmed(key), let said = trimmed(names[key] ?? key), said.lowercased() != unnamedAgent else { return nil }
            return said
        }
    }

    /// The hub server an MCP source reads, from the location the runtime wrote for it.
    public static func hubServer(_ source: MemorySourceView) -> String? {
        guard source.sourceKind == .mcp, source.location.hasPrefix(hubScheme) else { return nil }
        return trimmed(String(source.location.dropFirst(hubScheme.count)))
    }

    /// The most particular workspace a folder is inside: the path itself or one of its parents.
    public static func workspaceHolding(_ folder: String, _ workspaces: [String]) -> String? {
        workspaces.filter { folder == $0 || folder.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }.max { $0.count < $1.count }
    }

    static func round(_ id: String, _ label: String, _ kind: MemoryMapNodeKind, detail: String? = nil,
                              mark: String? = nil) -> MemoryMapNode {
        let place = Placed(id: id, x: SurfaceGeometry.layoutMiddle, y: SurfaceGeometry.layoutMiddle, depth: SurfaceGeometry.layoutMiddle,
                           width: MemoryMaps.Size.source, label: label)
        return MemoryMapNode(place: place, kind: kind, item: nil, status: nil, memoryKind: nil, tainted: false, detail: detail, mark: mark)
    }

    static func trimmed(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
