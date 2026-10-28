import MemnoxVoiceCore
import SwiftUI

/// The memory layers for the Memory page's Layers view, redrawn whenever the runtime answers.
@MainActor
final class MemoryLayersScreen: ObservableObject {
    let layers: MemoryLayers
    /// Bumped when the layers change, so every view reading them is drawn again.
    @Published private(set) var tick = 0
    /// What the last press came to, shown above the view until the next one.
    @Published var note: String?

    init(layers: MemoryLayers) {
        self.layers = layers
        layers.changed = { [weak self] in
            Task { @MainActor [weak self] in self?.tick += 1 }
        }
    }
}

private enum LayersLayout {
    static let badge: CGFloat = 26
    static let cardPadding: CGFloat = 16
    static let keepHeight: CGFloat = 96
    /// A settled layer's badge wash, light so the number stays the thing read.
    static let wash = 0.14
}

/// Memory as three layers any agent reads, numbered as the long term stack: 1 MEMORY.md for every chat, 2 the router,
/// 3 SKILL.md for live data. Below them the short term card with the cold cache numbers, then the keep on compact list.
/// Preview asks the runtime for the map, and only a confirm in the sheet has it write, inside Memnox's fences.
struct MemoryLayersPage<Switcher: View>: View {
    @ObservedObject var screen: MemoryLayersScreen
    let width: WidthClass
    /// The page's Graph, List and Layers switch, drawn first so the person can go back.
    @ViewBuilder let switcher: Switcher
    @State private var chosen: String?
    @State private var keep = ""
    @State private var reviewing = false

    var body: some View {
        let layers = screen.layers
        ShellScroll(width: width) {
            switcher
            NoteBanner(text: screen.note)
            if let view = layers.layers {
                valueStrip(view.value)
                if let project = current(view) {
                    picker(view)
                    longTerm(project)
                    shortTerm(project)
                } else {
                    EmptyState(symbol: "square.stack.3d.up", title: "No project yet",
                               detail: "Open a repository in an agent and its memory layers show here.")
                }
            } else if layers.unreadable {
                ReadFailed(what: "the memory layers") { Task { await layers.refresh() } }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task { await layers.refresh() }
        .consoleSheet(isPresented: Binding(get: { reviewing && layers.plan != nil },
                                           set: { if !$0 { close() } })) {
            if let plan = layers.plan {
                LayersPlanSheet(plan: plan, busy: layers.busy != nil, cancel: close, confirm: confirm)
            }
        }
    }

    private func current(_ view: MemoryLayersView) -> ProjectLayersView? {
        view.projects.first { $0.path == chosen } ?? view.projects.first
    }

    @ViewBuilder private func picker(_ view: MemoryLayersView) -> some View {
        if view.projects.count > 1 {
            Picker("Project", selection: Binding(get: { current(view)?.path ?? "" }, set: { chosen = $0 })) {
                ForEach(view.projects) { Text($0.name).tag($0.path) }
            }
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    /// Faster to find and cheaper to find, drawn only where the runtime measured the number.
    @ViewBuilder private func valueStrip(_ value: MemoryValueView) -> some View {
        let lines = MemoryLayersLines.value(value)
        if !lines.isEmpty {
            HStack(spacing: Memnox.Spacing.xLarge) {
                ForEach(lines) { line in
                    VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                        Text(line.title)
                            .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                            .foregroundStyle(Memnox.Console.muted)
                        Text(line.figure)
                            .font(Memnox.Console.sans(Memnox.Console.TextSize.large, .semibold).monospacedDigit())
                            .foregroundStyle(Memnox.Console.foreground)
                        Text(line.detail)
                            .font(Memnox.Console.sans(Memnox.Console.TextSize.label))
                            .foregroundStyle(Memnox.Console.faint)
                    }
                }
            }
        }
    }

    private func longTerm(_ project: ProjectLayersView) -> some View {
        ShellSection(title: "Long-term memory") {
            Button("Preview the map") { preview(project) }
                .buttonStyle(KitButton(kind: .primary))
                .disabled(screen.layers.busy != nil)
        } content: {
            VStack(spacing: Memnox.Spacing.medium) {
                ForEach(MemoryLayersLines.cards(project)) { LayerCardView(card: $0) }
            }
        }
    }

    private func shortTerm(_ project: ProjectLayersView) -> some View {
        ShellSection(title: "Short-term memory") {
            VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
                if let cost = screen.layers.sessionCost {
                    VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
                        ForEach(MemoryLayersLines.sessionCost(cost), id: \.self) { line in
                            Text(line).font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
                        }
                        Text("Counted from your chats only. Nothing is pinged to keep them warm.")
                            .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                            .foregroundStyle(Memnox.Console.faint)
                    }
                    .foregroundStyle(Memnox.Console.foreground)
                }
                Text("Keep when a chat compacts, one line each")
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.meta, .medium))
                    .foregroundStyle(Memnox.Console.muted)
                TextEditor(text: $keep)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
                    .frame(height: LayersLayout.keepHeight)
                    .scrollContentBackground(.hidden)
                    .background(Memnox.Console.field, in: RoundedRectangle(cornerRadius: Memnox.Console.controlRadius))
                    .overlay(RoundedRectangle(cornerRadius: Memnox.Console.controlRadius)
                        .strokeBorder(Memnox.Console.fieldEdge, lineWidth: Memnox.Stroke.hairline))
                    .onAppear { if keep.isEmpty { keep = project.keep.joined(separator: "\n") } }
                Button("Preview with this list") { preview(project) }
                    .buttonStyle(KitButton(kind: .secondary))
                    .disabled(screen.layers.busy != nil)
            }
            .padding(LayersLayout.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Memnox.Console.card, in: RoundedRectangle(cornerRadius: Memnox.Console.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Memnox.Console.cardRadius, style: .continuous)
                .strokeBorder(Memnox.Console.border, lineWidth: Memnox.Stroke.hairline))
        }
    }

    private func preview(_ project: ProjectLayersView) {
        let list = MemoryLayersLines.keepList(keep)
        Task {
            if case .failed(let why) = await screen.layers.preview(project: project.path, keep: list) {
                screen.note = why
            } else {
                screen.note = nil
                reviewing = true
            }
        }
    }

    private func confirm() {
        Task {
            switch await screen.layers.confirm() {
            case .written(let files):
                screen.note = files.isEmpty ? "Nothing needed writing." : "Wrote \(files.joined(separator: ", "))."
                reviewing = false
            case .failed(let why):
                screen.note = why
                reviewing = false
            }
        }
    }

    private func close() {
        reviewing = false
        screen.layers.dismissPlan()
    }
}

