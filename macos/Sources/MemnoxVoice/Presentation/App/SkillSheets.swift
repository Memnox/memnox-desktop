import MemnoxVoiceCore
import SwiftUI

private enum SheetLayout {
    static let width: CGFloat = 560
    static let minHeight: CGFloat = 360
    static let logo: CGFloat = 20
    static let versionWidth: CGFloat = 120
    static let instructionsHeight: CGFloat = 160
    /// An agent that cannot take skills is drawn faint, so it reads as there and not choosable.
    static let unavailable = 0.55
}

/// A sheet's frame: the title with what it is on, its body scrolling, and its buttons along the foot.
struct SkillSheetFrame<Body: View, Footer: View>: View {
    let title: String
    var step: String?
    @ViewBuilder let content: Body
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Memnox.Spacing.large) {
                Text(title)
                    .font(Memnox.Console.sans(Memnox.TextSize.headline, .semibold))
                    .foregroundStyle(Memnox.Console.foreground)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Memnox.Spacing.medium)
                if let step {
                    Text(step)
                        .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                        .foregroundStyle(Memnox.Console.muted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, Memnox.Spacing.xxLarge)
            .frame(height: ShellMetrics.barHeight)
            ShellDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: Memnox.Spacing.xLarge) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Memnox.Spacing.xxLarge)
            }
            ShellDivider()
            HStack(spacing: Memnox.Spacing.medium) { footer }
                .padding(.horizontal, Memnox.Spacing.xxLarge)
                .padding(.vertical, Memnox.Spacing.large)
        }
        .frame(width: SheetLayout.width)
        .frame(minHeight: SheetLayout.minHeight)
        .background(Memnox.Console.background)
        .buttonStyle(QuietButton())
    }
}

/// Who a skill is given to, ticked per agent with what each keeps of it. Before Continue the sheet says what conversion
/// loses for the agents being given it; giving waits on the island, taking away happens at once.
struct AssignSkillSheet: View {
    @ObservedObject var screen: SkillsScreen
    let view: SkillsHubView
    let skill: SkillView
    let close: () -> Void
    @State private var chosen: Set<String>
    @State private var reviewing = false
    @State private var sending = false

    init(screen: SkillsScreen, view: SkillsHubView, skill: SkillView, close: @escaping () -> Void) {
        self.screen = screen
        self.view = view
        self.skill = skill
        self.close = close
        _chosen = State(initialValue: Set(skill.agents))
    }

    var body: some View {
        let changes = SkillsLines.assignmentChanges(current: skill.agents, chosen: chosen)
        let losses = SkillsLines.conversionLosses(skill.compatibility, chosen: Set(changes.give))
        let nothing = changes.give.isEmpty && changes.take.isEmpty
        SkillSheetFrame(title: "Assign skill to agents", step: reviewing ? "What changes" : skill.name) {
            if reviewing {
                QuietLine("Each agent keeps skills in its own format, and these lose something on the way.")
                ForEach(losses, id: \.label) { each in
                    VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
                        Text(each.label)
                            .font(Memnox.Console.sans(Memnox.TextSize.body, .medium))
                            .foregroundStyle(Memnox.Console.foreground)
                        ForEach(each.loses, id: \.self) { loss in QuietLine("\u{2022} \(loss)") }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
                    ForEach(agents, id: \.agent) { agent in row(agent) }
                }
            }
            QuietLine("Giving a skill to an agent waits for your signature with Touch ID on the island. Taking it away happens at once.")
        } footer: {
            Button("Cancel", action: close).buttonStyle(KitButton(kind: .secondary)).keyboardShortcut(.cancelAction)
            if reviewing {
                Button("Back") { reviewing = false }.buttonStyle(KitButton(kind: .secondary))
            }
            Spacer(minLength: Memnox.Spacing.medium)
            Button("Continue") {
                if reviewing || losses.isEmpty { send() } else { reviewing = true }
            }
            .buttonStyle(KitButton(kind: .primary))
            .keyboardShortcut(.defaultAction)
            .disabled(nothing || sending)
        }
    }

    /// Agents installed here, and any it is still given to that are not.
    private var agents: [SkillAgentView] {
        view.agents.filter { $0.installed || skill.agents.contains($0.agent) }
    }

