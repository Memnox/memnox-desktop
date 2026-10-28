import AppKit
import MemnoxVoiceCore
import SwiftUI

/// Memory for the views: redrawn whenever the core's memory changes, with the line the last press ended in.
@MainActor
final class MemoryScreen: ObservableObject {
    let memory: Memory
    /// Bumped when memory changes, so every view reading it is drawn again.
    @Published private(set) var tick = 0
    /// What the last press came to, shown above the page until the next one.
    @Published var note: String?

    /// What signs a rule a confirm raises, named in every line that says so.
    static let keyTitle = "Touch ID"

    init(memory: Memory) {
        self.memory = memory
        memory.changed = { [weak self] in
            Task { @MainActor [weak self] in self?.tick += 1 }
        }
    }

    /// Runs one press and says how it ended above the page.
    func press(_ work: @escaping (Memory) async -> MemoryOutcome, then: ((MemoryOutcome) -> Void)? = nil) {
        Task {
            let outcome = await work(memory)
            note = outcome.note
            then?(outcome)
        }
    }
}

extension Tone {
    init(_ tone: MemoryTone) {
        switch tone {
        case .good: self = .good
        case .attention: self = .attention
        case .bad: self = .bad
        case .quiet: self = .quiet
        }
    }
}

private enum MemoryLayout {
    static let searchWidth: CGFloat = 300
    /// Whether memory is drawn as the graph or read as the list, remembered for the next visit.
    static let viewKey = "memnox.memory.shown"
    static let switchHeight: CGFloat = 28
    static let switchPadding: CGFloat = 4
    /// How long typing rests before the search is asked, so each key is not a request.
    static let searchRest: Duration = .milliseconds(300)
    /// The Inputs tab the memory sources page is routed under.
    static let sourcesTab = "sources"
    /// The tab the Skills Hub is routed under.
    static let skillsTab = "skills"
    /// Whose memory the graph draws, remembered for the next visit.
    static let homeKey = "memnox.memory.home"
}

/// What this Mac learned, led by the graph of it: what each fact cites and where that was read from, linked to the
/// conversations, projects and apps memory came through, with the list one press away and any piece with its evidence,
/// its links and the agents that used it in the details. The sources themselves live under Inputs. A statement is
/// shown whole.
struct MemoryDestination: View {
    @ObservedObject var screen: MemoryScreen
    @ObservedObject var shell: AppShellModel
    @ObservedObject var island: IslandModel
    let width: WidthClass
    @State private var status = MemoryStatus.verified
    @State private var scope: MemoryScope?
    @State private var query = ""
    @AppStorage(MemoryLayout.viewKey) private var view = MemoryView.graph
    @AppStorage(MemoryLayout.homeKey) private var home = MemoryHomeFilter.everything
    /// A document or a source picked on the graph, which is not an item and so is not the picked id.
    @State private var place: MemoryMapNode?
    /// The graph as it was when something on it was picked, so the details list what the piece is linked to.
    @State private var map: MemoryMap?
    /// The node picked on the brain, opened in a dialog over it rather than in the side details.
    @State private var opened: MapPick?

    private var filter: MemoryFilter {
        MemoryFilter(status: status, scope: scope, query: query.trimmingCharacters(in: .whitespaces).isEmpty ? nil : query)
    }

