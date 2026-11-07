import MemnoxVoiceCore
import SwiftUI

/// Personal sync for the window, redrawn whenever the runtime's answer changes it.
@MainActor
final class SyncScreen: ObservableObject {
    let sync: PersonalSync
    /// Bumped when the status or the conflicts change, so every view reading them is drawn again.
    @Published private(set) var tick = 0
    /// What the last press came to: a refusal, or what waits on Touch ID, until the next one.
    @Published var note: (text: String, alert: Bool)?

    init(sync: PersonalSync) {
        self.sync = sync
        sync.changed = { [weak self] in
            Task { @MainActor [weak self] in self?.tick += 1 }
        }
    }

    /// Runs one press and says how it ended, the part waiting on the island named with Touch ID.
    func press(waits: String? = nil, _ work: @escaping (PersonalSync) async -> SyncOutcome) {
        Task {
            switch await work(sync) {
            case .failed(let why): note = (why, true)
            case .proposed: note = waits.map { ($0, false) }
            case .done: note = nil
            }
        }
    }
}

private enum SyncLayout {
    static let digitSize: CGFloat = 24
    static let digitTracking: CGFloat = 2
    static let sideHeight: CGFloat = 180
}

/// Personal sync as the runtime runs it: where it stands in its own sentence, Sync now, the key offered or accepted
/// only behind a fingerprint the person compared and signs with Touch ID, and conflicts to choose between.
struct SyncPage: View {
    @ObservedObject var screen: SyncScreen

    var body: some View {
        content.task { await screen.sync.refresh() }
    }

    @ViewBuilder private var content: some View {
        let sync = screen.sync
        if let status = sync.status {
            SyncStateCard(screen: screen, status: status)
            // The plan's own sentence is all that is said there: no counts, no upsell beyond it.
            if status.syncState != .notOnPlan {
                if let arrived = status.arrivedFingerprint { ArrivedCard(screen: screen, fingerprint: arrived) }
                if !status.waiting.isEmpty { WaitingCard(screen: screen, waiting: status.waiting) }
                CountsCard(status: status)
                if status.conflicts > 0 { ConflictsCard(screen: screen, count: status.conflicts) }
            }
        } else if sync.unreadable {
            ReadFailed(what: "personal sync") { Task { await sync.refresh() } }
        } else {
            ProgressView().controlSize(.small)
        }
    }
}

private struct SyncStateCard: View {
    @ObservedObject var screen: SyncScreen
    let status: PersonalSyncStatus

