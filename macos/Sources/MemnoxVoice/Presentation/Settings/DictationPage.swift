import AppKit
import MemnoxVoiceCore
import SwiftUI

/// Dictating into any app: the key, whether the workspace's model polishes it, the person's own words, and what was
/// dictated lately, so a lost dictation can be copied again.
struct DictationPage: View {
    @ObservedObject var store: DictationStore
    @AppStorage(DictationKey.enabledKey) private var dictation = true
    @AppStorage(DictationStore.polishKey) private var polish = true
    @AppStorage(DictationStore.liveKey) private var live = true
    @State private var said = ""
    @State private var written = ""

    private enum Layout {
        static let fieldWidth: CGFloat = 200
        /// A history row shows this many lines of what was written before it is cut short.
        static let historyLines = 3
        /// How far a switch that cannot matter right now fades.
        static let restingOpacity = 0.45
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.pageSpacing) {
            SettingsSection(title: "Dictate") {
                SettingsCard {
                    SwitchRow(symbol: MenuSymbol.dictation, title: "Dictate anywhere",
                              detail: "Hold the right Option key and speak, or tap it twice to keep going hands free.",
                              isOn: $dictation)
                    SettingsDivider()
                    // Both only matter while dictation is on, so they rest greyed out with it off.
                    Group {
                        SwitchRow(symbol: "text.cursor", title: "Type as I speak",
                                  detail: "Words appear at the cursor while you talk, and are tidied once you finish.",
                                  isOn: $live)
                        SettingsDivider()
                        SwitchRow(symbol: "sparkles", title: "Polish with Claude Code",
                                  detail: "Your own Claude Code tidies false starts and layout, and lets you edit selected text by voice. Off, the Mac tidies it alone.",
                                  isOn: $polish)
                    }
                    .disabled(!dictation)
                    .opacity(dictation ? 1 : Layout.restingOpacity)
                }
            }
            group("Your words") {
                addRow
                if store.dictionary.words.isEmpty {
                    Text("Names and words Memnox should spell your way, such as a teammate's name or ORB. Fixes you make right after dictating are learned here too.")
                        .font(.system(size: SettingsMetrics.captionSize))
                        .foregroundStyle(Memnox.Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Memnox.Spacing.xLarge)
                        .padding(.bottom, Memnox.Spacing.large)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(store.dictionary.words) { word in
                    MenuDivider()
                    wordRow(word)
                }
            }
            group("Lately") {
                if store.history.entries.isEmpty {
                    Text("What you dictate shows here, so a dictation that went nowhere can be copied again.")
                        .font(.system(size: SettingsMetrics.rowTextSize))
                        .foregroundStyle(Memnox.Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Memnox.Spacing.xLarge)
                        .padding(.vertical, Memnox.Spacing.large)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(store.history.entries) { entry in
                        if entry.id != store.history.entries.first?.id { MenuDivider() }
                        historyRow(entry)
                    }
                    MenuDivider()
                    Button("Clear history") { store.clearHistory() }
                        .buttonStyle(KitButton(kind: .secondary))
                        .padding(.horizontal, Memnox.Spacing.xLarge)
                        .padding(.vertical, Memnox.Spacing.large)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    /// A word of their own: written alone it is a spelling; with what they say it is a replacement or a shortcut.
    private var addRow: some View {
        HStack(spacing: Memnox.Spacing.small) {
            TextField("When I say (optional)", text: $said)
                .kitField()
                .frame(width: Layout.fieldWidth)
            TextField("Write it as", text: $written)
                .kitField()
                .onSubmit(add)
            Button("Add", action: add)
                .buttonStyle(KitButton(kind: .primary))
                .disabled(written.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, Memnox.Spacing.xLarge)
        .padding(.vertical, Memnox.Spacing.large)
    }

    private func add() {
        store.add(DictationWord(said: said, written: written))
        said = ""
        written = ""
    }

    private func wordRow(_ word: DictationWord) -> some View {
        HStack(spacing: Memnox.Spacing.small) {
            if let said = word.said {
                Text(said).foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
                Image(systemName: "arrow.right").foregroundStyle(Memnox.ink(Memnox.Ink.tertiary))
                    .accessibilityLabel("is written as")
            }
            Text(word.written).foregroundStyle(Memnox.Palette.ink).lineLimit(1)
            Spacer(minLength: 0)
            Button {
                store.remove(word.id)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove")
            .accessibilityLabel("Remove \(word.written)")
        }
        .font(Memnox.sans(Memnox.TextSize.callout))
        .padding(.horizontal, Memnox.Spacing.xLarge)
        .padding(.vertical, Memnox.Spacing.medium)
    }

    private func historyRow(_ entry: DictationEntry) -> some View {
        HStack(alignment: .top, spacing: Memnox.Spacing.small) {
            VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                Text(entry.written)
                    .font(Memnox.sans(Memnox.TextSize.callout))
                    .foregroundStyle(Memnox.Palette.ink)
                    .lineLimit(Layout.historyLines)
                Text("\(entry.app ?? "An app"), \(entry.at.formatted(date: .omitted, time: .shortened))")
                    .font(Memnox.sans(Memnox.TextSize.caption))
                    .foregroundStyle(Memnox.ink(Memnox.Ink.tertiary))
            }
            Spacer(minLength: 0)
            Button("Copy") { PromptTyping.leaveOnClipboard(entry.written) }
                .buttonStyle(KitButton(kind: .secondary))
                .accessibilityLabel("Copy this dictation")
        }
        .padding(.horizontal, Memnox.Spacing.xLarge)
        .padding(.vertical, Memnox.Spacing.large)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        SettingsSection(title: title) {
            VStack(spacing: 0) { content() }
                .padding(.vertical, Memnox.Spacing.xSmall)
                .surface()
        }
    }
}