    var body: some View {
        let memory = screen.memory
        let listed = memory.facts
        let picked = listed?.items.first { $0.id == shell.inspecting }
        InspectorLayout(width: width, title: picked.map { MemoryLines.kindWord($0.kind) } ?? place.map { MapWords.kindWord($0.kind) },
                        close: { shell.inspecting = nil; place = nil }) {
            // The graph takes the whole panel edge to edge, the console's way, with the page's title, its controls and
            // the way to the sources floated over it; the list keeps the page.
            if view == .graph {
                graph(listed)
            } else if view == .layers, let layers = shell.memoryLayers {
                MemoryLayersPage(screen: layers, width: width) { viewSwitch }
            } else {
                ShellScroll(width: width) {
                    NoteBanner(text: screen.note)
                    ShellSection(title: "What your agents know") {
                        VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
                            filters
                            facts(listed)
                        }
                    }
                    sourcesLink
                }
            }
        } detail: {
            if let picked {
                VStack(alignment: .leading, spacing: Memnox.Spacing.xxLarge) {
                    FactInspector(screen: screen, item: picked) { shell.inspecting = nil }
                    if let map, let node = map.nodes.first(where: { $0.id == picked.id }) {
                        PlaceLinks(node: node, map: map) { pick($0, on: map) }
                    }
                }
                .id(picked.id)
            } else if let place {
                PlaceDetail(memory: memory, place: place, map: map, items: listed?.items ?? [], skills: shell.skills?.skills.hub,
                            rules: shell.studio?.studio.rules?.rules ?? [],
                            manage: { shell.go(WindowRoute(.workspaces, tab: MemoryLayout.sourcesTab)) },
                            openSkills: { shell.go(WindowRoute(.workspaces, tab: MemoryLayout.skillsTab)) },
                            open: { pick($0, on: map) })
                    .id(place.id)
            }
        }
        .task { await memory.refreshSources() }
        .task { await memory.refreshWorkspace() }
        .task(id: filter) {
            if filter.query != nil {
                try? await Task.sleep(for: MemoryLayout.searchRest)
                if Task.isCancelled { return }
            }
            await memory.show(filter)
        }
        // A signature on the island settles a rule, so the list is read again.
        .onChange(of: island.waiting.count) { Task { await memory.show(memory.filter) } }
    }

    /// Where the sources went: a quiet line that takes the person to them under Inputs.
    private var sourcesLink: some View {
        Button { shell.go(WindowRoute(.workspaces, tab: MemoryLayout.sourcesTab)) } label: {
            HStack(spacing: Memnox.Spacing.small) {
                Image(systemName: "books.vertical").accessibilityHidden(true)
                Text("Add or manage sources under Inputs")
            }
            .font(Memnox.Console.sans(Memnox.TextSize.footnote))
            .foregroundStyle(Memnox.Console.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHand()
    }

    /// A fact or a rule opens its fact in the details; anything else opens itself, with what it is linked to.
    private func pick(_ node: MemoryMapNode?, on picked: MemoryMap?) {
        map = picked
        guard let node else {
            place = nil
            shell.inspecting = nil
            return
        }
        if let item = node.item {
            pick(item)
        } else {
            place = node
            shell.inspecting = nil
        }
    }

    private func pick(_ item: String) {
        place = nil
        shell.inspecting = item
    }

    /// Graph or List, as the console's own segmented switch.
    private var viewSwitch: some View {
        HStack(spacing: Memnox.Spacing.xSmall) {
            ForEach(MemoryView.allCases, id: \.self) { each in
                let on = view == each
                Button { view = each } label: {
                    Label(each.title, systemImage: each.symbol)
                        .labelStyle(KitLabel())
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, on ? .medium : .regular))
                        .foregroundStyle(on ? Memnox.Console.foreground : Memnox.Console.muted)
                        .padding(.horizontal, Memnox.Spacing.large)
                        .frame(height: MemoryLayout.switchHeight)
                        .background(on ? Memnox.Console.active : Color.clear,
                                    in: RoundedRectangle(cornerRadius: Memnox.Console.controlRadius, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHand()
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(MemoryLayout.switchPadding)
        .background(Memnox.Console.card, in: RoundedRectangle(cornerRadius: Memnox.Console.controlRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Memnox.Console.controlRadius, style: .continuous)
            .strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Show memory as")
    }

    /// What the empty graph says: a first visit is told where memory comes from, a filter that matched nothing says
    /// so, and the workspace alone says how to join one or that nothing came down yet.
    private var emptyLine: String {
        if home == .workspace {
            let memory = screen.memory
            return memory.workspaceGraph.flatMap(WorkspaceLiveLines.emptyLine)
                ?? WorkspaceMemoryLines.emptyLine(joined: memory.joined, memory: memory.workspace)
                ?? "Nothing from your workspace matches."
        }
        if filter.query != nil { return "Nothing learned says that." }
        if status == .verified {
            return "Nothing learned yet. As your agents read sources, hold conversations and work in projects, memory fills this brain."
        }
        return "Nothing \(MemoryLines.statusWord(status.rawValue).word.lowercased()) here."
    }

    /// The search, the switch and the status chips on one row where the window is wide enough, so the graph below
    /// gets the height, and on two where it is not.
    private var filters: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Memnox.Spacing.medium) {
                SearchField(prompt: searchPrompt, text: $query).frame(width: MemoryLayout.searchWidth)
                viewSwitch
                statusRow
                Spacer(minLength: Memnox.Spacing.medium)
                homeRow
                scopeRow
            }
            stackedFilters
        }
    }

    /// The search names how much it reaches; on the brain the slash key searches the canvas instead.
    private var searchPrompt: String {
        guard view == .graph else { return "Search memory" }
        let count = screen.memory.facts?.items.count ?? 0
        return "Search \(count) \(count == 1 ? "memory" : "memories")"
    }

    /// Whose a fact is matters only once there is an organization beside the person.
    @ViewBuilder private var scopeRow: some View {
        if shell.hasOrganization {
            HStack(spacing: Memnox.Spacing.small) {
                MemoryChip(title: "Both", on: scope == nil) { scope = nil }
                ForEach(MemoryLines.scopes, id: \.scope) { each in
                    MemoryChip(title: each.label, on: scope == each.scope) { scope = each.scope }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Scope")
        }
    }

    /// Whose memory the graph draws: everything, this Mac's alone, or what came down from the workspace. Only the graph
    /// draws the workspace, so the list keeps this Mac's alone and no chip.
    @ViewBuilder private var homeRow: some View {
        if view == .graph {
            HStack(spacing: Memnox.Spacing.small) {
                ForEach(WorkspaceMemoryLines.filters, id: \.filter) { each in
                    MemoryChip(title: each.label, on: home == each.filter) { home = each.filter }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Whose memory")
        }
    }

    /// What the graph's heading says about the workspace: how to join one while this Mac is not joined, that its
    /// memory is on the way, when it was pulled and what the clearance kept back. Quiet while only this Mac is drawn.
    @ViewBuilder private var workspaceFoot: some View {
        let memory = screen.memory
        if home != .thisMac {
            if let line = WorkspaceMemoryLines.emptyLine(joined: memory.joined, memory: memory.workspace) {
                MemoryQuiet(line)
                if memory.joined == false {
                    Button("Open Account", systemImage: "person.crop.circle") { shell.go(page: .account) }
                        .buttonStyle(KitButton(kind: .secondary))
                }
            } else if let graph = memory.workspaceGraph {
                if let line = WorkspaceLiveLines.sourceLine(graph) { MemoryQuiet(line) }
                if graph.graphSource != .live, let pulled = memory.workspace, let line = WorkspaceMemoryLines.pulledLine(pulled) {
                    MemoryQuiet(line)
                }
                if graph.withheld > 0 { MemoryQuiet(WorkspaceMemoryLines.withheldLine(graph.withheld)) }
            } else if let pulled = memory.workspace {
                if let line = WorkspaceMemoryLines.pulledLine(pulled) { MemoryQuiet(line) }
                if pulled.withheld > 0 { MemoryQuiet(WorkspaceMemoryLines.withheldLine(pulled.withheld)) }
            }
            if memory.joined == true {
                // Reads the cloud again now, past the few seconds the runtime holds its last read.
                Button("Refresh from your workspace", systemImage: "arrow.clockwise") {
                    Task { await memory.refreshWorkspace(fresh: true) }
                }
                .buttonStyle(KitButton(kind: .secondary))
            }
            if memory.unreadable.workspace {
                ReadFailed(what: "your workspace's memory") { Task { await memory.refreshWorkspace() } }
            }
        }
    }

    /// The status chips while nothing is searched, and what the search is doing once something is.
    @ViewBuilder private var statusRow: some View {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            HStack(spacing: Memnox.Spacing.small) {
                ForEach(MemoryLines.filters, id: \.status) { each in
                    MemoryChip(title: each.label, on: status == each.status) { status = each.status }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Status")
        } else if let search = screen.memory.search {
            VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                MemoryQuiet("\(MemoryLines.searchModeLine(search.mode)), over every status.")
                if let note = search.note { MemoryQuiet(note) }
            }
        } else {
            MemoryQuiet("Searching every status for these words.")
        }
    }

    private var stackedFilters: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            HStack(spacing: Memnox.Spacing.medium) {
                SearchField(prompt: searchPrompt, text: $query).frame(maxWidth: MemoryLayout.searchWidth)
                viewSwitch
                Spacer(minLength: Memnox.Spacing.medium)
                scopeRow
            }
            HStack(spacing: Memnox.Spacing.medium) {
                statusRow
                Spacer(minLength: Memnox.Spacing.medium)
                homeRow
            }
        }
    }

    /// The canvas, standing even while empty or still reading so the page never looks broken, with the search and the
    /// filters along its top and the page's own lines in its heading card.
    private func graph(_ listed: MemoryItemsView?) -> some View {
        let memory = screen.memory
        return LocalMemoryMap(tools: island.tools, agents: shell.agents, skills: shell.skills, studio: shell.studio, hub: shell.hub,
                              sessions: island.cards, items: listed?.items ?? [],
                              sources: memory.sources ?? [], workspace: memory.workspace,
                              workspaceGraph: memory.workspaceGraph, status: filter.query == nil ? status : nil, shown: home,
                              selected: opened?.id,
                              empty: listed == nil ? nil : emptyLine, select: { node, map in opened = node.map { MapPick(node: $0, map: map) } }) {
            VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
                filters
                NoteBanner(text: screen.note)
                if memory.unreadable.facts {
                    ReadFailed(what: "what was learned") { Task { await memory.show(memory.filter) } }
                }
            }
        } foot: {
            VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
                if let listed, let more = MemoryLines.moreLine(listed.more) { MemoryQuiet(more) }
                workspaceFoot
                sourcesLink
            }
        } card: {
            if let each = opened {
                MapPickCard(screen: screen, pick: each, items: listed?.items ?? [], skills: shell.skills?.skills.hub,
                            rules: shell.studio?.studio.rules?.rules ?? [],
                            go: { route in
                                opened = nil
                                shell.go(route)
                            },
                            open: { node in opened = MapPick(node: node, map: each.map) },
                            close: { opened = nil })
            }
        }
    }

    @ViewBuilder private func facts(_ listed: MemoryItemsView?) -> some View {
        let memory = screen.memory
        if memory.unreadable.facts {
            ReadFailed(what: "what was learned") { Task { await memory.show(memory.filter) } }
        }
        if let listed {
            if listed.items.isEmpty {
                EmptyState(symbol: "brain",
                           title: filter.query == nil ? "Nothing \(MemoryLines.statusWord(status.rawValue).word.lowercased()) here" : "Nothing learned says that",
                           detail: "Add a source under Inputs and Memnox reads it with your own agent. What it finds waits in Learn until you confirm it.")
            } else {
                ShellPanel {
                    ForEach(Array(listed.items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { ShellDivider() }
                        let word = MemoryLines.statusWord(item.status)
                        ShellRow(title: item.statement, caption: MemoryLines.rowCaption(item), chosen: item.id == shell.inspecting,
                                 action: { pick(item.id) }) {
                            EmptyView()
                        } trailing: {
                            HStack(spacing: Memnox.Spacing.medium) {
                                ScopeChip(ScopeLines.memory(item))
                                if item.tainted { StatusWord(.attention, "Untrusted source") }
                                StatusWord(Tone(word.tone), word.word)
                            }
                        }
                    }
                }
            }
            if let more = MemoryLines.moreLine(listed.more) { MemoryQuiet(more) }
        }
    }
}

/// How memory is shown: drawn as the graph of what it was read out of, or read as the list.
private enum MemoryView: String, CaseIterable {
    case graph
    case list
    /// MEMORY.md, the router and the skills as three layers, with the short term card below them.
    case layers

    var title: String {
        switch self {
        case .graph: "Graph"
        case .list: "List"
        case .layers: "Layers"
        }
    }

    var symbol: String {
        switch self {
        case .graph: "point.3.connected.trianglepath.dotted"
        case .list: "list.bullet"
        case .layers: "square.stack.3d.up"
        }
    }
}

/// A piece of memory picked on the graph that is not a fact: what it is and what it says, the passage a document was
/// read from, a source's standing, the agents that used it, the facts joined to it and everything else it is linked
/// to, each a press that opens it, and where it lives, one press away.
private struct PlaceDetail: View {
    let memory: Memory
    let place: MemoryMapNode
    let map: MemoryMap?
    let items: [MemoryItemView]
    /// The Skills Hub as last read, for a skill's own instructions and where its file is.
    let skills: SkillsHubView?
    /// The rules in force, for a rule's own fields.
    let rules: [PolicyRuleView]
    /// Takes the person to the sources under Inputs, where a source is changed.
    let manage: () -> Void
    /// Takes the person to the Skills Hub, where a skill is changed.
    let openSkills: () -> Void
    let open: (MemoryMapNode) -> Void

    var body: some View {
        let document = place.kind == .document
        let evidence = items.flatMap(\.evidence).filter(cites)
        VStack(alignment: .leading, spacing: Memnox.Spacing.xxLarge) {
            VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
                HStack(spacing: Memnox.Spacing.small) {
                    Image(systemName: MapMark.symbol(place.kind))
                        .font(.system(size: Memnox.TextSize.footnote, weight: .medium))
                        .foregroundStyle(Memnox.Console.primary)
                        .accessibilityHidden(true)
                    Text(MapWords.kindWord(place.kind).uppercased())
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.label, .medium))
                        .tracking(PlaceHeading.tracking)
                        .foregroundStyle(Memnox.Console.muted)
                }
                Text(place.label)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.base, .medium))
                    .foregroundStyle(Memnox.Console.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if let said = said { MemoryQuiet(said) }
            }
            if !place.usedBy.isEmpty { FactList(facts: [("Used by", place.usedBy.joined(separator: ", "))]) }
            if document, let first = evidence.first {
                MemoryEvidence(memory: memory, evidence: [first])
                PathRow(path: MemoryLines.evidencePath(first, sources: memory.sources))
            }
            if place.kind == .skill {
                SkillPlace(skill: skills?.skills.first { LocalGraphs.skillId($0.name) == place.id },
                           path: LocalGraphs.skillPath(LocalGraphs.skills(skills), place.id), openSkills: openSkills)
            }
            if place.kind == .standing, let rule = rules.first(where: { LocalGraphs.standingId($0.name) == place.id }) {
                FactList(facts: [("Does", StudioLines.title(rule.effect)), ("Rule", rule.name), ("Set", StudioLines.sourceWords(rule))])
                if let file = rule.file { PathRow(path: file) }
            }
            if place.kind == .source, let source {
                FactList(facts: facts(source))
                Button("Manage under Inputs", systemImage: "books.vertical", action: manage).buttonStyle(KitButton(kind: .secondary))
            }
            if let live = place.live { LiveDetail(node: live) }
            if let entry = place.workspace {
                FactList(facts: WorkspaceMemoryLines.rows(entry))
                if let link = sourceLink(entry) {
                    Button("Open the source", systemImage: "link") { NSWorkspace.shared.open(link) }
                        .buttonStyle(KitButton(kind: .secondary))
                }
            }
            if place.kind == .workspace, let path = place.detail {
                Button("Show in Finder", systemImage: "folder") { reveal(path) }.buttonStyle(KitButton(kind: .secondary))
            }
            if let map { PlaceLinks(node: place, map: map, open: open) }
            if map == nil, let heading = relatedHeading, !related.isEmpty {
                PlaceSection(title: heading) {
                    ShellPanel {
                        ForEach(Array(related.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { ShellDivider() }
                            ShellRow(title: item.statement, caption: MemoryLines.statusWord(item.status).word, action: {}) {
                                EmptyView()
                            } trailing: {
                                EmptyView()
                            }
                        }
                    }
                }
            }
        }
    }

    /// What the piece is, said under its name: where a document sits, a source's kind, a project's path, where a
    /// conversation stands.
    private var said: String? {
        guard let detail = place.detail else { return nil }
        switch place.kind {
        case .document: return place.live == nil ? "Read from \(detail)" : detail
        case .conversation: return SessionState(rawValue: detail).map(Self.stateLine) ?? detail
        case .source, .workspace, .app, .memory, .rule, .decision, .person, .skill, .standing: return detail
        }
    }

    /// Where a conversation stands, said plainly.
    private static func stateLine(_ state: SessionState) -> String {
        switch state {
        case .working: "Working now"
        case .open: "Open, waiting on you"
        case .idle: "Idle"
        case .quiet: "Quiet"
        case .ended: "Ended"
        case .paused: "Paused"
        }
    }

    /// The facts listed that cite this document or were read from this source, for a graph that is not to hand.
    private var related: [MemoryItemView] {
        switch place.kind {
        case .document, .source: items.filter { $0.evidence.contains(where: cites) }
        case .workspace: items.filter { $0.project == place.detail }
        case .memory, .rule, .conversation, .app, .decision, .person, .skill, .standing: []
        }
    }

    private var relatedHeading: String? {
        switch place.kind {
        case .document: "Facts citing it"
        case .source: "Facts read from it"
        case .workspace: "Facts kept for it"
        case .memory, .rule, .conversation, .app, .decision, .person, .skill, .standing: nil
        }
    }

    private func cites(_ each: MemoryEvidenceView) -> Bool {
        place.kind == .document
            ? MemoryMaps.documentId(source: each.source, document: each.document) == place.id
            : MemoryMaps.sourceId(each.source) == place.id
    }

    private var source: MemorySourceView? {
        (memory.sources ?? []).first { MemoryMaps.sourceId($0.name) == place.id || MemoryMaps.sourceId($0.id) == place.id }
    }

    private func facts(_ source: MemorySourceView) -> [(String, String)] {
        [("Where", source.location), ("Trust", MemoryLines.trustWord(source.trust).word),
         ("Taught", MemoryLines.sourceCountsLine(source.counts)), ("Read", MemoryLines.lastReadLine(source, now: Date()))]
    }

    /// Where a workspace record was said, opened in the browser only when it is a secure link.
    private func sourceLink(_ entry: WorkspaceEntry) -> URL? {
        let ref: String?
        switch entry {
        case .settled(let fact): ref = fact.sourceRef
        case .unconfirmed(let candidate): ref = candidate.sourceRef
        }
        guard let ref, ref.hasPrefix(Self.secure) else { return nil }
        return URL(string: ref)
    }

    private static let secure = "https://"

    /// A project folder shown in Finder where it is still on this Mac.
    private func reveal(_ path: String) {
        guard FileManager.default.fileExists(atPath: path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

private enum PlaceHeading {
    /// A little tighter than a group heading's, since it sits inside the details.
    static let tracking = Memnox.Console.headingTracking * 0.8
}

/// A small capitalised heading over one part of the details.
private struct PlaceSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
            Text(title.uppercased())
                .font(Memnox.Console.sans(Memnox.Console.TextSize.label, .medium))
                .tracking(PlaceHeading.tracking)
                .foregroundStyle(Memnox.Console.muted)
                .accessibilityAddTraits(.isHeader)
            content
        }
    }
}