    var body: some View {
        let word = PersonalSyncLines.stateWord(status.syncState)
        let ready = status.syncState == .ready
        let busy = screen.sync.busy == PersonalSync.now
        SettingsCard(title: "Personal sync") {
            if status.syncState != .notOnPlan { SyncLine(PersonalSyncLines.what) }
            VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
                if !word.word.isEmpty { StatusWord(Tone(word.tone), word.word) }
                Text(status.said)
                    .font(Memnox.Console.sans(Memnox.TextSize.body))
                    .foregroundStyle(Memnox.Console.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if ready { SyncLine(PersonalSyncLines.lastSyncedLine(SessionText.ago(status.lastSyncedAt, now: Date()))) }
            }
            if ready {
                Button(busy ? "Syncing" : "Sync now", systemImage: "arrow.triangle.2.circlepath") {
                    screen.press { await $0.syncNow() }
                }
                .buttonStyle(KitButton(kind: .primary))
                .disabled(busy)
            }
            if let note = screen.note {
                Text(note.text)
                    .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(note.alert ? Memnox.Console.destructive : Memnox.Console.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Six groups of five digits, large and monospaced, so two screens read side by side.
private struct FingerprintDigits: View {
    let fingerprint: String

    var body: some View {
        let groups = PersonalSyncLines.fingerprintGroups(fingerprint)
        Grid(alignment: .leading, horizontalSpacing: Memnox.Spacing.xLarge, verticalSpacing: Memnox.Spacing.small) {
            ForEach(Array(stride(from: 0, to: groups.count, by: 3)), id: \.self) { start in
                GridRow {
                    // By place, since two groups can read the same.
                    ForEach(start..<min(start + 3, groups.count), id: \.self) { index in
                        Text(groups[index])
                            .font(.system(size: SyncLayout.digitSize, weight: .semibold, design: .monospaced))
                            .tracking(SyncLayout.digitTracking)
                            .foregroundStyle(Memnox.Console.foreground)
                    }
                }
            }
        }
        .textSelection(.enabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fingerprint \(fingerprint)")
    }
}

/// On the new Mac: the fingerprint of the key that arrived, accepted only once compared and signed.
private struct ArrivedCard: View {
    @ObservedObject var screen: SyncScreen
    let fingerprint: String

    var body: some View {
        let busy = screen.sync.busy == PersonalSync.accepting
        SettingsCard(title: "A sync key arrived") {
            FingerprintDigits(fingerprint: fingerprint)
            SyncLine(PersonalSyncLines.compareToAccept)
            Button(busy ? "Asking" : "Accept", systemImage: "key") {
                let compared = fingerprint
                screen.press(waits: PersonalSyncLines.keyWaitsLine(offering: false)) { await $0.accept(fingerprint: compared) }
            }
            .buttonStyle(KitButton(kind: .primary))
            .disabled(busy)
        }
    }
}

/// On the Mac holding the key: each of the person's machines waiting for it, offered only once compared and signed.
private struct WaitingCard: View {
    @ObservedObject var screen: SyncScreen
    let waiting: [PersonalSyncMachine]

    var body: some View {
        SettingsCard(title: "Waiting for your key") {
            ForEach(Array(waiting.enumerated()), id: \.element.machineId) { index, machine in
                if index > 0 { SettingsDivider(full: true) }
                let busy = screen.sync.busy == machine.machineId
                SettingsRow(symbol: "laptopcomputer", title: machine.machineId, caption: "Another of your machines, asking for the sync key") {
                    Button(busy ? "Asking" : "Offer", systemImage: "key") {
                        let id = machine.machineId, compared = machine.fingerprint
                        screen.press(waits: PersonalSyncLines.keyWaitsLine(offering: true)) {
                            await $0.offer(machineId: id, fingerprint: compared)
                        }
                    }
                    .buttonStyle(KitButton(kind: .primary))
                    .disabled(busy)
                }
                FingerprintDigits(fingerprint: machine.fingerprint)
            }
            SyncLine(PersonalSyncLines.compareToOffer)
        }
    }
}

/// What this Mac carries, counted by kind, with what the last run left out and what was opened elsewhere.
private struct CountsCard: View {
    let status: PersonalSyncStatus

    private static let symbols: [String: String] = [
        "servers": "server.rack", "skills": "sparkles", "projects": "folder", "rules": "checkmark.shield", "memory": "brain",
    ]

    var body: some View {
        SettingsCard(title: "On this machine") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Memnox.Spacing.regular)], spacing: Memnox.Spacing.regular) {
                ForEach(status.kinds, id: \.kind) { count in
                    let tile = PersonalSyncLines.kindTile(count)
                    StatTile(value: tile.value, label: tile.label, symbol: Self.symbols[count.kind] ?? "square.stack", tint: Memnox.Console.faint)
                }
            }
            ForEach(status.skipped, id: \.self) { SyncLine($0) }
            if !status.openedElsewhere.isEmpty {
                SyncLine(PersonalSyncLines.openedElsewhereLine(status.openedElsewhere.count))
                ForEach(status.openedElsewhere, id: \.self) { repository in
                    Text(repository)
                        .font(Memnox.Console.sans(Memnox.TextSize.micro))
                        .foregroundStyle(Memnox.Console.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }
}

/// The copies a sync replaced unseen, opened here beside this Mac's own, one side kept for each.
private struct ConflictsCard: View {
    @ObservedObject var screen: SyncScreen
    let count: Int

    var body: some View {
        SettingsCard(title: "Conflicts") {
            SyncLine(PersonalSyncLines.conflictsLine(count))
            if let opened = screen.sync.conflicts {
                ForEach(opened) { ConflictRow(screen: screen, conflict: $0) }
                SyncLine(PersonalSyncLines.conflictChoice)
            } else {
                let busy = screen.sync.busy == PersonalSync.opening
                Button(busy ? "Opening" : "Open them") { screen.press { await $0.loadConflicts() } }
                    .buttonStyle(KitButton(kind: .secondary))
                    .disabled(busy)
            }
        }
    }
}

private struct ConflictRow: View {
    @ObservedObject var screen: SyncScreen
    let conflict: PersonalSyncConflict

    var body: some View {
        let busy = screen.sync.busy == conflict.id
        let shape = RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            Text(conflict.name)
                .font(Memnox.Console.sans(Memnox.TextSize.body, .medium))
                .foregroundStyle(Memnox.Console.foreground)
            SyncLine(PersonalSyncLines.conflictCaption(conflict, kept: SessionText.ago(conflict.keptAt, now: Date())))
            HStack(alignment: .top, spacing: Memnox.Spacing.regular) {
                Side(title: "Theirs", text: conflict.theirs)
                Side(title: "Mine", text: conflict.mine ?? "Nothing by this name on this machine.")
            }
            HStack(spacing: Memnox.Spacing.medium) {
                Button("Keep theirs") { keep(.theirs) }
                Button("Keep mine") { keep(.mine) }
            }
            .buttonStyle(KitButton(kind: .secondary))
            .disabled(busy)
        }
        .padding(Memnox.Spacing.large)
        .overlay(shape.strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
    }

    private func keep(_ side: SyncKeep) {
        let id = conflict.id
        screen.press { await $0.resolve(id, keep: side) }
    }
}

/// One side of a conflict, as text.
private struct Side: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
            Text(title)
                .font(Memnox.Console.sans(Memnox.TextSize.footnote, .medium))
                .foregroundStyle(Memnox.Console.muted)
            ScrollView {
                Text(text)
                    .font(Memnox.Console.code(Memnox.TextSize.micro))
                    .foregroundStyle(Memnox.Console.foreground)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: SyncLayout.sideHeight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A quiet line of the sync page.
private struct SyncLine: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(Memnox.Console.sans(Memnox.TextSize.footnote))
            .foregroundStyle(Memnox.Console.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
