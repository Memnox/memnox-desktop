import AppKit
import MemnoxVoiceCore
import SwiftUI
import UniformTypeIdentifiers

/// What agents may do here, read first and changed second. Every rule is said as a sentence before its fields, and a
/// rule built here only goes in force once the person signs it on the island with Touch ID.
struct PoliciesDestination: View {
    @ObservedObject var shell: AppShellModel
    @ObservedObject var screen: StudioScreen
    @ObservedObject var island: IslandModel
    let home: HomeModel?
    let width: WidthClass

    @State private var filter: RuleEffect?
    @State private var building = false

    private static let effectWidth: CGFloat = 200

    var body: some View {
        page
            .task { await screen.studio.refresh() }
            // A signed or declined proposal leaves the island, and the rules are read again so they show what holds.
            .onChange(of: island.waiting.count) { Task { await screen.studio.refresh() } }
            .sheet(isPresented: $building) {
                RuleBuilderSheet(screen: screen, agents: shell.hub?.hub.hub?.agents.map(\.agent) ?? []) { building = false }.consoleLook()
            }
    }

    @ViewBuilder private var page: some View {
        let studio = screen.studio
        if let view = studio.rules {
            let picked = view.rules.first { $0.name == shell.inspecting }
            InspectorLayout(width: width, title: picked?.name, close: { shell.inspecting = nil }) {
                ShellScroll(width: width) {
                    NoteBanner(text: screen.note)
                    effects
                    if let progress = studio.progress { LetGo(screen: screen, home: home, progress: progress) }
                    alwaysAsk(view)
                    rulesInForce(view)
                    if shell.supports("index-list") == true, let index = shell.index { IndexPacks(screen: index) }
                    TryAction(screen: screen)
                }
            } detail: {
                if let picked { RuleDetail(shell: shell, screen: screen, rule: picked) }
            }
        } else if studio.unreadable {
            ShellScroll(width: width) { ReadFailed(what: "the rules") { Task { await studio.refresh() } } }
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The three effects, each explained once, before any rule uses them.
    private var effects: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.effectWidth), spacing: Memnox.Spacing.regular)],
                  spacing: Memnox.Spacing.regular) {
            ForEach(RuleEffect.allCases, id: \.self) { effect in
                let words = StudioLines.words(effect)
                VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
                    StatusWord(Tone(effect: effect.rawValue), words.title)
                    QuietLine(words.says)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ShellMetrics.rowPaddingH)
                .padding(.vertical, ShellMetrics.rowPaddingV)
                .background(Memnox.Console.card, in: RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
                    .strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func alwaysAsk(_ view: PolicyRulesView) -> some View {
        ShellSection(title: "Always ask me before") {
            ShellPanel {
                ForEach(Array(StudioLines.alwaysAsk.enumerated()), id: \.element.id) { index, each in
                    if index > 0 { ShellDivider() }
                    let on = StudioLines.switchOn(view.rules, action: each.draft.action, branches: each.draft.branches)
                    ShellRow(title: each.title,
                             caption: on ? "A rule asks about this now" : "Agents go ahead unless another rule says otherwise") {
                        EmptyView()
                    } trailing: {
                        // Only turning one on is offered here: a switch that is on is a rule, removed from its inspector.
                        Toggle(each.title, isOn: Binding(get: { on }, set: { want in
                            if want { screen.press { await $0.propose(each.draft) } }
                        }))
                        .toggleStyle(MemnoxSwitch())
                        .labelsHidden()
                        .disabled(on || screen.studio.busy != nil)
                    }
                }
            }
        }
    }

    private func rulesInForce(_ view: PolicyRulesView) -> some View {
        // The scope selector shows the person's rules or the organization's, never the two mixed.
        let scoped = ShellLines.inScope(view.rules, shell.scope) { ScopeLines.rule($0) == .organization }
        let counts = StudioLines.countsByEffect(scoped)
        let shown = scoped.filter { filter == nil || $0.ruleEffect == filter }
        return ShellSection(title: "Rules in force") {
            HStack(spacing: Memnox.Spacing.medium) {
                Button(action: exportRules) { Label("Export", systemImage: "square.and.arrow.down") }
                    .buttonStyle(KitButton(kind: .secondary))
                    .help("Save the rules set on this computer as a TOML file")
                Button(action: importPack) { Label("Import", systemImage: "square.and.arrow.up") }
                    .buttonStyle(KitButton(kind: .secondary))
                    .disabled(screen.studio.busy == Studio.importing)
                    .help("Propose every rule in a TOML file, each signed on its own")
                Button { building = true } label: { Label("New rule", systemImage: "plus") }
                    .buttonStyle(KitButton(kind: .primary))
            }
        } content: {
            HStack(spacing: Memnox.Spacing.small) {
                FilterChip(title: "All \(scoped.count)", chosen: filter == nil) { filter = nil }
                ForEach(RuleEffect.allCases, id: \.self) { effect in
                    FilterChip(title: "\(StudioLines.words(effect).title) \(counts[effect] ?? 0)", chosen: filter == effect) { filter = effect }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Show rules that")
            if !view.problems.isEmpty {
                VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
                    ForEach(view.problems, id: \.file) { problem in
                        Text("\(problem.file): \(problem.issues.joined(separator: " "))")
                            .font(Memnox.Console.sans(Memnox.TextSize.footnote, .medium))
                            .foregroundStyle(Memnox.Console.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ShellMetrics.rowPaddingH)
                .padding(.vertical, ShellMetrics.rowPaddingV)
                .background(Memnox.Console.card, in: RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous))
                .accessibilityElement(children: .combine)
            }
            if shell.scope == .organization {
                QuietLine(scoped.isEmpty ? ShellLines.noOrganizationItems : ShellLines.organizationReadOnly)
            }
            if shown.isEmpty {
                EmptyState(symbol: "checkmark.shield", title: "No rules of this kind",
                           detail: "Build one with New rule, or turn on a switch above.")
            } else {
                ShellPanel {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, rule in
                        if index > 0 { ShellDivider() }
                        ShellRow(title: rule.sentence, caption: StudioLines.sourceWords(rule), chosen: rule.name == shell.inspecting,
                                 action: { shell.inspecting = rule.name }) {
                            EmptyView()
                        } trailing: {
                            ScopeChip(ScopeLines.rule(rule))
                            StatusWord(Tone(effect: rule.effect), StudioLines.title(rule.effect))
                        }
                    }
                }
            }
        }
    }

    /// A pack is a TOML file: saved where the person picks in a save panel, and imported one rule proposal at a time.
    private func exportRules() {
        Task {
            let toml = await screen.studio.exportToml()
            guard let toml, StudioLines.exportedCount(toml) > 0 else {
                screen.note = StudioLines.nothingToExport
                return
            }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: "toml")].compactMap { $0 }
            panel.nameFieldStringValue = "memnox-rules.toml"
            panel.prompt = "Export"
            // A cancelled save says nothing, since nothing happened.
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try toml.write(to: url, atomically: true, encoding: .utf8)
                screen.note = StudioLines.packSaved(StudioLines.exportedCount(toml))
            } catch {
                screen.note = "That file could not be written: \(error.localizedDescription)"
            }
        }
    }

    private func importPack() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "toml"), .plainText].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let toml = try? String(contentsOf: url, encoding: .utf8) else {
            screen.note = "That file could not be read as text."
            return
        }
        screen.press { await $0.importPack(toml) }
    }
}