/// Everything a piece is linked to on the graph, grouped by its kind and said with the line that joins them, each a
/// press that opens it in these details.
struct PlaceLinks: View {
    let node: MemoryMapNode
    let map: MemoryMap
    let open: (MemoryMapNode) -> Void

    var body: some View {
        let linked = MemoryMaps.linked(map, node.id)
        if !linked.isEmpty {
            PlaceSection(title: "Linked to") {
                ShellPanel {
                    ForEach(Array(linked.enumerated()), id: \.element.node.id) { index, each in
                        if index > 0 { ShellDivider() }
                        ShellRow(title: each.node.label, caption: "\(MapWords.kindWord(each.node.kind)), \(MapInk.of(each.kind).label.lowercased())",
                                 action: { open(each.node) }) {
                            Image(systemName: MapMark.symbol(each.node.kind))
                                .font(.system(size: Memnox.TextSize.footnote))
                                .foregroundStyle(Memnox.Console.muted)
                                .accessibilityHidden(true)
                        } trailing: {
                            EmptyView()
                        }
                    }
                }
            }
        }
    }
}

/// One filter or scope as the console's chip, washed in its blue while it is chosen.
struct MemoryChip: View {
    let title: String
    let on: Bool
    let choose: () -> Void

    var body: some View {
        FilterChip(title: title, chosen: on, choose: choose)
    }
}

