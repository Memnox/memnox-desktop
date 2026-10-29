import Foundation
import MemnoxVoiceCore
import SwiftUI

/// Ready-made rules as cards somebody adds, so nobody has to know an action string to govern a force push: the console's
/// whole library by category, then whatever the runtime's packs add, narrowed by a chip and a search. Adding one
/// proposes it and puts nothing in force.
struct RulesLibrary: View {
    @ObservedObject var shell: AppShellModel
    @ObservedObject var screen: StudioScreen
    let rules: [PolicyRuleView]
    let width: WidthClass
    /// Opens the add dialog for one card or a pack's remaining rules.
    let add: (RuleAdding) -> Void

    /// The chip chosen, nil while All is.
    @State private var group: String?
    @State private var query = ""

    private enum Layout {
        static let groupSpacing: CGFloat = 32
    }

    var body: some View {
        let groups = ReadyRules.groups(screen.studio.packs ?? [])
        let shown = ReadyRules.shown(groups, group: group, query: query)
        ShellSection(title: "Ready-made rules") {
            QuietLine("Add one and choose whether agents are asked or refused. Each one is proposed, so you sign it with Touch ID on the island before it holds.")
            if !orgOnly, !starterLeft.isEmpty {
                Button { add(RuleAdding(title: "Add the starter set", rules: starterLeft)) } label: {
                    Label("Add the starter set", systemImage: RuleSymbols.starter)
                }
                .buttonStyle(KitButton(kind: .secondary))
                .disabled(screen.studio.busy != nil)
                .help("The rules memnox protect starts a machine with, each proposed and signed on its own")
            }
            SearchField(prompt: "Search by tool, command or what it protects: kubectl, refund, secrets", text: $query)
                .accessibilityLabel("Search ready-made rules")
            WordFlow(alignment: .leading, spacing: Memnox.Spacing.small, lineSpacing: Memnox.Spacing.small) {
                FilterChip(title: "All", chosen: group == nil, count: groups.reduce(0) { $0 + $1.rules.count }) { group = nil }
                ForEach(groups) { each in
                    FilterChip(title: each.title, chosen: group == each.id, count: each.rules.count) { group = each.id }
                }
            }
            .padding(.bottom, Memnox.Spacing.medium)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Show ready-made rules about")
            if shown.isEmpty {
                EmptyState(symbol: "magnifyingglass", title: "No ready-made rule matches that.",
                           detail: "Propose your own with Propose a rule.")
            } else {
                VStack(alignment: .leading, spacing: Layout.groupSpacing) {
                    ForEach(shown) { each in groupView(each) }
                }
            }
        }
        .task { await screen.studio.readPacks() }
    }

    private func groupView(_ each: ReadyRuleGroup) -> some View {
        let left = each.rules.filter { ReadyRules.inForce($0, among: rules) == nil }
        return VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
            HStack(alignment: .firstTextBaseline, spacing: Memnox.Spacing.medium) {
                Text(each.title)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
                    .foregroundStyle(Memnox.Console.foreground)
                    .accessibilityAddTraits(.isHeader)
                Text("\(each.rules.count)")
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.meta).monospacedDigit())
                    .foregroundStyle(Memnox.Console.muted)
                Spacer(minLength: Memnox.Spacing.medium)
                // A whole group goes up at once, and only the rules in it not yet in force.
                if left.count > 1, !orgOnly {
                    let category = ReadyRuleCategory(rawValue: each.id) != nil
                    Button { add(RuleAdding(title: category ? "Add every \(each.title.lowercased()) rule" : "Add the whole pack", rules: left)) } label: {
                        Label(category ? "Add all" : "Add the whole pack", systemImage: RuleSymbols.add)
                    }
                    .buttonStyle(KitButton(kind: .secondary))
                    .disabled(screen.studio.busy != nil)
                }
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: Memnox.Spacing.large) {
                ForEach(each.rules) { rule in
                    ReadyRuleCard(rule: rule, live: ReadyRules.inForce(rule, among: rules), canAdd: !orgOnly,
                             busy: screen.studio.busy != nil,
                             add: { add(RuleAdding(title: "Add a rule", rules: [rule])) },
                             change: { name in shell.inspecting = name })
                }
            }
        }
    }

    /// The starter set's rules not yet in force.
    private var starterLeft: [ReadyRule] {
        ReadyRules.starter.filter { ReadyRules.inForce($0, among: rules) == nil }
    }

    /// The organization's scope only reads, so nothing on it offers to add.
    private var orgOnly: Bool { shell.scope == .organization }

    /// Three across on a wide window, two on a medium one, one below, as the console's grid steps down.
    private var columns: [GridItem] {
        let count: Int
        switch width {
        case .wide: count = 3
        case .medium: count = 2
        case .narrow, .compact: count = 1
        }
        return Array(repeating: GridItem(.flexible(), spacing: Memnox.Spacing.large, alignment: .top), count: count)
    }
}

/// One ready-made rule: what it is about, whether it holds, and the way to add it, or to open it once it holds.
private struct ReadyRuleCard: View {
    let rule: ReadyRule
    /// The rule in force it stands for, where one is.
    let live: PolicyRuleView?
    let canAdd: Bool
    let busy: Bool
    let add: () -> Void
    let change: (String) -> Void

    private enum Layout {
        static let padding: CGFloat = 16
        static let actionLines = 2
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Memnox.Console.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
            HStack(alignment: .top, spacing: Memnox.Spacing.large) {
                RuleMarks(marks: rule.marks, actions: rule.actions)
                Spacer(minLength: Memnox.Spacing.medium)
                pill
            }
            VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
                Text(rule.title)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
                    .foregroundStyle(Memnox.Console.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Text(rule.says)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                    .foregroundStyle(Memnox.Console.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text(rule.actions.joined(separator: ", "))
                    .font(Memnox.Console.code(Memnox.Console.TextSize.label))
                    .foregroundStyle(Memnox.Console.faint)
                    .lineLimit(Layout.actionLines)
                    .help(rule.actions.joined(separator: ", "))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if canAdd || live != nil {
                Button(action: press) {
                    if live == nil { Label("Add", systemImage: RuleSymbols.add) } else { Text("Change") }
                }
                .buttonStyle(KitButton(kind: .secondary, wide: true))
                .disabled(live == nil && busy)
                .help(live == nil ? RuleWords.proposeDescription : "Open the rule in force to remove it")
            }
        }
        .padding(Layout.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Memnox.Console.card, in: shape)
        .overlay(shape.strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
    }

    @ViewBuilder private var pill: some View {
        if let live, let effect = live.ruleEffect {
            StatusWord(Tone(effect: effect.rawValue), "In force as \(StudioLines.words(effect).title.lowercased())")
        } else {
            StatusWord(Tone(effect: rule.effect.rawValue), StudioLines.words(rule.effect).title)
        }
    }

    private func press() {
        if let live { change(live.name) } else { add() }
    }
}