/// Rule packs from the community index, beside import and export; installing proposes each rule, signed on its own.
private struct IndexPacks: View {
    @ObservedObject var screen: IndexScreen

    var body: some View {
        let packs = screen.index.packs ?? []
        Group {
            if !packs.isEmpty {
                ShellSection(title: "Rule packs from the community index") {
                    NoteBanner(text: screen.note)
                    ShellPanel {
                        ForEach(Array(packs.enumerated()), id: \.element.id) { index, pack in
                            if index > 0 { ShellDivider() }
                            ShellRow(title: pack.name,
                                     caption: "\(pack.description) · \(IndexLines.publisher(pack.publisher)) · \(IndexLines.latest(pack))") {
                                EmptyView()
                            } trailing: {
                                if IndexLines.canInstall(pack) {
                                    Button("Install", systemImage: "arrow.down.circle") { screen.install(pack.name, version: pack.latest?.version) }
                                        .buttonStyle(KitButton(kind: .secondary))
                                        .disabled(screen.index.busy == pack.name)
                                } else {
                                    StatusWord(.bad, "Marked unsafe")
                                }
                            }
                        }
                    }
                    QuietLine(IndexLines.installWaits(kind: IndexKind.rulePack.rawValue, keyTitle: "Touch ID"))
                }
            }
        }
        .task { await screen.index.readPacks() }
    }
}