/// A quiet line of memory's details.
struct MemoryQuiet: View {
    let text: String
    var tint = Memnox.Console.muted

    init(_ text: String, tint: Color = Memnox.Console.muted) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text)
            .font(Memnox.Console.sans(Memnox.TextSize.footnote))
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One fact whole: its words as written, where it stands, who settled it, and every passage it was read from.
private struct FactInspector: View {
    @ObservedObject var screen: MemoryScreen
    let item: MemoryItemView
    let forgotten: () -> Void
    @State private var sure = false

    var body: some View {
        let word = MemoryLines.statusWord(item.status)
        VStack(alignment: .leading, spacing: Memnox.Spacing.xLarge) {
            Text(item.statement)
                .font(Memnox.Console.sans(Memnox.TextSize.body))
                .foregroundStyle(Memnox.Console.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            HStack(spacing: Memnox.Spacing.large) {
                StatusWord(Tone(word.tone), word.word)
                if item.tainted { StatusWord(.attention, MemoryLines.taintedLine) }
            }
            if let rule = item.rule { MemoryQuiet("What it governs: \(rule.sentence)", tint: Memnox.Console.foreground) }
            FactList(facts: facts)
            MemoryEvidence(memory: screen.memory, evidence: item.evidence)
            ShellDivider()
            HStack(spacing: Memnox.Spacing.medium) {
                if sure {
                    MemoryQuiet("Forgetting deletes it and its evidence for good.")
                    Spacer(minLength: Memnox.Spacing.medium)
                    Button("Keep it") { sure = false }.buttonStyle(KitButton(kind: .secondary))
                    Button("Forget", systemImage: "trash", action: forget)
                        .buttonStyle(KitButton(kind: .primary))
                        .disabled(screen.memory.busy == item.id)
                } else {
                    Button("Forget", systemImage: "trash") { sure = true }.buttonStyle(KitButton(kind: .secondary))
                }
            }
        }
    }

    private var facts: [(String, String)] {
        var rows = [("About", item.subject), ("Kept", MemoryLines.keptLine(item)), ("From", MemoryLines.originLine(item))]
        if let confidence = MemoryLines.confidenceLine(item.extractorConfidence) { rows.append(("Extractor", confidence)) }
        if let decided = MemoryLines.decidedLine(item, now: Date()) { rows.append(("Settled", decided)) }
        return rows
    }

    private func forget() {
        let id = item.id
        screen.press({ await $0.forget(id) }) { outcome in
            if case .failed = outcome { return }
            forgotten()
        }
    }
}

/// Where an item was read from, each piece a press: a link opens in the browser, and a file opens on this Mac, a folder
/// shown in Finder. A passage that changed since is marked.
struct MemoryEvidence: View {
    let memory: Memory
    let evidence: [MemoryEvidenceView]
    @State private var copied: String?

