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
    static let cardWidth: CGFloat = 280
    static let searchWidth: CGFloat = 300
    /// How long typing rests before the search is asked, so each key is not a request.
    static let searchRest: Duration = .milliseconds(300)
}

/// What this Mac learned, read three ways from one record: the list by status and scope, one fact with the evidence it
/// was read from, and the sources it came out of. A statement is shown whole, as written.
struct MemoryDestination: View {
    @ObservedObject var screen: MemoryScreen
    @ObservedObject var shell: AppShellModel
    @ObservedObject var island: IslandModel
    let width: WidthClass
    @State private var status = MemoryStatus.verified
    @State private var scope: MemoryScope?
    @State private var query = ""

    private var filter: MemoryFilter {
        MemoryFilter(status: status, scope: scope, query: query.trimmingCharacters(in: .whitespaces).isEmpty ? nil : query)
    }

    var body: some View {
        let memory = screen.memory
        let listed = memory.facts
        let picked = listed?.items.first { $0.id == shell.inspecting }
        InspectorLayout(width: width, title: picked.map { MemoryLines.kindWord($0.kind) }, close: { shell.inspecting = nil }) {
            ShellScroll(width: width) {
                NoteBanner(text: screen.note)
                ShellSection(title: "What your agents know") {
                    VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
                        filters
                        facts(listed)
                    }
                }
                MemorySources(screen: screen, hub: shell.hub)
            }
        } detail: {
            if let picked {
                FactInspector(screen: screen, item: picked) { shell.inspecting = nil }.id(picked.id)
            }
        }
        .task { await memory.refreshSources() }
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

