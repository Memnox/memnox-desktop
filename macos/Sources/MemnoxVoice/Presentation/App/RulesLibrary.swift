import Foundation
import MemnoxVoiceCore
import SwiftUI

/// Ready-made rules as the console's library lays them out, so nobody has to know an action string to govern a force
/// push: the categories down the side, one search with how many it leaves, and a grid of cards, each with its effect
/// now and Allow, Ask and Deny to pick as the console's choices offer them. A pick only gathers in the bar under the
/// page; nothing is proposed until Review and save, and nothing holds until it is signed on the island.
struct RulesLibrary: View {
    @ObservedObject var shell: AppShellModel
    @ObservedObject var screen: StudioScreen
    let rules: [PolicyRuleView]
    let width: WidthClass
    /// The effect picked on each card, by rule name, kept by the page so its bar can gather them.
    @Binding var picked: [String: RuleEffect]

    /// The category chosen, nil while All is.
    @State private var group: String?
    @State private var query = ""

    private enum Layout {
        static let cardMinimum: CGFloat = 240
        static let gridSpacing: CGFloat = 16
        static let railSpacing: CGFloat = 24
    }

    private static let columns = [GridItem(.adaptive(minimum: Layout.cardMinimum), spacing: Layout.gridSpacing, alignment: .top)]