    private static let icon: CGFloat = 13

    var body: some View {
        if evidence.isEmpty {
            MemoryQuiet("No evidence: an agent suggested it without citing a passage.")
        } else {
            VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
                Text("Evidence")
                    .font(Memnox.Console.sans(Memnox.TextSize.footnote, .medium))
                    .foregroundStyle(Memnox.Console.muted)
                ForEach(Array(evidence.enumerated()), id: \.offset) { _, each in
                    row(each)
                }
            }
        }
    }

    private func row(_ each: MemoryEvidenceView) -> some View {
        let path = MemoryLines.evidencePath(each, sources: memory.sources)
        return Button { open(each, path: path) } label: {
            HStack(alignment: .firstTextBaseline, spacing: Memnox.Spacing.medium) {
                Image(systemName: each.url == nil ? "doc.text" : "link")
                    .font(.system(size: Self.icon))
                    .foregroundStyle(Memnox.Console.muted)
                    .accessibilityHidden(true)
                Text(MemoryLines.evidenceLine(each))
                    .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(each.stale ? Memnox.Console.muted : Memnox.Console.primary)
                    .strikethrough(each.stale, color: Memnox.Console.faint)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if each.stale { StatusWord(.quiet, "Stale") }
                if copied == each.ref { MemoryQuiet("Path copied") }
            }
            .padding(.horizontal, Memnox.Spacing.small)
            .padding(.vertical, Memnox.Spacing.xSmall)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverLight(radius: Memnox.radius, inset: 0)
        .help(each.url ?? path)
    }

    /// A secure link opens in the browser; a file this Mac holds opens in its app, and a folder is shown in Finder.
    private func open(_ each: MemoryEvidenceView, path: String) {
        if let url = each.url, url.hasPrefix("https://"), let link = URL(string: url) {
            NSWorkspace.shared.open(link)
            return
        }
        var folder: ObjCBool = false
        if LaunchLines.isAbsoluteFolder(path), FileManager.default.fileExists(atPath: path, isDirectory: &folder) {
            let file = URL(fileURLWithPath: path)
            if folder.boolValue {
                NSWorkspace.shared.activateFileViewerSelecting([file])
            } else {
                NSWorkspace.shared.open(file)
            }
            return
        }
        // A file that moved or a source that was removed still leaves its path, so the person can find it.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        copied = each.ref
    }
}

/// The graph fed what else memory came through on this Mac: the conversations, the person's apps, and the agents only to
/// name who used what, each list watched so the drawing follows it, and each read once when nothing has read it yet.
private struct LocalMemoryMap<Bar: View, Foot: View, Card: View>: View {
    @ObservedObject var tools: ToolsModel
    let agents: AgentsScreen?
    /// The Skills Hub, the rules and the MCP Hub, each watched so the brain's other layers follow them.
    let skills: SkillsScreen?
    let studio: StudioScreen?
    let hub: McpHubScreen?
    let sessions: [SessionCard]
    let items: [MemoryItemView]
    let sources: [MemorySourceView]
    /// What came down from the workspace, read off the runtime; nil where this Mac never pulled any.
    let workspace: WorkspaceMemoryView?
    /// The workspace's live graph, which stands in for `workspace` wherever the runtime answered it.
    let workspaceGraph: WorkspaceGraphView?
    /// The status chip, which narrows the workspace's decisions too; nil while a search reads every status.
    let status: MemoryStatus?
    let shown: MemoryHomeFilter
    let selected: String?
    let empty: String?
    let select: (MemoryMapNode?, MemoryMap) -> Void
    @ViewBuilder let bar: Bar
    @ViewBuilder let foot: Foot
    @ViewBuilder let card: Card

