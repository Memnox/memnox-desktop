import Foundation
import MemnoxVoiceCore
import SwiftUI

/// Proposing a rule is a decision, so it is a dialog, laid out as the console's: the action, what happens when an agent
/// tries it, then what narrows it, read back as a sentence. Nothing goes in force from here: the runtime raises a
/// proposal the person signs on the island.
struct RuleBuilderSheet: View {
    @ObservedObject var screen: StudioScreen
    /// The agent kinds the MCP Hub found, offered to narrow the rule to one.
    let agents: [String]
    let close: () -> Void

    @State private var effect: RuleEffect = .ask
    @State private var action = ""
    @State private var agent = ""
    @State private var targets = ""
    @State private var carries = ""
    @State private var classes = ""
    @State private var branch = ""
    @State private var folder = ""
    @State private var insteadAction = ""
    @State private var insteadNote = ""
    @State private var reason = ""
    /// Why the runtime refused the last proposal, said in the sheet since the page behind it is covered.
    @State private var problem: String?
    @FocusState private var actionFocused: Bool

    /// The console's examples, each an action string the runtime names, a press away.
    private static let examples: [(action: String, title: String)] = [
        ("git.push-force", "Force push"),
        ("gh.pr-merge", "Merge a pull request"),
        ("vercel.deploy-prod", "Deploy to production"),
        ("filesystem.delete", "Delete files"),
        ("mcp.stripe.*", "Any Stripe tool"),
    ]

