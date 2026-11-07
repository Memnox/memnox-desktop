import MemnoxVoiceCore
import SwiftUI

/// The places memory is read from, one card each, and the sheet that adds another, as its own page under Inputs so a
/// source is added and looked after where the rest of what flows in is.
struct MemorySourcesPage: View {
    @ObservedObject var screen: MemoryScreen
    @ObservedObject var shell: AppShellModel
    @State private var adding = false

    /// A source card is never narrower than this, so its buttons keep their whole labels.
    private static let cardWidth: CGFloat = 280

    init(screen: MemoryScreen, shell: AppShellModel) {
        self.screen = screen
        self.shell = shell
    }

    var body: some View {
        let memory = screen.memory
        let list = memory.sources
        ShellSection(title: "Memory sources") {
            if let list, !list.isEmpty { addButton }
        } content: {
            VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
                // What a Read now or a Remove came to, so a failure on a card is said rather than lost.
                NoteBanner(text: screen.note)
                if memory.unreadable.sources {
                    ReadFailed(what: "the memory sources") { Task { await memory.refreshSources() } }
                }
                if list == nil, !memory.unreadable.sources {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                }
                if let list {
                    if list.isEmpty {
                        EmptyState(symbol: "books.vertical", title: "No memory sources yet",
                                   detail: "Point Memnox at an Obsidian vault, a folder of notes, your agents' instruction files, a Notion export, Supermemory or an MCP memory server. Your own agent reads it, and you confirm what it finds.")
                        addButton
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.cardWidth), spacing: Memnox.Spacing.large)],
                                  alignment: .leading, spacing: Memnox.Spacing.large) {
                            ForEach(list) { source in
                                SourceCard(screen: screen, source: source)
                            }
                        }
                    }
                }
            }
        }
        .task { await memory.refreshSources() }
        .consoleSheet(isPresented: $adding) {
            AddMemorySourceSheet(screen: screen, hub: shell.hub) { adding = false }.consoleLook()
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
                Image(systemName: "book").foregroundStyle(Memnox.Console.muted).accessibilityHidden(true)
                Text(source.name)
                    .font(Memnox.Console.sans(Memnox.TextSize.body, .semibold))
                    .foregroundStyle(Memnox.Console.foreground)
                    .lineLimit(1)
                Spacer(minLength: Memnox.Spacing.small)
                MemoryQuiet(MemoryLines.sourceKindLabel(source.kind))
            }
            Text(source.location)
                .font(Memnox.Console.sans(Memnox.TextSize.micro))
                .foregroundStyle(Memnox.Console.muted)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(source.location)
            StatusWord(Tone(trust.tone), trust.word)
            MemoryQuiet(MemoryLines.sourceCountsLine(source.counts), tint: Memnox.Console.foreground)
            MemoryQuiet(MemoryLines.lastReadLine(source, now: Date()))
            if let key = MemoryLines.keyLine(source.keyHeld) {
                MemoryQuiet(key, tint: source.keyHeld == true ? Memnox.Console.muted : Memnox.Console.warm)
            }
            if let error = source.lastError {
                MemoryQuiet("The last read failed: \(error)", tint: Memnox.Console.destructive)
            }
            if let read = memory.lastRead(source.id) {
                MemoryQuiet(MemoryLines.readSummaryLine(read), tint: Memnox.Console.foreground)
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
        .background(Memnox.Console.card, in: shape)
        .overlay(shape.strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
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