    private func row(_ agent: SkillAgentView) -> some View {
        let compatibility = skill.compatibility.first { $0.agent == agent.agent }
        let takes = compatibility?.supported ?? true
        let ticked = Binding(get: { chosen.contains(agent.agent) }, set: { on in
            if on { chosen.insert(agent.agent) } else { chosen.remove(agent.agent) }
        })
        return Toggle(isOn: ticked) {
            HStack(spacing: Memnox.Spacing.regular) {
                BrandLogo(agent: agent.agent, name: agent.label, size: SheetLayout.logo)
                VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                    Text(agent.label)
                        .font(Memnox.Console.sans(Memnox.TextSize.body))
                        .foregroundStyle(Memnox.Console.foreground)
                    Text(compatibility.map(SkillsLines.compatibility) ?? "Takes it as written")
                        .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                        .foregroundStyle(Memnox.Console.muted)
                }
            }
        }
        .toggleStyle(CheckboxStyle())
        .disabled(!takes)
        .opacity(takes ? 1 : SheetLayout.unavailable)
        .padding(.vertical, Memnox.Spacing.xSmall)
    }

    private func send() {
        sending = true
        let name = skill.name
        let wanted = chosen
        Task {
            let results = await screen.skills.assign(name, to: wanted)
            screen.note = SkillsLines.assignedNote(proposed: results.proposed, done: results.done, failed: results.failed, keyTitle: "Touch ID")
            close()
        }
    }
}

/// A skill written here, kept in the person's Memnox folder; one reaching further than before waits on a signature.
struct NewSkillSheet: View {
    @ObservedObject var screen: SkillsScreen
    let close: () -> Void
    @State private var form = SkillForm(version: SkillsLines.firstVersion)
    @State private var problem: String?

    var body: some View {
        SkillSheetFrame(title: "New skill") {
            HStack(alignment: .top, spacing: Memnox.Spacing.large) {
                labelled("Name") { TextField("release-notes", text: $form.name).kitField() }
                labelled("Version") { TextField("", text: $form.version).kitField() }
                    .frame(width: SheetLayout.versionWidth)
            }
            labelled("What it is for") {
                TextField("Drafts release notes from merged pull requests", text: $form.description).kitField()
            }
            labelled("Category, optional") { TextField("Writing", text: $form.category).kitField() }
            labelled("Instructions") {
                TextEditor(text: $form.instructions)
                    .font(Memnox.Console.code(Memnox.TextSize.footnote))
                    .scrollContentBackground(.hidden)
                    .padding(Memnox.Spacing.small)
                    .frame(height: SheetLayout.instructionsHeight)
                    .background(Memnox.Console.field, in: RoundedRectangle(cornerRadius: Memnox.Spacing.medium, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Memnox.Spacing.medium, style: .continuous)
                        .strokeBorder(Memnox.Console.fieldEdge, lineWidth: Memnox.Stroke.hairline))
                    .accessibilityLabel("Instructions")
            }
            labelled("Agent tools it needs, separated by commas") {
                TextField("Read, Bash", text: $form.tools).kitField().font(Memnox.Console.code(Memnox.TextSize.footnote))
            }
            labelled("Commands it runs, separated by commas") {
                TextField("gh, git", text: $form.commands).kitField().font(Memnox.Console.code(Memnox.TextSize.footnote))
            }
            if let problem {
                Text(problem)
                    .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Console.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } footer: {
            Button("Cancel", action: close).buttonStyle(KitButton(kind: .secondary)).keyboardShortcut(.cancelAction)
            Spacer(minLength: Memnox.Spacing.medium)
            Button("Add skill", action: save)
                .buttonStyle(KitButton(kind: .primary))
                .keyboardShortcut(.defaultAction)
                .disabled(screen.skills.busy != nil)
        }
    }

    private func save() {
        switch SkillsLines.draft(from: form) {
        case .failure(let missing):
            problem = missing.why
        case .success(let draft):
            Task {
                let outcome = await screen.skills.put(draft)
                if case .failed(let why) = outcome {
                    problem = why
                    return
                }
                screen.said(outcome)
                close()
            }
        }
    }

    private func labelled<Field: View>(_ label: String, @ViewBuilder field: () -> Field) -> some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
            Text(label)
                .font(Memnox.Console.sans(Memnox.TextSize.footnote, .medium))
                .foregroundStyle(Memnox.Console.muted)
            field()
        }
    }
}