    var body: some View {
        Watching(skills) {
            Watching(studio) {
                Watching(hub) {
                    if let agents {
                        AgentsWatch(screen: agents) { standings in graph(standings) }
                    } else {
                        graph([])
                    }
                }
            }
        }
        .task {
            if tools.loading { tools.refresh() }
            if let agents, agents.agents.agents == nil { await agents.agents.refresh() }
        }
        .task { if let skills, skills.skills.hub == nil { await skills.skills.refresh() } }
        .task { if let studio, studio.studio.rules == nil { await studio.studio.refresh() } }
        .task { if let hub, hub.hub.hub == nil { await hub.hub.refresh() } }
    }

    private func graph(_ standings: [AgentStanding]) -> some View {
        let inputs = LocalGraphInputs(items: items, sources: sources, agents: standings.map(LocalAgent.init),
                                      sessions: sessions.map(LocalSession.init), apps: tools.yourApps.map(LocalApp.init),
                                      workspace: workspace, workspaceGraph: workspaceGraph, workspaceStatus: status,
                                      skills: LocalGraphs.skills(skills?.skills.hub),
                                      standings: (studio?.studio.rules?.rules ?? []).map(LocalStanding.init),
                                      servers: (hub?.hub.hub?.servers ?? []).map(LocalServer.init))
        // A conversation glowing on the island is at work, and sends a bead into the brain.
        let working = Set(sessions.filter(\.status.isActive).map { LocalGraphs.conversationId($0.sessionId) })
        return MemoryMapView(graph: inputs, shown: shown, working: working, selected: selected, empty: empty, select: select) { bar } foot: { foot } card: { card }
    }
}

/// Watches a screen that may not be there yet, drawing its content again whenever the screen changes.
private struct Watching<Model: ObservableObject, Content: View>: View {
    let model: Model?
    @ViewBuilder let content: () -> Content