/// What could run without asking, how close the rest is, and what the autopilot already answers.
private struct LetGo: View {
    @ObservedObject var screen: StudioScreen
    let home: HomeModel?
    let progress: AutonomyProgress

    var body: some View {
        ShellSection(title: "Let go") {
            VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
                Text(progress.ladder.says)
                    .font(Memnox.Console.sans(Memnox.TextSize.body, .semibold))
                    .foregroundStyle(Memnox.Console.foreground)
                if let needs = progress.ladder.needs { QuietLine(needs) }
                QuietLine(StudioLines.thisWeek(progress))
                ladder.padding(.top, Memnox.Spacing.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Memnox.Spacing.xLarge)
            .padding(.vertical, Memnox.Spacing.large)
            .background(Memnox.Console.card, in: RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
                .strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
            if !progress.ready.isEmpty || !progress.almost.isEmpty || !progress.grants.isEmpty {
                ShellPanel {
                    ForEach(Array(progress.ready.enumerated()), id: \.offset) { index, ready in
                        if index > 0 { ShellDivider() }
                        if let home {
                            ReadyRow(home: home, ready: ready)
                        } else {
                            ShellRow(title: "\(ready.action), said yes \(ready.approvals) times", caption: ready.because) {
                                EmptyView()
                            } trailing: {
                                EmptyView()
                            }
                        }
                    }
                    ForEach(Array(progress.almost.enumerated()), id: \.offset) { index, almost in
                        if index > 0 || !progress.ready.isEmpty { ShellDivider() }
                        ShellRow(title: StudioLines.almostLine(almost), caption: "It needs the same yes a few more times, with no refusal.") {
                            EmptyView()
                        } trailing: {
                            EmptyView()
                        }
                    }
                    ForEach(Array(progress.grants.enumerated()), id: \.element.id) { index, grant in
                        if index > 0 || !progress.ready.isEmpty || !progress.almost.isEmpty { ShellDivider() }
                        ShellRow(title: grant.says, caption: "The autopilot answers this until \(StudioNotes.day(grant.until))") {
                            EmptyView()
                        } trailing: {
                            Button("Take it back") { screen.press { await $0.revoke(grant.id) } }
                                .buttonStyle(KitButton(kind: .secondary))
                                .disabled(screen.studio.busy == grant.id)
                        }
                    }
                }
                if let home { HandOverNote(home: home) }
            }
        }
    }

    /// Every rung, the one the machine stands on drawn strongest.
    private var ladder: some View {
        HStack(spacing: Memnox.Spacing.small) {
            ForEach(progress.ladder.rungs, id: \.self) { rung in
                let here = rung == progress.ladder.level
                Text(rung)
                    .font(Memnox.Console.sans(Memnox.TextSize.micro, here ? .semibold : .regular))
                    .foregroundStyle(here ? Memnox.Console.foreground : Memnox.Console.muted)
                    .padding(.horizontal, Memnox.Spacing.regular)
                    .padding(.vertical, Memnox.Spacing.xxSmall)
                    .overlay(Capsule().strokeBorder(here ? Memnox.Console.primary : Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
                    .accessibilityAddTraits(here ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Autonomy ladder")
    }
}

/// A ready action, handed over through the home's own press so it reads the same as on Home.
private struct ReadyRow: View {
    @ObservedObject var home: HomeModel
    let ready: ProgressReady

    var body: some View {
        ShellRow(title: "\(ready.action), said yes \(ready.approvals) times", caption: ready.because) {
            EmptyView()
        } trailing: {
            Button(home.handingOver ? "Proposing" : "Let it run on its own") { home.handOver(ready.homeReady) }
                .buttonStyle(KitButton(kind: .primary))
                .disabled(home.handingOver)
                .help("Proposes an allow rule for exactly these; nothing changes until you confirm it with Touch ID")
        }
    }
}

private struct HandOverNote: View {
    @ObservedObject var home: HomeModel

    var body: some View {
        if let note = home.handOverNote { QuietLine(note) }
    }
}

/// One rule whole: its sentence, its effect, its fields, where it came from, and Remove where it is this Mac's own.
private struct RuleDetail: View {
    @ObservedObject var shell: AppShellModel
    @ObservedObject var screen: StudioScreen
    let rule: PolicyRuleView

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.xxLarge) {
            VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
                Text(rule.sentence)
                    .font(Memnox.Console.sans(Memnox.TextSize.headline, .semibold))
                    .foregroundStyle(Memnox.Console.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                StatusWord(Tone(effect: rule.effect), StudioLines.says(rule.effect))
                if let reason = rule.reason {
                    Text(reason)
                        .font(Memnox.Console.sans(Memnox.TextSize.body))
                        .foregroundStyle(Memnox.Console.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            FactList(facts: facts)
            if rule.editable {
                VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
                    ShellDivider()
                    Button(rule.ruleEffect == .allow ? "Remove" : "Propose removing it", action: remove)
                        .buttonStyle(KitButton(kind: .secondary))
                        .disabled(screen.studio.busy == rule.name)
                    if rule.ruleEffect != .allow {
                        QuietLine("Removing a rule that asks or refuses lets agents do more, so it waits for your signature.")
                    }
                }
            } else {
                QuietLine("This rule is not one set on this computer, so it is changed where it came from.")
            }
        }
    }

    private var facts: [(String, String)] {
        let match = rule.match
        let fields: [(String, [String]?)] = [
            ("Actions", match.actions), ("Targets", match.targets), ("Agents", match.agents),
            ("Folders", match.workingDirectories), ("Branches", match.branches), ("Kinds", match.classes),
        ]
        var facts = fields.compactMap { name, values -> (String, String)? in
            guard let values, !values.isEmpty else { return nil }
            return (name, values.joined(separator: ", "))
        }
        facts.append(("From", StudioLines.sourceWords(rule)))
        if let until = rule.until { facts.append(("Until", StudioNotes.moment(until))) }
        return facts
    }

    private func remove() {
        let name = rule.name
        Task {
            let outcome = await screen.studio.remove(name)
            screen.said(outcome)
            if case .done = outcome { shell.inspecting = nil }
        }
    }
}

/// What the rules would do with one action, without anything running or being recorded.
private struct TryAction: View {
    @ObservedObject var screen: StudioScreen
    @State private var action = ""
    @State private var target = ""
    @State private var result: RuleTryResult?

    private static let fieldWidth: CGFloat = 140

    var body: some View {
        ShellSection(title: "Try an action") {
            QuietLine("See what your rules would do, without anything running or being recorded.")
            HStack(spacing: Memnox.Spacing.medium) {
                TextField("git.push", text: $action)
                    .kitField()
                    .font(Memnox.Console.code(Memnox.TextSize.body))
                    .frame(minWidth: Self.fieldWidth)
                    .onSubmit(run)
                    .accessibilityLabel("Action to try")
                TextField("On, optional", text: $target)
                    .kitField()
                    .frame(minWidth: Self.fieldWidth)
                    .onSubmit(run)
                    .accessibilityLabel("Target to try")
                Button(action: run) { Label("Try it", systemImage: "flask") }
                    .buttonStyle(KitButton(kind: .secondary))
                    .disabled(trimmed(action).isEmpty)
            }
            switch result {
            case .failed(let why):
                StatusWord(.bad, why)
            case .verdict(let verdict):
                VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
                    StatusWord(Tone(effect: verdict.effect), StudioLines.says(verdict.effect))
                    Text(verdict.reason)
                        .font(Memnox.Console.sans(Memnox.TextSize.body))
                        .foregroundStyle(Memnox.Console.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    if let rule = verdict.rule { QuietLine("Rule: \(rule)") }
                    if let instead = verdict.instead { QuietLine("Instead: \(instead)") }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Memnox.Spacing.xLarge)
                .padding(.vertical, Memnox.Spacing.large)
                .background(Memnox.Console.card, in: RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous))
                .accessibilityElement(children: .combine)
            case nil:
                EmptyView()
            }
        }
    }

    private func run() {
        let action = trimmed(action)
        guard !action.isEmpty else { return }
        let target = trimmed(target)
        let input = RuleTestInput(action: action, target: target.isEmpty ? nil : target)
        Task { result = await screen.studio.test(input) }
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