    var body: some View {
        RuleDialog(title: "Propose a rule", proposing: sending, canPropose: canPropose, close: close, propose: propose) {
            actionField
            RuleEffectChoice(effects: RuleEffect.allCases, chosen: $effect)
            RuleField(label: "Only for one agent", optional: true) {
                ConsoleSelect(label: "Only for one agent", selection: $agent,
                              options: [SelectOption(value: "", title: "Any agent")]
                                  + agents.map { SelectOption(value: $0, title: McpHubLines.agentLabel($0)) })
            }
            RuleField(label: "Only where it touches", optional: true,
                      hint: "Hosts, paths or repositories, comma separated. Start one with ! to leave it out, so !api.stripe.com is an approved destination.") {
                code("!api.stripe.com, !s3.amazonaws.com", $targets, "Only where it touches")
            }
            RuleField(label: "Only when it carries", optional: true) {
                code("secret, financial", $carries, "Only when it carries")
                RuleHint(text: "What the action carries, as the runtime classifies it. Pick a word below, or type a name your team gave its own patterns.")
                DataClassChips(text: $carries)
            }
            RuleField(label: "Only when it is", optional: true,
                      hint: "What the action does: \(RuleToml.actionClasses.joined(separator: ", ")). A send needs none, since the data it carries and where it goes already narrow it.") {
                code("destructive", $classes, "Only when it is")
            }
            HStack(alignment: .top, spacing: Memnox.Spacing.medium) {
                RuleField(label: "Only on the branch", optional: true) { code("main", $branch, "Only on the branch") }
                RuleField(label: "Only in the folder", optional: true) { code("~/code/app", $folder, "Only in the folder") }
            }
            if effect == .deny { instead }
            RuleField(label: "Why, in your words", optional: true) {
                TextField("What an agent reads when this rule decides", text: $reason).kitField().accessibilityLabel("Why")
            }
            readBack
            RulePreview(code: RuleToml.text(table))
            if let problem {
                Text(problem)
                    .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Console.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { actionFocused = true }
    }

    /// What a refused agent may do instead, which only a deny names and which keeps a refused task finishing.
    private var instead: some View {
        RuleField(label: "What the agent may do instead", optional: true,
                  hint: "A refused agent that is told what it may do still finishes the task. Both halves, or neither.") {
            code("The action it may take, such as http.request", $insteadAction, "The action it may take instead")
            TextField("What the agent reads, such as: send it to an approved destination", text: $insteadNote)
                .kitField()
                .accessibilityLabel("What the agent reads instead")
        }
    }

    /// The action string, with the common ones and the ones the rules already name a press away.
    private var actionField: some View {
        RuleField(label: "Which action") {
            HStack(spacing: Memnox.Spacing.small) {
                TextField("vercel.deploy-prod", text: $action)
                    .kitField()
                    .font(Memnox.Console.code(Memnox.TextSize.body))
                    .focused($actionFocused)
                    .accessibilityLabel("Which action")
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
            WordFlow(alignment: .leading, spacing: Memnox.Spacing.small, lineSpacing: Memnox.Spacing.small) {
                Text("Try one:")
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                    .foregroundStyle(Memnox.Console.muted)
                    .frame(height: Memnox.Console.controlHeight)
                ForEach(Self.examples, id: \.action) { example in
                    FilterChip(title: example.title, chosen: trimmed(action) == example.action) { action = example.action }
                }
            }
            .padding(.top, Memnox.Spacing.xSmall)
        }
    }

    /// What the rule will do, read back before its fields are checked.
    private var readBack: some View {
        let sentence = StudioLines.draftSentence(draft, agentName: McpHubLines.agentLabel)
        return Text(sentence)
            .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
            .foregroundStyle(Memnox.Console.foreground)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Memnox.Spacing.large)
            .background(Memnox.Console.hover, in: RoundedRectangle(cornerRadius: Memnox.Console.cardRadius, style: .continuous))
            .accessibilityLabel("This rule would say: \(sentence)")
    }

    private func code(_ prompt: String, _ text: Binding<String>, _ label: String) -> some View {
        TextField(prompt, text: text)
            .kitField()
            .font(Memnox.Console.code(Memnox.TextSize.body))
            .accessibilityLabel(label)
    }

    /// The actions the rules in force already name, offered so a person need not remember how one is spelt.
    private var known: [String] {
        Array(Set((screen.studio.rules?.rules ?? []).flatMap(\.match.actions))).sorted()
    }

    private var draft: RuleDraftInput {
        let why = trimmed(reason)
        return RuleDraftInput(effect: effect, action: trimmed(action), branches: RuleToml.words(branch),
                              targets: RuleToml.words(targets), agents: agent.isEmpty ? nil : [agent],
                              workingDirectories: RuleToml.words(folder), classes: RuleToml.words(classes),
                              reason: why.isEmpty ? "you chose to \(effect.rawValue) this" : why)
    }

    /// The way round a refusal, only on a deny and only with both halves named.
    private var alternative: RuleAlternative? {
        let action = trimmed(insteadAction)
        let note = trimmed(insteadNote)
        guard effect == .deny, !action.isEmpty, !note.isEmpty else { return nil }
        return RuleAlternative(action: action, note: note)
    }

    /// One half of the way round named without the other, which the runtime would refuse.
    private var halfAnAlternative: Bool {
        effect == .deny && trimmed(insteadAction).isEmpty != trimmed(insteadNote).isEmpty
    }

    /// The rule as it reads in the file, which is what goes up whenever a draft alone could not carry it.
    private var table: RuleTable {
        var table = RuleToml.table(of: draft, dataClassifications: RuleToml.words(carries))
        table.alternative = alternative
        return table
    }

    /// A draft carries neither the data an action holds nor a way round, so a rule naming either goes up as its TOML.
    private var asFile: Bool {
        RuleToml.words(carries) != nil || alternative != nil
    }

    private var canPropose: Bool {
        !trimmed(action).isEmpty && !halfAnAlternative && screen.studio.busy == nil
    }

    private var sending: Bool {
        screen.studio.busy == Studio.proposing || screen.studio.busy == Studio.importing
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func propose() {
        let draft = draft
        let file = asFile ? RuleToml.document([RuleToml.text(table)]) : nil
        Task {
            let outcome = if let file { await screen.studio.importPack(file) } else { await screen.studio.propose(draft) }
            screen.said(outcome)
            if case .failed(let why) = outcome {
                problem = why
                return
            }
            close()
        }
    }
}
