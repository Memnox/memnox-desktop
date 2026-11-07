import MemnoxVoiceCore
import SwiftUI

/// Each skill's use and its fixes for a skill's page, redrawn whenever the runtime answers.
@MainActor
final class SkillCareScreen: ObservableObject {
    let care: SkillCare
    /// Bumped when the counts or a suggestion change, so every view reading them is drawn again.
    @Published private(set) var tick = 0

    init(care: SkillCare) {
        self.care = care
        care.changed = { [weak self] in
            Task { @MainActor [weak self] in self?.tick += 1 }
        }
    }
}

/// How a skill fared in the chats lately, its fix backlog with a field to add to it, Calibrate, and the suggested fix
/// as a diff with Accept. Accept sends the new version through skill-put, so one reaching further waits on the island.
struct SkillCareSection: View {
    @ObservedObject var care: SkillCareScreen
    @ObservedObject var screen: SkillsScreen
    let skill: SkillView
    @State private var typed = ""

    var body: some View {
        let model = care.care
        let stats = model.stats(skill.name)
        ShellSection(title: "Use and fixes") {
            VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
                Text(SkillCareLines.counts(stats))
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
                    .foregroundStyle(Memnox.Console.foreground)
                if let failures = stats?.recentFailures, !failures.isEmpty {
                    listed("Recent failures", failures)
                }
                if let notes = stats?.notes, !notes.isEmpty { listed("Fix backlog", notes) }
                HStack(spacing: Memnox.Spacing.medium) {
                    TextField("Note a fix, such as read the staged diff first", text: $typed)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(note)
                    Button("Note", action: note)
                        .buttonStyle(KitButton(kind: .secondary))
                        .disabled(SkillCareLines.note(typed) == nil || model.busy != nil)
                }
                HStack(spacing: Memnox.Spacing.medium) {
                    Button("Calibrate") { screen.press { _ in await model.calibrate(skill.name) } }
                        .buttonStyle(KitButton(kind: .secondary))
                        .disabled(model.busy != nil)
                    if let hint = SkillCareLines.calibrateHint(stats) {
                        Text(hint)
                            .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                            .foregroundStyle(Memnox.Console.faint)
                    }
                }
                if let calibration = model.calibration, calibration.name == skill.name { suggestion(calibration) }
            }
        }
        .task(id: skill.name) { await model.refresh() }
    }

    private func suggestion(_ calibration: SkillCalibration) -> some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            Text(SkillCareLines.suggestionTitle(calibration, current: skill.version))
                .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .semibold))
                .foregroundStyle(Memnox.Console.foreground)
            PlanDiffView(lines: SkillCareLines.diff(calibration))
            HStack(spacing: Memnox.Spacing.medium) {
                Button("Accept") {
                    let model = care.care
                    let scope = skill.skillScope ?? .personal
                    screen.press { hub in
                        let outcome = await model.accept(calibration, scope: scope, project: skill.project)
                        await hub.refresh()
                        return outcome
                    }
                }
                .buttonStyle(KitButton(kind: .primary))
                Button("Dismiss") { care.care.dismissSuggestion() }
                    .buttonStyle(KitButton(kind: .secondary))
            }
        }
    }

    private func listed(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
            Text(title)
                .font(Memnox.Console.sans(Memnox.Console.TextSize.meta, .medium))
                .foregroundStyle(Memnox.Console.muted)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                    .foregroundStyle(Memnox.Console.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func note() {
        guard SkillCareLines.note(typed) != nil else { return }
        let words = typed
        let model = care.care
        typed = ""
        screen.press { _ in await model.note(skill.name, words) }
    }
}
