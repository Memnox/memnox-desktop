import AppKit
import MemnoxVoiceCore
import SwiftUI
import UniformTypeIdentifiers

/// The Rules page, laid out as the console's: the three effects said once, the rules in force, then the ready-made
/// rules to add. What is already true is read first and changed second, and a rule built here only goes in force
/// once the person signs it on the island with Touch ID.
struct PoliciesDestination: View {
    @ObservedObject var shell: AppShellModel
    @ObservedObject var screen: StudioScreen
    @ObservedObject var island: IslandModel
    let home: HomeModel?
    let width: WidthClass

    @State private var filter: RuleEffect?
    @State private var building = false
    @State private var adding: RuleAdding?

    var body: some View {
        page
            .task { await screen.studio.refresh() }
            // A signed or declined proposal leaves the island, and the rules are read again so they show what holds.
            .onChange(of: island.waiting.count) { Task { await screen.studio.refresh() } }
            .consoleSheet(isPresented: $building) {
                RuleBuilderSheet(screen: screen, agents: shell.hub?.hub.hub?.agents.map(\.agent) ?? []) { building = false }
            }
            .consoleSheet(item: $adding) { each in
                RuleAddSheet(screen: screen, adding: each) { adding = nil }
            }
    }

    @ViewBuilder private var page: some View {
        let studio = screen.studio
        if let view = studio.rules {
            let picked = view.rules.first { $0.name == shell.inspecting }
            // Nothing in force means the ready-made rules are where to start, so they lead.
            let libraryFirst = view.rules.isEmpty
            InspectorLayout(width: width, title: picked?.name, close: { shell.inspecting = nil }) {
                ShellScroll(width: width) {
                    NoteBanner(text: screen.note)
                    EffectCards(counts: StudioLines.countsByEffect(scoped(view)), filter: $filter, stacked: width.stacksCards)
                    if libraryFirst { library(view) }
                    rulesInForce(view)
                    if !libraryFirst { library(view) }
                    if let progress = studio.progress { LetGo(screen: screen, home: home, progress: progress) }
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

    private func library(_ view: PolicyRulesView) -> some View {
        RulesLibrary(shell: shell, screen: screen, rules: view.rules, width: width) { adding = $0 }
    }

    /// The scope selector shows the person's rules or the organization's, never the two mixed.
    private func scoped(_ view: PolicyRulesView) -> [PolicyRuleView] {
        ShellLines.inScope(view.rules, shell.scope) { ScopeLines.rule($0) == .organization }
    }

    private func rulesInForce(_ view: PolicyRulesView) -> some View {
        let scoped = self.scoped(view)
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
                Button { building = true } label: { Label("Propose a rule", systemImage: RuleSymbols.add) }
                    .buttonStyle(KitButton(kind: .primary))
            }
        } content: {
            HStack(spacing: Memnox.Spacing.small) {
                FilterChip(title: "All", chosen: filter == nil, count: scoped.count) { filter = nil }
                ForEach(RuleEffect.allCases, id: \.self) { effect in
                    FilterChip(title: StudioLines.words(effect).title, chosen: filter == effect, count: counts[effect] ?? 0) { filter = effect }
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
                .overlay(RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
                    .strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
                .accessibilityElement(children: .combine)
            }
            if shell.scope == .organization {
                QuietLine(scoped.isEmpty ? ShellLines.noOrganizationItems : ShellLines.organizationReadOnly)
            }
            if shown.isEmpty {
                EmptyState(symbol: "checkmark.shield", title: "No rule here yet",
                           detail: "Propose one with Propose a rule, or add a ready-made rule.")
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

/// One rule whole, as the console's rule panel: its effect as a band, its actions as the title, then a plain sentence,
/// why it exists, the rule as code, its other fields, and Remove where it is this Mac's own.
private struct RuleDetail: View {
    @ObservedObject var shell: AppShellModel
    @ObservedObject var screen: StudioScreen
    let rule: PolicyRuleView

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
                if let effect = rule.ruleEffect { EffectBand(effect: effect) }
                Text(RuleDetailLines.title(rule.match.actions))
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.large, .semibold))
                    .foregroundStyle(Memnox.Console.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.bottom, Memnox.Spacing.xLarge)
            ShellDivider()
            VStack(alignment: .leading, spacing: Memnox.Spacing.xxLarge) {
                Text(sentence)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.base))
                    .foregroundStyle(Memnox.Console.foreground)
                    .lineSpacing(Memnox.Spacing.xSmall)
                    .fixedSize(horizontal: false, vertical: true)
                if let reason = rule.reason { fact("Why", reason) }
                CodeBlock(code: RuleToml.text(RuleToml.table(of: rule)), label: RuleToml.file)
                FactList(facts: facts)
                if rule.editable {
                    VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
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
            .padding(.top, Memnox.Spacing.xLarge)
        }
    }

    /// The rule as one sentence, or the runtime's own where its effect is not one of the three.
    private var sentence: String {
        guard let effect = rule.ruleEffect else { return rule.sentence }
        return RuleDetailLines.sentence(agents: rule.match.agents, actions: rule.match.actions, targets: rule.match.targets,
                                        effect: effect, agentName: McpHubLines.agentLabel)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
            Text(label)
                .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                .foregroundStyle(Memnox.Console.muted)
            Text(value)
                .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
                .foregroundStyle(Memnox.Console.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }

    /// What the code does not already say plainly: where the rule came from, its name, and when it ends.
    private var facts: [(String, String)] {
        var facts = [("Name", rule.name), ("From", StudioLines.sourceWords(rule))]
        if let file = rule.file { facts.append(("File", file)) }
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

/// An effect as the panel's full width band: its symbol and word in the effect's colour on its own tint.
private struct EffectBand: View {
    let effect: RuleEffect

    private enum Layout {
        static let height: CGFloat = 30
        static let icon: CGFloat = 12
    }

    var body: some View {
        let tone = Tone(effect: effect.rawValue)
        HStack(spacing: Memnox.Spacing.small) {
            Image(systemName: RuleSymbols.effect(effect))
                .font(.system(size: Layout.icon, weight: .semibold))
            Text(StudioLines.words(effect).title)
                .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
        }
        .foregroundStyle(tone.color)
        .padding(.horizontal, Memnox.Spacing.medium)
        .frame(maxWidth: .infinity, minHeight: Layout.height, alignment: .leading)
        .background(tone.pill, in: RoundedRectangle(cornerRadius: Memnox.Console.controlRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// The three effects said once at the top of the page, each with how many rules in force use it, and each a filter
/// over the rules below: pressing one shows only its rules, pressing it again shows them all.
private struct EffectCards: View {
    let counts: [RuleEffect: Int]
    @Binding var filter: RuleEffect?
    /// One under another where the window is too narrow for three across.
    let stacked: Bool

    var body: some View {
        let layout = stacked ? AnyLayout(VStackLayout(spacing: Memnox.Spacing.medium))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Memnox.Spacing.medium))
        layout {
            ForEach(RuleEffect.allCases, id: \.self) { effect in
                EffectCard(effect: effect, count: counts[effect] ?? 0, chosen: filter == effect) {
                    filter = filter == effect ? nil : effect
                }
            }
        }
        // Every card as tall as the tallest, so the three read as one row however their lines wrap.
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Show rules that")
    }
}

private struct EffectCard: View {
    let effect: RuleEffect
    let count: Int
    let chosen: Bool
    let choose: () -> Void
    @State private var hovering = false

    private enum Layout {
        static let tile: CGFloat = 32
        static let icon: CGFloat = 14
        static let countSize: CGFloat = 26
        /// The chosen card's wash, the console's blue at 5 percent under its outline.
        static let chosenWash = 0.05
    }

    var body: some View {
        let words = StudioLines.words(effect)
        let tone = Tone(effect: effect.rawValue)
        let shape = RoundedRectangle(cornerRadius: Memnox.Console.cardRadius, style: .continuous)
        Button(action: choose) {
            VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
                HStack(alignment: .center, spacing: Memnox.Spacing.medium) {
                    Image(systemName: RuleSymbols.effect(effect))
                        .font(.system(size: Layout.icon, weight: .semibold))
                        .foregroundStyle(tone.color)
                        .frame(width: Layout.tile, height: Layout.tile)
                        .background(tone.pill, in: RoundedRectangle(cornerRadius: Memnox.Console.controlRadius, style: .continuous))
                    Text(words.title)
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
                        .foregroundStyle(Memnox.Console.foreground)
                    Spacer(minLength: Memnox.Spacing.medium)
                    Text("\(count)")
                        .font(Memnox.Console.sans(Layout.countSize, .semibold).monospacedDigit())
                        .foregroundStyle(count == 0 ? Memnox.Console.faint : Memnox.Console.foreground)
                }
                VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                    Text(words.says)
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                        .foregroundStyle(Memnox.Console.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(count == 1 ? "1 rule in force" : "\(count) rules in force")
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                        .foregroundStyle(Memnox.Console.faint)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Memnox.Spacing.xLarge)
            .background(chosen ? Memnox.Console.primary.opacity(Layout.chosenWash) : hovering ? Memnox.Console.hover : Memnox.Console.card,
                        in: shape)
            .overlay(shape.strokeBorder(chosen ? Memnox.Console.primary : Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
            .contentShape(shape)
            .animation(.easeOut(duration: Memnox.Motion.quick), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointingHand()
        .help(chosen ? "Show every rule" : "Show only the rules that \(words.title.lowercased())")
        .accessibilityLabel("\(words.title), \(count) rules. \(words.says)")
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }
}

private extension WidthClass {
    /// Three cards fit side by side only on a wide or medium window.
    var stacksCards: Bool {
        switch self {
        case .wide, .medium: false
        case .narrow, .compact: true
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
                .overlay(RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
                    .strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
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
