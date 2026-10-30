import MemnoxVoiceCore
import SwiftUI

/// What your agent read out of your sources, and what other agents suggested, waiting on you oldest first. Nothing
/// here counts until it is confirmed, and a rule confirmed here still waits for its signature with Touch ID.
struct LearnDestination: View {
    @ObservedObject var screen: MemoryScreen
    @ObservedObject var island: IslandModel
    let width: WidthClass
    /// The line each card's last press ended in, by the item's id.
    @State private var notes: [String: String] = [:]

    var body: some View {
        ShellScroll(width: width) { content }
            .task {
                await screen.memory.refreshLearn()
                // Evidence names its source, and the sources say where a file sits.
                if screen.memory.sources == nil { await screen.memory.refreshSources() }
            }
            // A signature on the island settles a rule, so the queue is read again.
            .onChange(of: island.waiting.count) { Task { await screen.memory.refreshLearn() } }
    }

    @ViewBuilder private var content: some View {
        let memory = screen.memory
        if let queue = memory.learn {
            let items = MemoryLines.oldestFirst(queue.items)
            // A card answered here leaves the queue, and its line stays so the person sees what the press did.
            let answered = notes.keys.filter { id in !items.contains { $0.id == id } }.sorted()
            VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
                ForEach(answered, id: \.self) { id in NoteBanner(text: notes[id]) }
                if items.isEmpty {
                    EmptyState(symbol: "graduationcap", title: "Nothing to confirm",
                               detail: "When your agent reads a memory source, or another agent suggests something through memnox_suggest, it waits here until you confirm, edit or reject it.")
                } else {
                    MemoryQuiet("\(items.count) waiting, oldest first. Nothing here reaches an agent as settled until you confirm it.")
                    ForEach(items) { item in
                        Suggestion(screen: screen, item: item, note: notes[item.id]) { notes[item.id] = $0 }
                    }
                    if let more = MemoryLines.moreLine(queue.more) { MemoryQuiet(more) }
                }
            }
        } else if memory.unreadable.learn {
            ReadFailed(what: "the Learn queue") { Task { await memory.refreshLearn() } }
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity)
        }
    }
}

/// One suggestion as a card: its words, what it would govern, where it was read, and Confirm, Edit or Reject.
private struct Suggestion: View {
    @ObservedObject var screen: MemoryScreen
    let item: MemoryItemView
    let note: String?
    let said: (String) -> Void
    @State private var editing = false
    @State private var draft = ""

    private static let editorHeight: CGFloat = 90

    var body: some View {
        let memory = screen.memory
        let busy = memory.busy == item.id
        let shape = RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
        VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
            header
            if editing {
                TextEditor(text: $draft)
                    .font(Memnox.sans(Memnox.TextSize.body))
                    .scrollContentBackground(.hidden)
                    .padding(Memnox.Spacing.small)
                    .frame(minHeight: Self.editorHeight)
                    .background(Memnox.Palette.field, in: RoundedRectangle(cornerRadius: Memnox.Spacing.medium, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Memnox.Spacing.medium, style: .continuous)
                        .strokeBorder(Memnox.Palette.fieldEdge, lineWidth: Memnox.Stroke.hairline))
                    .accessibilityLabel("The statement")
            } else {
                Text(item.statement)
                    .font(Memnox.sans(Memnox.TextSize.body))
                    .foregroundStyle(Memnox.Palette.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if let rule = item.rule {
                Text("What it would govern: \(rule.sentence)")
                    .font(Memnox.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Palette.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Memnox.Spacing.regular)
                    .padding(.vertical, Memnox.Spacing.medium)
                    .background(Memnox.Palette.hover, in: RoundedRectangle(cornerRadius: Memnox.Spacing.medium, style: .continuous))
            }
            if let duplicate = item.duplicateOf { MemoryQuiet(MemoryLines.duplicateLine(duplicate.statement)) }
            if let confidence = MemoryLines.confidenceLine(item.extractorConfidence) { MemoryQuiet(confidence) }
            MemoryEvidence(memory: memory, evidence: item.evidence)
            buttons(busy: busy)
            if item.memoryKind == .rule, item.proposalId == nil, !editing, note == nil {
                MemoryQuiet("Confirming a rule proposes it. It holds once you sign it on the island with \(MemoryScreen.keyTitle).")
            }
            if let note { MemoryQuiet(note) }
        }
        .padding(Memnox.Spacing.xLarge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Memnox.Palette.card, in: shape)
        .overlay(shape.strokeBorder(Memnox.Palette.panelEdge, lineWidth: Memnox.Stroke.hairline))
    }

    private var header: some View {
        HStack(spacing: Memnox.Spacing.medium) {
            Text(MemoryLines.kindWord(item.kind))
                .font(Memnox.sans(Memnox.TextSize.micro, .medium))
                .foregroundStyle(Memnox.Palette.muted)
                .padding(.horizontal, Memnox.Spacing.medium)
                .padding(.vertical, Memnox.Spacing.xxSmall)
                .overlay(Capsule().strokeBorder(Memnox.Palette.panelEdge, lineWidth: Memnox.Stroke.hairline))
            Text(MemoryLines.originLine(item))
                .font(Memnox.sans(Memnox.TextSize.footnote))
                .foregroundStyle(Memnox.Palette.muted)
                .lineLimit(1)
            Spacer(minLength: Memnox.Spacing.medium)
            if item.tainted { StatusWord(.attention, MemoryLines.taintedLine) }
            if item.proposalId != nil { StatusWord(.attention, "Waiting for your signature on the island") }
            if item.memoryStatus == .conflicting {
                let word = MemoryLines.statusWord(item.status)
                StatusWord(Tone(word.tone), word.word)
            }
        }
    }

    @ViewBuilder private func buttons(busy: Bool) -> some View {
        HStack(spacing: Memnox.Spacing.medium) {
            if editing {
                Button("Save", action: save)
                    .buttonStyle(KitButton(kind: .primary))
                    .disabled(busy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel") {
                    draft = item.statement
                    editing = false
                }
                .buttonStyle(KitButton(kind: .secondary))
            } else {
                Button("Confirm", systemImage: "checkmark", action: confirm)
                    .buttonStyle(KitButton(kind: .primary))
                    .disabled(busy || item.proposalId != nil)
                Button("Edit", systemImage: "pencil") {
                    draft = item.statement
                    editing = true
                }
                .buttonStyle(KitButton(kind: .secondary))
                .disabled(busy)
                // Set apart from Confirm, so a rejection is never pressed by a slip.
                Spacer(minLength: Memnox.Spacing.medium)
                Button("Reject", systemImage: "xmark", action: reject)
                    .buttonStyle(KitButton(kind: .secondary))
                    .disabled(busy)
            }
        }
    }

    private func confirm() {
        let id = item.id
        Task { said(await screen.memory.confirm(id, keyTitle: MemoryScreen.keyTitle).note) }
    }

    private func reject() {
        let id = item.id
        Task { said(await screen.memory.reject(id).note) }
    }

    /// The words go as typed, so what the person wrote is what is kept.
    private func save() {
        let id = item.id, statement = draft
        Task {
            let outcome = await screen.memory.edit(id, statement: statement)
            said(outcome.note)
            if case .failed = outcome { return }
            editing = false
        }
    }
}