/// One numbered layer as a card: its number in a badge, the file, what it is for, and how it stands.
private struct LayerCardView: View {
    let card: LayerCard

    var body: some View {
        HStack(alignment: .center, spacing: Memnox.Spacing.large) {
            Text("\(card.number)")
                .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .semibold).monospacedDigit())
                .foregroundStyle(card.settled ? Memnox.Console.success : Memnox.Console.muted)
                .frame(width: LayersLayout.badge, height: LayersLayout.badge)
                .background((card.settled ? Memnox.Console.success : Memnox.Console.faint).opacity(LayersLayout.wash), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                HStack(spacing: Memnox.Spacing.small) {
                    Text(card.file)
                        .font(Memnox.Console.code(Memnox.Console.TextSize.bodySmall, .medium))
                        .foregroundStyle(Memnox.Console.foreground)
                    Text(card.role)
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                        .foregroundStyle(Memnox.Console.muted)
                }
                Text(card.state)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                    .foregroundStyle(Memnox.Console.faint)
            }
            Spacer(minLength: 0)
        }
        .padding(LayersLayout.cardPadding)
        .background(Memnox.Console.card, in: RoundedRectangle(cornerRadius: Memnox.Console.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Memnox.Console.cardRadius, style: .continuous)
            .strokeBorder(Memnox.Console.border, lineWidth: Memnox.Stroke.hairline))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Layer \(card.number), \(card.file), \(card.role). \(card.state)")
    }
}

/// The map the runtime would write, file by file as a diff, then the console's confirm before it writes anything.
private struct LayersPlanSheet: View {
    let plan: MemoryLayersPlan
    let busy: Bool
    let cancel: () -> Void
    let confirm: () -> Void
    @State private var confirming = false

    var body: some View {
        if confirming {
            ConsoleConfirm(symbol: "square.stack.3d.up", title: "Write the memory map?",
                           message: MemoryLayersLines.planSummary(plan),
                           detail: "Your own words in these files stay as they are.",
                           confirm: "Write", destructive: false,
                           cancel: { confirming = false }, act: confirm)
        } else {
            SkillSheetFrame(title: "The new memory map", step: MemoryLayersLines.planSummary(plan)) {
                ForEach(plan.files) { file in
                    VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
                        Text(file.path)
                            .font(Memnox.Console.code(Memnox.Console.TextSize.meta, .medium))
                            .foregroundStyle(file.changed ? Memnox.Console.foreground : Memnox.Console.faint)
                        if file.changed { PlanDiffView(lines: MemoryLayersLines.diff(before: file.before, after: file.after)) }
                    }
                }
            } footer: {
                Spacer()
                Button("Cancel", action: cancel).buttonStyle(KitButton(kind: .secondary))
                Button("Confirm") { confirming = true }
                    .buttonStyle(KitButton(kind: .primary))
                    .disabled(busy || !plan.files.contains(where: \.changed))
            }
        }
    }
}

/// A diff as the console draws one: a mark and a tint for each added or removed line, the rest plain.
struct PlanDiffView: View {
    let lines: [PlanDiffLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(lines) { line in
                HStack(alignment: .firstTextBaseline, spacing: Memnox.Spacing.small) {
                    Text(mark(line.mark)).foregroundStyle(tint(line.mark))
                    Text(line.text.isEmpty ? " " : line.text)
                        .foregroundStyle(line.mark == .same ? Memnox.Console.muted : Memnox.Console.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(Memnox.Console.code(Memnox.Console.TextSize.meta))
                .padding(.horizontal, Memnox.Spacing.medium)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(tint(line.mark).opacity(line.mark == .same ? 0 : LayersLayout.wash))
            }
        }
        .padding(.vertical, Memnox.Spacing.small)
        .background(Memnox.Console.field, in: RoundedRectangle(cornerRadius: Memnox.Console.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: Memnox.Console.controlRadius)
            .strokeBorder(Memnox.Console.border, lineWidth: Memnox.Stroke.hairline))
    }

    private func mark(_ mark: PlanDiffMark) -> String {
        switch mark {
        case .added: "+"
        case .removed: "\u{2212}"
        case .same: " "
        }
    }

    private func tint(_ mark: PlanDiffMark) -> Color {
        switch mark {
        case .added: Memnox.Console.success
        case .removed: Memnox.Console.destructive
        case .same: Memnox.Console.muted
        }
    }
}