    init(_ model: Model?, @ViewBuilder content: @escaping () -> Content) {
        self.model = model
        self.content = content
    }

    var body: some View {
        if let model {
            Watched(model: model, content: content)
        } else {
            content()
        }
    }
}

private struct Watched<Model: ObservableObject, Content: View>: View {
    @ObservedObject var model: Model
    @ViewBuilder let content: () -> Content

    var body: some View { content() }
}

/// A skill picked on the brain: its SKILL.md drawn formatted, from the hub's own copy or the agent folder's file on
/// this Mac, with the file opened or its path copied, and the hub one press away.
private struct SkillPlace: View {
    let skill: SkillView?
    let path: String?
    let openSkills: () -> Void
    @State private var document: SkillDocument?
    @State private var unreadable = false

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
            if let skill {
                FactList(facts: [("Version", skill.version), ("Given to", skill.agents.isEmpty ? "No agent yet" : skill.agents.joined(separator: ", "))])
            }
            if let path { PathRow(path: path) }
            PlaceSection(title: SkillSearch.skillFile) {
                if let document {
                    if !document.fields.isEmpty { FactList(facts: document.fields.map { ($0.key, $0.value) }) }
                    SkillMarkdown(blocks: document.blocks)
                } else if let skill {
                    SkillMarkdown(blocks: SkillMarkdownReader.parse(skill.instructions))
                } else if unreadable {
                    MemoryQuiet("Its SKILL.md could not be read here.")
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            Button("Open in Skills", systemImage: "sparkle", action: openSkills).buttonStyle(KitButton(kind: .secondary))
        }
        .task(id: path) { read() }
    }

    /// The agent's own file, read as it is on disk; nothing here writes to it.
    private func read() {
        guard skill == nil, let path else { return }
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            unreadable = true
            return
        }
        document = SkillMarkdownReader.document(text)
    }
}

/// Where a file is on this Mac, said whole, with the file opened on the device or its path copied.
private struct PathRow: View {
    let path: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
            Text(SkillSearch.shortPath(path, home: NSHomeDirectory()))
                .font(Memnox.Console.code(Memnox.Console.TextSize.label))
                .foregroundStyle(Memnox.Console.muted)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            HStack(spacing: Memnox.Spacing.medium) {
                if FileManager.default.fileExists(atPath: path) {
                    Button("Open on device", systemImage: "arrow.up.forward.app") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                        .buttonStyle(KitButton(kind: .secondary))
                }
                Button(copied ? "Path copied" : "Copy path", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(path, forType: .string)
                    copied = true
                }
                .buttonStyle(KitButton(kind: .secondary))
            }
        }
    }
}

/// Watches the agents list, which is drawn again whenever the runtime's answer changes.
private struct AgentsWatch<Content: View>: View {
    @ObservedObject var screen: AgentsScreen
    @ViewBuilder let content: ([AgentStanding]) -> Content

    var body: some View {
        content(screen.agents.agents ?? [])
    }
}

/// One node of the workspace's live graph in the details: the words that arrived, as the cloud clipped them, who said
/// it, through which tool and when, the newest of what an author's count holds, and the source one press away.
private struct LiveDetail: View {
    let node: WorkspaceGraphNode

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
            if let words = node.excerpt {
                Text(words)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
                    .foregroundStyle(Memnox.Console.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            FactList(facts: WorkspaceLiveLines.rows(node))
            if !node.said.isEmpty {
                PlaceSection(title: "Lately") {
                    ShellPanel {
                        ForEach(Array(node.said.enumerated()), id: \.offset) { index, said in
                            if index > 0 { ShellDivider() }
                            ShellRow(title: said.excerpt ?? said.label, caption: said.at.map { String($0.prefix(Self.dayLength)) },
                                     action: { open(said.href) }) {
                                EmptyView()
                            } trailing: {
                                EmptyView()
                            }
                        }
                    }
                }
            }
            if let link = WorkspaceLiveLines.link(node) {
                Button("Open the source", systemImage: "link") { NSWorkspace.shared.open(link) }
                    .buttonStyle(KitButton(kind: .secondary))
            }
        }
    }

