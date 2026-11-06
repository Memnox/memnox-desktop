import Foundation
import MemnoxVoiceCore
import SwiftUI

/// What Review and save opens: the changes the cards gathered, each still its own proposal.
struct RuleAdding: Identifiable {
    let changes: [ReadyRuleChange]

    var id: String { changes.map { "\($0.rule.id)=\($0.to.rawValue)" }.joined(separator: "\n") }
}

/// Review and save, as the console's choices save: each rule with what it goes from and to, and the rules as the runtime
/// reads them. Saving proposes them, a changed rule as its old one taken out and its new one added, and each still
/// waits on the island for its own Touch ID signature.
struct RuleAddSheet: View {
    @ObservedObject var screen: StudioScreen
    let adding: RuleAdding
    let close: () -> Void
    /// Called once the runtime took every proposal, so the page clears its picks.
    let saved: () -> Void

    @State private var problem: String?
    @State private var sending = false

    private enum Layout {
        static let rowMark: CGFloat = 28
    }

    /// The Mac signs with the Secure Enclave behind Touch ID.
    private static let keyTitle = "Touch ID"

    var body: some View {
        RuleDialog(title: ProtectionLines.review, description: ProtectionLines.reviewDescription(keyTitle: Self.keyTitle),
                   confirm: (idle: ProtectionLines.save, busy: ProtectionLines.saving), proposing: sending,
                   canPropose: screen.studio.busy == nil && !adding.changes.isEmpty, close: close, propose: propose) {
            QuietLine("\(ReadyRuleChanges.countLine(adding.changes.count)). \(ProtectionLines.previewed)")
            ShellPanel {
                ForEach(Array(adding.changes.enumerated()), id: \.element.id) { index, change in
                    if index > 0 { ShellDivider() }
                    row(change)
                }
            }
            if !ReadyRuleChanges.removals(adding.changes).isEmpty {
                QuietLine("A rule already in force is changed by taking it out and adding it again, so each waits for your signature on the island.")
            }
            RulePreview(code: ReadyRuleChanges.toml(adding.changes) ?? "")
            if let problem {
                Text(problem)
                    .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Console.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(_ change: ReadyRuleChange) -> some View {
        HStack(spacing: Memnox.Spacing.large) {
            RuleMarks(marks: Array(change.rule.marks.prefix(1)), actions: Array(change.rule.actions.prefix(1)), size: Layout.rowMark)
            VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                Text(change.rule.title)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
                    .foregroundStyle(Memnox.Console.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                QuietLine(ReadyRuleChanges.changeLine(change))
            }
            Spacer(minLength: Memnox.Spacing.medium)
            StatusWord(Tone(effect: change.to.rawValue), StudioLines.words(change.to).title)
        }
        .padding(.horizontal, ShellMetrics.rowPaddingH)
        .padding(.vertical, ShellMetrics.rowPaddingV)
    }

    /// Takes out each changed rule first, then proposes every new table in one import, stopping at the first refusal.
    private func propose() {
        let removals = ReadyRuleChanges.removals(adding.changes)
        let toml = ReadyRuleChanges.toml(adding.changes)
        sending = true
        Task {
            defer { sending = false }
            for name in removals {
                let outcome = await screen.studio.remove(name)
                if case .failed(let why) = outcome {
                    problem = why
                    return
                }
            }
            guard let toml else { return }
            let outcome = await screen.studio.importPack(toml)
            screen.said(outcome)
            if case .failed(let why) = outcome {
                problem = why
                return
            }
            saved()
            close()
        }
    }
}