    private var filters: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            HStack(spacing: Memnox.Spacing.medium) {
                SearchField(prompt: "Search memory", text: $query).frame(maxWidth: MemoryLayout.searchWidth)
                Spacer(minLength: Memnox.Spacing.medium)
                HStack(spacing: Memnox.Spacing.small) {
                    MemoryChip(title: "Both", on: scope == nil) { scope = nil }
                    ForEach(MemoryLines.scopes, id: \.scope) { each in
                        MemoryChip(title: each.label, on: scope == each.scope) { scope = each.scope }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Scope")
            }
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                HStack(spacing: Memnox.Spacing.small) {
                    ForEach(MemoryLines.filters, id: \.status) { each in
                        MemoryChip(title: each.label, on: status == each.status) { status = each.status }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Status")
            } else {
                if let search = screen.memory.search {
                    MemoryQuiet("\(MemoryLines.searchModeLine(search.mode)), over every status.")
                    if let note = search.note { MemoryQuiet(note) }
                } else {
                    MemoryQuiet("Searching every status for these words.")
                }
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
                           detail: "Add a source below and Memnox reads it with your own agent. What it finds waits in Learn until you confirm it.")
            } else {
                ShellPanel {
                    ForEach(Array(listed.items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { ShellDivider() }
                        let word = MemoryLines.statusWord(item.status)
                        ShellRow(title: item.statement, caption: MemoryLines.rowCaption(item), chosen: item.id == shell.inspecting,
                                 action: { shell.inspecting = item.id }) {
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

/// One filter or scope as a capsule, drawn strongest while it is chosen.
struct MemoryChip: View {
    let title: String
    let on: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            Text(title)
                .font(Memnox.sans(Memnox.TextSize.footnote, on ? .medium : .regular))
                .foregroundStyle(on ? Memnox.Palette.foreground : Memnox.Palette.muted)
                .padding(.horizontal, Memnox.Spacing.regular)
                .padding(.vertical, Memnox.Spacing.xSmall)
                .background(on ? Memnox.Palette.hover : Color.clear, in: Capsule())
                .overlay(Capsule().strokeBorder(on ? Memnox.Palette.primary : Memnox.Palette.panelEdge, lineWidth: Memnox.Stroke.hairline))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHand()
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}

/// A quiet line of memory's details.
struct MemoryQuiet: View {
    let text: String
    var tint = Memnox.Palette.muted

    init(_ text: String, tint: Color = Memnox.Palette.muted) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text)
            .font(Memnox.sans(Memnox.TextSize.footnote))
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
                .font(Memnox.sans(Memnox.TextSize.body))
                .foregroundStyle(Memnox.Palette.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            HStack(spacing: Memnox.Spacing.large) {
                StatusWord(Tone(word.tone), word.word)
                if item.tainted { StatusWord(.attention, MemoryLines.taintedLine) }
            }
            if let rule = item.rule { MemoryQuiet("What it governs: \(rule.sentence)", tint: Memnox.Palette.foreground) }
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
                    .font(Memnox.sans(Memnox.TextSize.footnote, .medium))
                    .foregroundStyle(Memnox.Palette.muted)
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
                    .foregroundStyle(Memnox.Palette.muted)
                    .accessibilityHidden(true)
                Text(MemoryLines.evidenceLine(each))
                    .font(Memnox.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(each.stale ? Memnox.Palette.muted : Memnox.Palette.primary)
                    .strikethrough(each.stale, color: Memnox.Palette.faint)
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

/// The places memory is read from, one card each, and the sheet that adds another.
private struct MemorySources: View {
    @ObservedObject var screen: MemoryScreen
    let hub: McpHubScreen?
    @State private var adding = false

    var body: some View {
        let memory = screen.memory
        let list = memory.sources
        ShellSection(title: "Memory sources") {
            if let list, !list.isEmpty { addButton }
        } content: {
            VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
                if memory.unreadable.sources {
                    ReadFailed(what: "the memory sources") { Task { await memory.refreshSources() } }
                }
                if let list {
                    if list.isEmpty {
                        EmptyState(symbol: "books.vertical", title: "No memory sources yet",
                                   detail: "Point Memnox at an Obsidian vault, a folder of notes, your agents' instruction files, a Notion export, Supermemory or an MCP memory server. Your own agent reads it, and you confirm what it finds.")
                        addButton
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: MemoryLayout.cardWidth), spacing: Memnox.Spacing.large)],
                                  alignment: .leading, spacing: Memnox.Spacing.large) {
                            ForEach(list) { source in
                                SourceCard(screen: screen, source: source)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $adding) {
            AddMemorySourceSheet(screen: screen, hub: hub) { adding = false }
        }
    }

    private var addButton: some View {
        Button("Add source", systemImage: "plus") { adding = true }.buttonStyle(KitButton(kind: .primary))
    }
}

private struct SourceCard: View {
    @ObservedObject var screen: MemoryScreen
    let source: MemorySourceView
    @State private var sure = false

    var body: some View {
        let memory = screen.memory
        let shape = RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
        let trust = MemoryLines.trustWord(source.trust)
        let busy = memory.busy == source.id
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            HStack(spacing: Memnox.Spacing.medium) {
                Image(systemName: "book").foregroundStyle(Memnox.Palette.muted).accessibilityHidden(true)
                Text(source.name)
                    .font(Memnox.sans(Memnox.TextSize.body, .semibold))
                    .foregroundStyle(Memnox.Palette.foreground)
                    .lineLimit(1)
                Spacer(minLength: Memnox.Spacing.small)
                MemoryQuiet(MemoryLines.sourceKindLabel(source.kind))
            }
            Text(source.location)
                .font(Memnox.mono(Memnox.TextSize.micro))
                .foregroundStyle(Memnox.Palette.muted)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(source.location)
            StatusWord(Tone(trust.tone), trust.word)
            MemoryQuiet(MemoryLines.sourceCountsLine(source.counts), tint: Memnox.Palette.foreground)
            MemoryQuiet(MemoryLines.lastReadLine(source, now: Date()))
            if let key = MemoryLines.keyLine(source.keyHeld) {
                MemoryQuiet(key, tint: source.keyHeld == true ? Memnox.Palette.muted : Memnox.Palette.warm)
            }
            if let error = source.lastError {
                MemoryQuiet("The last read failed: \(error)", tint: Memnox.Palette.destructive)
            }
            if let read = memory.lastRead(source.id) {
                MemoryQuiet(MemoryLines.readSummaryLine(read), tint: Memnox.Palette.foreground)
            }
            Spacer(minLength: 0)
            HStack(spacing: Memnox.Spacing.medium) {
                Button(busy ? "Reading" : "Read now", systemImage: "arrow.clockwise", action: readNow)
                    .buttonStyle(KitButton(kind: .secondary))
                    .disabled(busy)
                Spacer(minLength: Memnox.Spacing.small)
                if sure {
                    Button("Keep") { sure = false }.buttonStyle(KitButton(kind: .secondary))
                    Button("Remove", systemImage: "trash", action: remove)
                        .buttonStyle(KitButton(kind: .primary))
                        .disabled(busy)
                } else {
                    Button("Remove", systemImage: "trash") { sure = true }.buttonStyle(KitButton(kind: .secondary))
                }
            }
        }
        .padding(Memnox.Spacing.xLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Memnox.Palette.card, in: shape)
        .overlay(shape.strokeBorder(Memnox.Palette.panelEdge, lineWidth: Memnox.Stroke.hairline))
    }

    private func readNow() {
        let id = source.id
        // The summary stays under the card, so only a failure is said above the page.
        Task {
            if case .failed(let why) = await screen.memory.readNow(id) { screen.note = why }
        }
    }

    private func remove() {
        let id = source.id
        screen.press { await $0.removeSource(id) }
    }
}