    /// A date written as the runtime writes it, read by its day.
    private static let dayLength = 10
    private static let secure = "https://"

    private func open(_ href: String?) {
        guard let href, href.hasPrefix(Self.secure), let link = URL(string: href) else { return }
        NSWorkspace.shared.open(link)
    }
}

/// A node picked on the brain, with the map it was picked on so its dialog can list what it is linked to.
private struct MapPick: Identifiable {
    let node: MemoryMapNode
    let map: MemoryMap

    var id: String { node.id }
}

private enum MapPickLayout {
    static let avatar: CGFloat = 44
    static let initials: CGFloat = 16
}

/// What a click on the brain opens, in the card beside the node: what it is and its name with a close button, then
/// the fact whole with its evidence, or the piece with its details, or a person's profile, and everything it is
/// linked to, each a press that moves the card to it.
private struct MapPickCard: View {
    @ObservedObject var screen: MemoryScreen
    let pick: MapPick
    let items: [MemoryItemView]
    let skills: SkillsHubView?
    let rules: [PolicyRuleView]
    /// Goes somewhere else in the window, putting the card away first.
    let go: (WindowRoute) -> Void
    let open: (MemoryMapNode) -> Void
    let close: () -> Void

    private static let sourcesTab = "sources"
    private static let skillsTab = "skills"

    var body: some View {
        let node = pick.node
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Memnox.Spacing.medium) {
                VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                    Text(MapWords.kindWord(node.kind).uppercased())
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.label, .medium))
                        .tracking(PlaceHeading.tracking)
                        .foregroundStyle(Memnox.Console.muted)
                    Text(MapNames.short(node.label))
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.base, .semibold))
                        .foregroundStyle(Memnox.Console.foreground)
                        .lineLimit(2)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: Memnox.Spacing.medium)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: Memnox.TextSize.footnote, weight: .semibold))
                        .foregroundStyle(Memnox.Console.muted)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHand()
                .accessibilityLabel("Close the details")
            }
            .padding(Memnox.Spacing.xLarge)
            ShellDivider()
            // Its own height while it fits the card, and scrolling once it would run past the card's most.
            ViewThatFits(in: .vertical) {
                details(node)
                ScrollView { details(node) }
            }
        }
        .id(node.id)
    }

    private func details(_ node: MemoryMapNode) -> some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.xLarge) {
            if node.kind == .person {
                PersonProfile(person: node, map: pick.map, open: open)
            } else if let id = node.item, let item = items.first(where: { $0.id == id }) {
                FactInspector(screen: screen, item: item, forgotten: close)
                PlaceLinks(node: node, map: pick.map, open: open)
            } else {
                PlaceDetail(memory: screen.memory, place: node, map: pick.map, items: items, skills: skills, rules: rules,
                            manage: { go(WindowRoute(.workspaces, tab: Self.sourcesTab)) },
                            openSkills: { go(WindowRoute(.workspaces, tab: Self.skillsTab)) }, open: open)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Memnox.Spacing.xLarge)
    }
}

/// A person's profile: their avatar and name, their address where their name is one, what they said, what names
/// them as owner or approver and what they confirmed, and the tools those came from, each a press that opens it.
private struct PersonProfile: View {
    let person: MemoryMapNode
    let map: MemoryMap
    let open: (MemoryMapNode) -> Void

    var body: some View {
        let profile = BrainFaces.profile(person.id, in: map, label: person.label)
        let ink = ArmsInk.avatars[BrainFaces.colour(person.label, count: BrainFaces.avatarColours) % ArmsInk.avatars.count]
        HStack(spacing: Memnox.Spacing.large) {
            Text(BrainFaces.initials(person.label))
                .font(Memnox.Console.sans(MapPickLayout.initials, .semibold))
                .foregroundStyle(Color.white)
                .frame(width: MapPickLayout.avatar, height: MapPickLayout.avatar)
                .background(ink, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                Text(person.label)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.base, .medium))
                    .foregroundStyle(Memnox.Console.foreground)
                    .textSelection(.enabled)
                if let email = profile.email { MemoryQuiet(email) }
                if let detail = person.detail { MemoryQuiet(detail) }
            }
        }
        group("Said", profile.said)
        group("Owns or approves", profile.named)
        group("Confirmed", profile.confirmed)
        group("Sources", profile.sources)
        if profile.said.isEmpty && profile.named.isEmpty && profile.confirmed.isEmpty {
            MemoryQuiet("Nothing in your memory says what they decided yet.")
        }
    }

    @ViewBuilder private func group(_ title: String, _ ids: [String]) -> some View {
        let nodes = ids.compactMap { id in map.nodes.first { $0.id == id } }
        if !nodes.isEmpty {
            PlaceSection(title: title) {
                ShellPanel {
                    ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                        if index > 0 { ShellDivider() }
                        ShellRow(title: node.label, caption: MapWords.kindWord(node.kind), action: { open(node) }) {
                            Image(systemName: MapMark.symbol(node.kind))
                                .font(.system(size: Memnox.TextSize.footnote))
                                .foregroundStyle(Memnox.Console.muted)
                                .accessibilityHidden(true)
                        } trailing: {
                            EmptyView()
                        }
                    }
                }
            }
        }
    }
}
