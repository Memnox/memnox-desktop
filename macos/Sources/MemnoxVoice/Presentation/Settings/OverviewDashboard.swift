import AppKit
import MemnoxVoiceCore
import SwiftUI

/// The top of the overview: the person greeted for the hour, Talk beside it, and the two keys that do almost
/// everything as two tiles under it, so the page opens on what to press rather than on a logo.
struct OverviewHero: View {
    let name: String?
    let talk: () -> Void

    private enum Layout {
        static let titleSize: CGFloat = 26
        static let keySpacing: CGFloat = 3
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
            HStack(alignment: .center, spacing: Memnox.Spacing.large) {
                VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
                    Text(greeting)
                        .font(Memnox.display(Layout.titleSize, .bold))
                        .foregroundStyle(Memnox.Palette.foreground)
                        .accessibilityAddTraits(.isHeader)
                    Text("Talk to your agents, or dictate anywhere on this Mac.")
                        .font(.system(size: SettingsMetrics.rowTextSize))
                        .foregroundStyle(Memnox.Palette.muted)
                }
                Spacer(minLength: Memnox.Spacing.large)
                Button(action: talk) { Label("Talk to Memnox", systemImage: MenuSymbol.talk) }
                    .buttonStyle(KitButton(kind: .primary))
            }
            HStack(spacing: Memnox.Spacing.large) {
                shortcut(["Right \u{2325}"], title: "Dictate", "Hold, speak, let go. It types where your cursor is.")
                shortcut(["\u{2325}", "Space"], title: "Ask Memnox", "About your agents, or tell them what to do.")
            }
        }
    }

    /// Good morning, afternoon or evening, with their first name once setup has it.
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        return name.map { "\(part), \($0)" } ?? part
    }

    private func shortcut(_ keys: [String], title: String, _ words: String) -> some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
            HStack(spacing: Layout.keySpacing) { ForEach(keys, id: \.self) { Keycap(label: $0) } }
            Text(title)
                .font(.system(size: SettingsMetrics.rowTextSize, weight: .semibold))
                .foregroundStyle(Memnox.Palette.foreground)
            Text(words)
                .font(.system(size: SettingsMetrics.captionSize))
                .foregroundStyle(Memnox.Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SettingsMetrics.cardPadding)
        .background(Memnox.Palette.card, in: RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// The numbers a person checks at a glance in one row: who needs them, what is working, and their dictation.
struct OverviewStats: View {
    let overview: MenuOverview
    let store: DictationStore?

    var body: some View {
        HStack(spacing: Memnox.Spacing.large) {
            StatTile(value: overview.needYou, label: "Need you", symbol: "hand.raised", tint: Memnox.Palette.warm,
                     caption: overview.needYou == 0 ? "Nothing waiting" : "Answer on the notch")
            StatTile(value: overview.working, label: "Working", symbol: "bolt", tint: Memnox.Palette.success,
                     caption: overview.agents == 1 ? "1 agent" : "\(overview.agents) agents")
            if let store { DictationTiles(store: store) }
        }
    }
}

/// The dictation half of the row, watching the store so a dictation counts the moment it lands.
private struct DictationTiles: View {
    @ObservedObject var store: DictationStore

    var body: some View {
        let streak = store.tally.streak(today: Date())
        StatTile(value: store.tally.words, label: "Words dictated", symbol: "waveform", tint: Memnox.Palette.primary,
                 caption: store.tally.wordsPerMinute.map { "\($0) a minute" } ?? "Free, on this Mac")
        StatTile(value: streak, label: "Day streak", symbol: "flame", tint: Memnox.Palette.sky,
                 caption: streak == 1 ? "1 day in a row" : "\(streak) days in a row")
    }
}

/// The latest dictations, newest first and grouped by day, each copyable or forgettable, with a search over them.
struct RecentDictations: View {
    @ObservedObject var store: DictationStore
    @State private var search = ""

    private enum Layout {
        static let timeColumn: CGFloat = 64
        static let actionSide: CGFloat = 28
        static let searchWidth: CGFloat = 200
        static let lines = 4
    }

    var body: some View {
        SettingsSection(title: "Recent dictations") {
            SearchField(prompt: "Search dictations", text: $search)
                .frame(width: Layout.searchWidth)
        } content: {
            SettingsCard {
                if shown.isEmpty {
                    SettingsRow(symbol: MenuSymbol.dictation, title: search.isEmpty ? "Nothing dictated yet" : "Nothing matches",
                                caption: search.isEmpty ? "Hold the right Option key anywhere and speak. What you say lands here too." : nil) {
                        EmptyView()
                    }
                } else {
                    ForEach(Array(days.enumerated()), id: \.element.title) { index, day in
                        if index > 0 { SettingsDivider(full: true) }
                        Text(day.title)
                            .font(.system(size: SettingsMetrics.captionSize, weight: .semibold))
                            .foregroundStyle(Memnox.Palette.muted)
                        ForEach(day.entries) { entry in row(entry) }
                    }
                }
            }
        }
    }

    private var shown: [DictationEntry] {
        let words = search.trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty else { return store.history.entries }
        return store.history.entries.filter { $0.written.localizedCaseInsensitiveContains(words) || ($0.app ?? "").localizedCaseInsensitiveContains(words) }
    }

    private var days: [(title: String, entries: [DictationEntry])] {
        var groups: [(title: String, entries: [DictationEntry])] = []
        for entry in shown {
            let title = Self.dayTitle(entry.at)
            if groups.last?.title == title { groups[groups.count - 1].entries.append(entry) } else { groups.append((title, [entry])) }
        }
        return groups
    }

    private static func dayTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private func row(_ entry: DictationEntry) -> some View {
        HStack(alignment: .top, spacing: Memnox.Spacing.large) {
            VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
                Text(entry.at.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: SettingsMetrics.captionSize).monospacedDigit())
                    .foregroundStyle(Memnox.Palette.muted)
                if let app = entry.app {
                    Text(app)
                        .font(.system(size: SettingsMetrics.captionSize - 1, weight: .medium))
                        .lineLimit(1)
                        .padding(.horizontal, Memnox.Spacing.small)
                        .padding(.vertical, Memnox.Spacing.xxSmall)
                        .background(Capsule().fill(Memnox.Palette.surface))
                        .foregroundStyle(Memnox.Palette.foreground)
                }
            }
            .frame(width: Layout.timeColumn, alignment: .leading)
            Text(entry.written)
                .font(.system(size: SettingsMetrics.rowTextSize))
                .foregroundStyle(Memnox.Palette.foreground)
                .lineLimit(Layout.lines)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            action("doc.on.doc", "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.written, forType: .string)
            }
            action("trash", "Delete from history") { store.forget(entry.id) }
        }
        .padding(.vertical, Memnox.Spacing.xSmall)
    }

    private func action(_ symbol: String, _ help: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: symbol)
                .frame(width: Layout.actionSide, height: Layout.actionSide)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Memnox.Palette.surface))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Memnox.Palette.muted)
        .pointingHand()
        .help(help)
        .accessibilityLabel(help)
    }
}
