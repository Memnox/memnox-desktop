import Foundation
import MemnoxVoiceCore
import SwiftUI

/// What a press on a card or a pack's heading opens: the rules it adds, each effect still to choose.
struct RuleAdding: Identifiable {
    let title: String
    let rules: [ReadyRule]

    var id: String { rules.map(\.id).joined(separator: "\n") }
}

/// Adding ready-made rules, one from its card or a pack's at once. Every effect can be changed before anything is
/// proposed, and each rule still waits on the island for its own Touch ID signature.
struct RuleAddSheet: View {
    @ObservedObject var screen: StudioScreen
    let adding: RuleAdding
    let close: () -> Void

    @State private var effects: [String: RuleEffect] = [:]
    @State private var problem: String?

    private enum Layout {
        static let rowEffectWidth: CGFloat = 120
        static let rowMark: CGFloat = 28
    }

    var body: some View {
        RuleDialog(title: adding.title, proposing: sending, canPropose: screen.studio.busy == nil,
                   close: close, propose: propose) {
            if let single = adding.rules.first, adding.rules.count == 1 {
                VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
                    RuleMarks(marks: single.marks, actions: single.actions)
                        .padding(.bottom, Memnox.Spacing.small)
                    Text(single.title)
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
                        .foregroundStyle(Memnox.Console.foreground)
                    QuietLine(single.says)
                }
                RuleEffectChoice(effects: ReadyRules.effects, chosen: binding(single), recommended: single.effect)
            } else {
                ShellPanel {
                    ForEach(Array(adding.rules.enumerated()), id: \.element.id) { index, rule in
                        if index > 0 { ShellDivider() }
                        row(rule)
                    }
                }
            }
            RulePreview(code: preview)
            if let problem {
                Text(problem)
                    .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Console.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sending: Bool {
        screen.studio.busy == Studio.proposing || screen.studio.busy == Studio.importing
    }

    private func row(_ rule: ReadyRule) -> some View {
        HStack(spacing: Memnox.Spacing.large) {
            RuleMarks(marks: Array(rule.marks.prefix(1)), actions: Array(rule.actions.prefix(1)), size: Layout.rowMark)
            VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                Text(rule.title)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
                    .foregroundStyle(Memnox.Console.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                QuietLine(rule.says)
            }
            Spacer(minLength: Memnox.Spacing.medium)
            ConsoleSelect(label: "When an agent tries \(rule.title)", selection: binding(rule),
                          options: ReadyRules.effects.map { SelectOption(value: $0, title: StudioLines.words($0).title) })
                .frame(width: Layout.rowEffectWidth)
        }
        .padding(.horizontal, ShellMetrics.rowPaddingH)
        .padding(.vertical, ShellMetrics.rowPaddingV)
    }

    private func binding(_ rule: ReadyRule) -> Binding<RuleEffect> {
        Binding(get: { effects[rule.id] ?? rule.effect }, set: { effects[rule.id] = $0 })
    }

    private var picks: [(rule: ReadyRule, effect: RuleEffect)] {
        adding.rules.map { ($0, effects[$0.id] ?? $0.effect) }
    }

    /// The rules in the runtime's own file format, which is exactly what is imported.
    private var preview: String {
        ReadyRules.toml(picks) ?? ""
    }

    private func propose() {
        guard let toml = ReadyRules.toml(picks) else { return }
        Task {
            let outcome = await screen.studio.importPack(toml)
            screen.said(outcome)
            if case .failed(let why) = outcome {
                problem = why
                return
            }
            close()
        }
    }
}