    var body: some View {
        let groups = ReadyRules.groups(screen.studio.packs ?? [])
        let total = ReadyRuleChanges.flat(groups).count
        let categories = groups.map { (id: $0.id, title: $0.title, count: $0.rules.count) }
        let pool = ReadyRuleChanges.flat(ReadyRules.shown(groups, group: group, query: ""))
        let shown = ReadyRuleChanges.flat(ReadyRules.shown(groups, group: group, query: query))
        VStack(alignment: .leading, spacing: SettingsMetrics.pageSpacing) {
            QuietLine(ProtectionLines.readyIntro(keyTitle: Self.keyTitle))
            if !rail {
                chips(categories, total: total)
            }
            HStack(alignment: .top, spacing: Layout.railSpacing) {
                if rail {
                    CategoryRail(heading: "Categories", allTitle: ProtectionLines.allRules, total: total, categories: categories,
                                 chosen: group) { group = $0 }
                }
                VStack(alignment: .leading, spacing: SettingsMetrics.pageSpacing) {
                    HStack(spacing: Memnox.Spacing.large) {
                        SearchField(prompt: ProtectionLines.search, text: $query)
                            .accessibilityLabel(ProtectionLines.searchLabel)
                        Text(ReadyRuleChanges.shownLine(shown.count, of: pool.count))
                            .font(Memnox.Console.code(Memnox.Console.TextSize.meta).monospacedDigit())
                            .foregroundStyle(Memnox.Console.muted)
                            .contentTransition(.numericText())
                            .fixedSize()
                        pickAll(pool)
                    }
                    if shown.isEmpty {
                        EmptyState(symbol: "magnifyingglass", title: ProtectionLines.noneMatchTitle, detail: ProtectionLines.noneMatchDetail)
                    } else {
                        LazyVGrid(columns: Self.columns, alignment: .leading, spacing: Layout.gridSpacing) {
                            ForEach(shown) { rule in card(rule) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task { await screen.studio.readPacks() }
    }

    private func card(_ rule: ReadyRule) -> some View {
        let live = ReadyRules.inForce(rule, among: rules)
        return ReadyRuleCard(rule: rule, badge: ReadyRuleChanges.badge(rule, among: rules),
                             current: ReadyRuleChanges.current(rule, among: rules), picked: picked[rule.id],
                             canChange: !orgOnly && ReadyRuleChanges.canChange(rule, among: rules),
                             busy: screen.studio.busy != nil,
                             pick: { effect in pick(effect, for: rule) },
                             open: live.map { live in { shell.inspecting = live.name } })
    }

    /// A pick back to what holds drops it, so the bar only counts real changes.
    private func pick(_ effect: RuleEffect, for rule: ReadyRule) {
        if ReadyRuleChanges.current(rule, among: rules) == effect || picked[rule.id] == effect {
            picked[rule.id] = nil
        } else {
            picked[rule.id] = effect
        }
    }

    /// Picks the suggested effect on every card here not added yet: the starter set under All, a category's whole set
    /// once one is chosen.
    @ViewBuilder private func pickAll(_ pool: [ReadyRule]) -> some View {
        let set = group == nil ? ReadyRules.starter : pool
        let left = set.filter { ReadyRules.inForce($0, among: rules) == nil && picked[$0.id] == nil }
        if !orgOnly, !left.isEmpty {
            Button {
                picked = ReadyRuleChanges.picking(left, into: picked, among: rules)
            } label: {
                Label(group == nil ? ProtectionLines.starter : ProtectionLines.everySuggestion, systemImage: RuleSymbols.starter)
            }
            .buttonStyle(KitButton(kind: .secondary))
            .disabled(screen.studio.busy != nil)
            .help("Sets the suggested effect on each rule not added yet; nothing is proposed until you review and save")
            .fixedSize()
        }
    }

    /// The categories as chips where the window is too narrow for the rail.
    private func chips(_ categories: [(id: String, title: String, count: Int)], total: Int) -> some View {
        WordFlow(alignment: .leading, spacing: Memnox.Spacing.small, lineSpacing: Memnox.Spacing.small) {
            FilterChip(title: ProtectionLines.allRules, chosen: group == nil, count: total) { group = nil }
            ForEach(categories, id: \.id) { each in
                FilterChip(title: each.title, chosen: group == each.id, count: each.count) { group = each.id }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Categories")
    }

    /// The Mac signs with the Secure Enclave behind Touch ID.
    private static let keyTitle = "Touch ID"

    /// The organization's scope only reads, so nothing on it offers to change.
    private var orgOnly: Bool { shell.scope == .organization }

    /// The rail stands beside the grid on a wide or medium window, and folds to chips above it below that.
    private var rail: Bool {
        switch width {
        case .wide, .medium: true
        case .narrow, .compact: false
        }
    }
}

/// One ready-made rule: its mark, its name and one line, its effect now as a coloured badge with Changed under it once a
/// pick waits, and Allow, Ask and Deny to pick, the suggested one marked. A card with a pick waiting is outlined in blue.
private struct ReadyRuleCard: View {
    let rule: ReadyRule
    let badge: (word: String, tone: StudioTone)
    /// The effect in force now, nil while not added.
    let current: RuleEffect?
    let picked: RuleEffect?
    let canChange: Bool
    let busy: Bool
    let pick: (RuleEffect) -> Void
    /// Opens the rule in force in the details, where one holds.
    let open: (() -> Void)?

    private enum Layout {
        static let padding: CGFloat = 16
        static let saysLines = 2
        static let mark: CGFloat = 28
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Memnox.Console.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
            HStack(alignment: .top, spacing: Memnox.Spacing.medium) {
                RuleMarks(marks: Array(rule.marks.prefix(1)), actions: Array(rule.actions.prefix(1)), size: Layout.mark)
                Spacer(minLength: Memnox.Spacing.medium)
                VStack(alignment: .trailing, spacing: Memnox.Spacing.xxSmall) {
                    StatusWord(Tone(badge.tone), badge.word)
                    // Reserved on every card, so a marker arriving never moves the title.
                    Text(ProtectionLines.changed)
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.label, .medium))
                        .foregroundStyle(Memnox.Console.primary)
                        .opacity(picked == nil ? 0 : 1)
                        .accessibilityHidden(picked == nil)
                }
            }
            VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
                Text(rule.title)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
                    .foregroundStyle(Memnox.Console.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Text(rule.says)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                    .foregroundStyle(Memnox.Console.muted)
                    .lineLimit(Layout.saysLines)
                    .help("\(rule.says)\n\(rule.actions.joined(separator: ", "))")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack(alignment: .top, spacing: Memnox.Spacing.medium) {
                EffectPicker(chosen: picked ?? current, suggested: rule.effect, disabled: !canChange || busy, pick: pick)
                Spacer(minLength: 0)
                if let open {
                    Button("Details", action: open)
                        .buttonStyle(.plain)
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                        .foregroundStyle(Memnox.Console.primary)
                        .pointingHand()
                        .help(canChange ? "Open the rule in force" : "This rule is changed where it came from")
                }
            }
        }
        .padding(Layout.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Memnox.Console.card, in: shape)
        .overlay(shape.strokeBorder(picked == nil ? Memnox.Console.panelEdge : Memnox.Console.primary, lineWidth: Memnox.Stroke.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(rule.title), \(badge.word)")
    }
}

/// Allow, Ask and Deny side by side, the chosen one filled in its effect's colour, and Suggested under the suggested
/// one as the console marks it. The marker's line is always drawn, so every card is the same height.
private struct EffectPicker: View {
    let chosen: RuleEffect?
    let suggested: RuleEffect
    let disabled: Bool
    let pick: (RuleEffect) -> Void

    private enum Layout {
        static let height: CGFloat = 24
        /// One width for all three, so Suggested sits centred under its own segment.
        static let segment: CGFloat = 52
        static let markerGap: CGFloat = 2
        static let inset: CGFloat = 2
        /// Faded the way a disabled control is, so a rule from a file or the organization reads as fixed here.
        static let disabledFade = 0.5
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Memnox.Console.controlRadius, style: .continuous)
        VStack(alignment: .leading, spacing: Layout.markerGap) {
            HStack(spacing: Layout.inset) {
                ForEach(ReadyRules.effects, id: \.self) { effect in segment(effect) }
            }
            .padding(Layout.inset)
            .overlay(shape.strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
            .disabled(disabled)
            .opacity(disabled ? Layout.disabledFade : 1)
            HStack(spacing: Layout.inset) {
                ForEach(ReadyRules.effects, id: \.self) { effect in
                    Text(effect == suggested ? ProtectionLines.suggested : " ")
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.label))
                        .foregroundStyle(Memnox.Console.muted)
                        .frame(width: Layout.segment)
                }
            }
            .padding(.horizontal, Layout.inset)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(RuleWords.whenTried)
    }

    private func segment(_ effect: RuleEffect) -> some View {
        let on = chosen == effect
        let tone = Tone(effect: effect.rawValue)
        let title = StudioLines.words(effect).title
        return Button { pick(effect) } label: {
            Text(title)
                // Every segment is medium weight, so choosing one never resizes it.
                .font(Memnox.Console.sans(Memnox.Console.TextSize.meta, .medium))
                .foregroundStyle(on ? tone.color : Memnox.Console.muted)
                .frame(width: Layout.segment, height: Layout.height)
                .background(on ? tone.pill : Color.clear,
                            in: RoundedRectangle(cornerRadius: Memnox.Console.controlRadius - Layout.inset, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHand()
        .help(effect == suggested ? "\(title), \(ProtectionLines.suggested.lowercased())" : title)
        .accessibilityLabel(effect == suggested ? "\(title), \(ProtectionLines.suggested)" : title)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}
