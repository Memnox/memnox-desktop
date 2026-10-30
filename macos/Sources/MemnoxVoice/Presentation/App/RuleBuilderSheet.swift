import Foundation
import MemnoxVoiceCore
import SwiftUI

/// When, then, and scope, read back as a sentence before it is proposed; the rule as written is there for those who
/// want it. Nothing goes in force from here: the runtime raises a proposal the person signs on the island.
struct RuleBuilderSheet: View {
    @ObservedObject var screen: StudioScreen
    /// The agent kinds the MCP Hub found, offered to narrow the rule to one.
    let agents: [String]
    let close: () -> Void

    @State private var effect: RuleEffect = .ask
    @State private var action = ""
    @State private var agent = ""
    @State private var target = ""
    @State private var branch = ""
    @State private var folder = ""
    @State private var reason = ""
    @State private var written = false
    /// Why the runtime refused the last proposal, said in the sheet since the page behind it is covered.
    @State private var problem: String?
    @FocusState private var actionFocused: Bool

    private static let width: CGFloat = 560
    private static let writtenHeight: CGFloat = 190

    var body: some View {
        VStack(spacing: 0) {
            Text("New rule")
                .font(Memnox.Console.sans(Memnox.TextSize.headline, .semibold))
                .foregroundStyle(Memnox.Console.foreground)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Memnox.Spacing.xxLarge)
                .frame(height: ShellMetrics.barHeight)
            ShellDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: Memnox.Spacing.xLarge) {
                    when
                    then
                    Text(StudioLines.draftSentence(draft, agentName: McpHubLines.agentLabel))
                        .font(Memnox.Console.sans(Memnox.TextSize.body))
                        .foregroundStyle(Memnox.Console.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, ShellMetrics.rowPaddingH)
                        .padding(.vertical, Memnox.Spacing.large)
                        .background(Memnox.Console.card, in: RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous))
                        .accessibilityLabel("This rule would say: \(StudioLines.draftSentence(draft, agentName: McpHubLines.agentLabel))")
                    DisclosureGroup("Show the rule as written", isExpanded: $written) {
                        ScrollView {
                            Text(asWritten)
                                .font(Memnox.Console.code(Memnox.TextSize.micro))
                                .foregroundStyle(Memnox.Console.foreground)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(Memnox.Spacing.large)
                        }
                        .frame(maxHeight: Self.writtenHeight)
                        .background(Memnox.Console.card, in: RoundedRectangle(cornerRadius: Memnox.Spacing.medium, style: .continuous))
                    }
                    .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Console.muted)
                    if let problem {
                        Text(problem)
                            .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                            .foregroundStyle(Memnox.Console.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Memnox.Spacing.xxLarge)
            }
            ShellDivider()
            footer
        }
        .frame(width: Self.width)
        .background(Memnox.Console.background)
        .buttonStyle(QuietButton())
        .onAppear { actionFocused = true }
    }

    private var when: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            legend("When")
            Picker("Which agent", selection: $agent) {
                Text("Any agent").tag("")
                ForEach(agents, id: \.self) { kind in
                    Text(McpHubLines.agentLabel(kind)).tag(kind)
                }
            }
            .labelsHidden()
            .accessibilityLabel("Which agent")
            HStack(spacing: Memnox.Spacing.small) {
                TextField("git.push", text: $action)
                    .kitField()
                    .font(Memnox.Console.code(Memnox.TextSize.body))
                    .focused($actionFocused)
                    .accessibilityLabel("The action")
                if !known.isEmpty {
                    Menu {
                        ForEach(known, id: \.self) { each in
                            Button(each) { action = each }
                        }
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Pick an action a rule already names")
                    .accessibilityLabel("Actions your rules already name")
                }
            }
            HStack(spacing: Memnox.Spacing.medium) {
                TextField("On, optional", text: $target).kitField().accessibilityLabel("Target")
                TextField("Branch, optional", text: $branch).kitField().accessibilityLabel("Branch")
                TextField("Folder, optional", text: $folder).kitField().accessibilityLabel("Folder")
            }
        }
    }

    private var then: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            legend("Then")
            HStack(spacing: Memnox.Spacing.medium) {
                ForEach(RuleEffect.allCases, id: \.self) { each in
                    choice(each)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Then")
            TextField("Why, in your words", text: $reason).kitField().accessibilityLabel("Why")
        }
    }

    private var footer: some View {
        HStack(spacing: Memnox.Spacing.medium) {
            QuietLine("It goes in force when you sign it with Touch ID.")
            Spacer(minLength: Memnox.Spacing.medium)
            Button("Cancel", action: close).buttonStyle(KitButton(kind: .secondary)).keyboardShortcut(.cancelAction)
            Button("Propose", action: propose)
                .buttonStyle(KitButton(kind: .primary))
                .keyboardShortcut(.defaultAction)
                .disabled(trimmed(action).isEmpty || screen.studio.busy != nil)
        }
        .padding(.horizontal, Memnox.Spacing.xxLarge)
        .padding(.vertical, Memnox.Spacing.large)
    }

    private func legend(_ text: String) -> some View {
        Text(text)
            .font(Memnox.Console.sans(Memnox.TextSize.footnote, .semibold))
            .foregroundStyle(Memnox.Console.muted)
            .accessibilityAddTraits(.isHeader)
    }

    private func choice(_ each: RuleEffect) -> some View {
        let on = effect == each
        let words = StudioLines.words(each)
        let shape = RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
        return Button { effect = each } label: {
            VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
                StatusWord(Tone(effect: each.rawValue), words.title)
                Text(words.says)
                    .font(Memnox.Console.sans(Memnox.TextSize.micro))
                    .foregroundStyle(Memnox.Console.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Memnox.Spacing.large)
            .padding(.vertical, Memnox.Spacing.regular)
            .background(on ? Memnox.Console.hover : Color.clear, in: shape)
            .overlay(shape.strokeBorder(on ? Memnox.Console.primary : Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .pointingHand()
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    /// The actions the rules in force already name, offered so a person need not remember how one is spelt.
    private var known: [String] {
        Array(Set((screen.studio.rules?.rules ?? []).flatMap(\.match.actions))).sorted()
    }

    private var draft: RuleDraftInput {
        let why = trimmed(reason)
        return RuleDraftInput(effect: effect, action: trimmed(action), branches: list(branch), targets: list(target),
                              agents: agent.isEmpty ? nil : [agent], workingDirectories: list(folder),
                              reason: why.isEmpty ? "you chose to \(effect.rawValue) this" : why)
    }

    /// The draft as it goes to the runtime, keys sorted so it reads the same each time.
    private var asWritten: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(draft) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private func list(_ value: String) -> [String]? {
        let word = trimmed(value)
        return word.isEmpty ? nil : [word]
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func propose() {
        let draft = draft
        Task {
            let outcome = await screen.studio.propose(draft)
            screen.said(outcome)
            if case .failed(let why) = outcome {
                problem = why
                return
            }
            close()
        }
    }
}
