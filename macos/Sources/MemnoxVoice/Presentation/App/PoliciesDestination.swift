import AppKit
import MemnoxVoiceCore
import SwiftUI
import UniformTypeIdentifiers

/// Protection settings, laid out as the console's: Ready-made rules, All rules and Autonomy as tabs with counts, the
/// pages its one sidebar row lights. Ready-made rules is the library's categories, search and cards, whose picks gather
/// in one bar at the foot as the console's choices do; All rules says the three effects once over the rules that hold;
/// Autonomy offers what could stop being asked. Nothing built here holds until the person signs it on the island.
struct PoliciesDestination: View {
    @ObservedObject var shell: AppShellModel
    @ObservedObject var screen: StudioScreen
    @ObservedObject var island: IslandModel
    let home: HomeModel?
    let width: WidthClass

    /// The effect tab over the rules in force, nil while All is.
    @State private var filter: RuleEffect?
    @State private var building = false
    @State private var adding: RuleAdding?
    /// The console's sidebar row lands on the choices first, so this page opens on the ready-made rules.
    @State private var tab = ProtectionTab.readyMade
    /// The effect picked on each ready-made card, by rule name, gathered in the bar until reviewed and saved.
    @State private var picked: [String: RuleEffect] = [:]

    var body: some View {
        page
            .task { await screen.studio.refresh() }
            // A signed or declined proposal leaves the island, and the rules are read again so they show what holds.
            .onChange(of: island.waiting.count) { Task { await screen.studio.refresh() } }
            .consoleSheet(isPresented: $building) {
                RuleBuilderSheet(screen: screen, agents: shell.hub?.hub.hub?.agents.map(\.agent) ?? []) { building = false }
            }
            .consoleSheet(item: $adding) { each in
                RuleAddSheet(screen: screen, adding: each, close: { adding = nil }, saved: { picked = [:] })
            }
    }

    @ViewBuilder private var page: some View {
        let studio = screen.studio
        if let view = studio.rules {
            let inspected = view.rules.first { $0.name == shell.inspecting }
            let ready = ReadyRuleChanges.flat(ReadyRules.groups(studio.packs ?? []))
            let changes = ReadyRuleChanges.changes(picked, rules: ready, among: view.rules)
            InspectorLayout(width: width, title: inspected?.name, close: { shell.inspecting = nil }) {
                ShellScroll(width: width) {
                    CountTabs(tabs: ProtectionTab.shown.map { (id: $0, title: $0.title, count: count($0, view: view, ready: ready)) },
                              chosen: tab) { tab = $0 }
                    NoteBanner(text: screen.note)
                    switch tab {
                    case .readyMade:
                        RulesLibrary(shell: shell, screen: screen, rules: view.rules, width: width, picked: $picked)
                    case .allRules:
                        allRules(view)
                    case .autonomy:
                        HandOver(screen: screen, home: home, progress: studio.progress)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if !changes.isEmpty {
                        ChangesBar(count: ReadyRuleChanges.countLine(changes.count), busy: studio.busy != nil,
                                   undo: { picked = [:] }, review: { adding = RuleAdding(changes: changes) })
                            .padding(.horizontal, Memnox.Spacing.xLarge)
                            .padding(.bottom, Memnox.Spacing.large)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.snappy(duration: Memnox.Motion.quick), value: changes.isEmpty)
            } detail: {
                if let inspected {
                    RuleDetail(shell: shell, screen: screen, rule: inspected,
                               alike: PlainRules.grouped(scoped(view)).first { $0.rules.contains(inspected) }?.rules ?? [inspected])
                }
            }
        } else if studio.unreadable {
            ShellScroll(width: width) { ReadFailed(what: "the rules") { Task { await studio.refresh() } } }
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// What each tab counts: the ready-made rules offered, the rules in force, and what is ready to hand over.
    private func count(_ tab: ProtectionTab, view: PolicyRulesView, ready: [ReadyRule]) -> Int {
        switch tab {
        case .readyMade: ready.count
        case .allRules: scoped(view).count
        case .autonomy: screen.studio.progress?.ready.count ?? 0
        }
    }

    /// The scope selector shows the person's rules or the organization's, never the two mixed.
    private func scoped(_ view: PolicyRulesView) -> [PolicyRuleView] {
        ShellLines.inScope(view.rules, shell.scope) { ScopeLines.rule($0) == .organization }
    }

    /// All rules in the console's order: what it is with its two presses, the way to the simple version, the three
    /// effects, a start from the library while nothing holds, then the rules in force.
    @ViewBuilder private func allRules(_ view: PolicyRulesView) -> some View {
        let scoped = self.scoped(view)
        HStack(alignment: .center, spacing: Memnox.Spacing.medium) {
            QuietLine(ProtectionLines.allIntro)
            Spacer(minLength: Memnox.Spacing.large)
            Button { building = true } label: { Label(ProtectionLines.propose, systemImage: RuleSymbols.add) }
                .buttonStyle(KitButton(kind: .primary))
                .fixedSize()
        }
        PointerCard(title: ProtectionLines.simplerTitle, note: ProtectionLines.simplerNote) { tab = .readyMade }
        EffectLegend(stacked: width.stacksCards)
        if scoped.isEmpty {
            PointerCard(title: ProtectionLines.startTitle, note: ProtectionLines.startNote) { tab = .readyMade }
        }
        rulesInForce(view)
        // The community's rule packs are left off for now, since the marketplace holds no listing yet.
    }

    private func rulesInForce(_ view: PolicyRulesView) -> some View {
        let scoped = self.scoped(view)
        let counts = StudioLines.countsByEffect(scoped)
        let shown = scoped.filter { filter == nil || $0.ruleEffect == filter }
        let tabs: [(id: RuleEffect?, title: String, count: Int)] = [(id: nil, title: ProtectionLines.allTab, count: scoped.count)]
            + RuleEffect.allCases.map { (id: $0, title: StudioLines.words($0).title, count: counts[$0] ?? 0) }
        return ShellSection(title: ProtectionLines.rulesInForce) {
            HStack(spacing: Memnox.Spacing.medium) {
                Button(action: exportRules) { Label("Export", systemImage: "square.and.arrow.down") }
                    .buttonStyle(KitButton(kind: .secondary))
                    .help("Save the rules set on this computer as a TOML file")
                Button(action: importPack) { Label("Import", systemImage: "square.and.arrow.up") }
                    .buttonStyle(KitButton(kind: .secondary))
                    .disabled(screen.studio.busy == Studio.importing)
                    .help("Propose every rule in a TOML file, each signed on its own")
            }
        } content: {
            CountTabs(tabs: tabs, chosen: filter) { filter = $0 }
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
                EmptyState(symbol: "checkmark.shield", title: filter == nil ? ProtectionLines.noRules : ProtectionLines.noRuleHere,
                           detail: filter == nil ? ProtectionLines.noRulesBody : ProtectionLines.noRuleHereBody)
            } else {
                // Rules that read the same and do the same stand as one row with how many say it, the first opening the details.
                ShellPanel {
                    ForEach(Array(PlainRules.grouped(shown).enumerated()), id: \.element.id) { index, group in
                        if index > 0 { ShellDivider() }
                        let first = group.rules[0]  // A group is never empty, since a rule opens it.
                        ShellRow(title: group.plain.title, caption: group.plain.caption ?? StudioLines.sourceWords(first),
                                 chosen: group.rules.contains { $0.name == shell.inspecting },
                                 action: { shell.inspecting = first.name }) {
                            EmptyView()
                        } trailing: {
                            if let count = PlainRules.countLine(group.count) {
                                Text(count)
                                    .font(Memnox.Console.sans(Memnox.Console.TextSize.label, .medium))
                                    .foregroundStyle(Memnox.Console.muted)
                                    .padding(.horizontal, Memnox.Spacing.regular)
                                    .padding(.vertical, Memnox.Spacing.xxSmall)
                                    .background(Memnox.Console.hover, in: Capsule())
                            }
                            ScopeChip(ScopeLines.rule(first))
                            StatusWord(Tone(effect: group.effect), StudioLines.title(group.effect))
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

/// A card that is a press to the tab that answers the question better, as the console's pointer cards link.
private struct PointerCard: View {
    let title: String
    let note: String
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Memnox.Console.cardRadius, style: .continuous)
        Button(action: open) {
            HStack(spacing: Memnox.Spacing.large) {
                VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                    Text(title)
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
                        .foregroundStyle(Memnox.Console.foreground)
                    Text(note)
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                        .foregroundStyle(Memnox.Console.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Memnox.Spacing.medium)
                Image(systemName: "arrow.right")
                    .font(.system(size: Memnox.TextSize.footnote, weight: .medium))
                    .foregroundStyle(Memnox.Console.muted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Memnox.Spacing.xLarge)
            .padding(.vertical, Memnox.Spacing.large)
            .background(Memnox.Console.card, in: shape)
            .overlay(shape.strokeBorder(hovering ? Memnox.Console.muted : Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointingHand()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
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

/// Autonomy as the console's hand over page: what could run without asking, how close the rest is, and what the
/// autopilot already answers, each proposed and signed rather than changed here.
private struct HandOver: View {
    @ObservedObject var screen: StudioScreen
    let home: HomeModel?
    let progress: AutonomyProgress?

    var body: some View {
        QuietLine(ProtectionLines.autonomyIntro)
        if let progress {
            VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
                Text(progress.ladder.says)
                    .font(Memnox.Console.sans(Memnox.TextSize.body, .semibold))
                    .foregroundStyle(Memnox.Console.foreground)
                if let needs = progress.ladder.needs { QuietLine(needs) }
                QuietLine(StudioLines.thisWeek(progress))
                ladder(progress).padding(.top, Memnox.Spacing.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Memnox.Spacing.xLarge)
            .padding(.vertical, Memnox.Spacing.large)
            .background(Memnox.Console.card, in: RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
                .strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
        }
        ShellSection(title: ProtectionLines.readyToHandOver) {
            if let progress, !progress.ready.isEmpty || !progress.almost.isEmpty || !progress.grants.isEmpty {
                rows(progress)
                if let home { HandOverNote(home: home) }
            } else {
                EmptyState(symbol: "arrow.triangle.branch", title: ProtectionLines.nothingReady, detail: ProtectionLines.nothingReadyBody)
            }
        }
    }

    private func rows(_ progress: AutonomyProgress) -> some View {
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
                ShellRow(title: StudioLines.almostLine(almost), caption: ProtectionLines.almostCaption) {
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
                    Button(ProtectionLines.takeBack) { screen.press { await $0.revoke(grant.id) } }
                        .buttonStyle(KitButton(kind: .secondary))
                        .disabled(screen.studio.busy == grant.id)
                }
            }
        }
    }

    /// Every rung, the one the machine stands on drawn strongest.
    private func ladder(_ progress: AutonomyProgress) -> some View {
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
            Button(home.handingOver ? ProtectionLines.proposing : ProtectionLines.stopAsking) { home.handOver(ready.homeReady) }
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

/// One rule whole, as the console's rule panel: its effect as a band, its plain title, why it exists, the rules that say
/// the same, the rule as written behind a disclosure, its other fields, and Remove where it is this Mac's own.
private struct RuleDetail: View {
    @ObservedObject var shell: AppShellModel
    @ObservedObject var screen: StudioScreen
    let rule: PolicyRuleView
    /// Every rule in force that reads and does the same as this one, itself included.
    let alike: [PolicyRuleView]
    @State private var written = false

    var body: some View {
        let plain = PlainRules.plain(rule)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
                if let effect = rule.ruleEffect { EffectBand(effect: effect) }
                Text(plain.title)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.large, .semibold))
                    .foregroundStyle(Memnox.Console.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.bottom, Memnox.Spacing.xLarge)
            ShellDivider()
            VStack(alignment: .leading, spacing: Memnox.Spacing.xxLarge) {
                if let why = plain.caption { fact("Why", why) }
                if alike.count > 1 {
                    VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
                        Text(PlainRules.countLine(alike.count) ?? "")
                            .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                            .foregroundStyle(Memnox.Console.muted)
                        ForEach(alike, id: \.name) { each in
                            Button(each.name) { shell.inspecting = each.name }
                                .buttonStyle(.plain)
                                .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, each.name == rule.name ? .medium : .regular))
                                .foregroundStyle(each.name == rule.name ? Memnox.Console.foreground : Memnox.Console.primary)
                                .pointingHand()
                                .accessibilityAddTraits(each.name == rule.name ? .isSelected : [])
                        }
                    }
                }
                DisclosureGroup(isExpanded: $written) {
                    VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
                        // The sentence names the patterns themselves, so it stands with them rather than above.
                        Text(sentence)
                            .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
                            .foregroundStyle(Memnox.Console.foreground)
                            .lineSpacing(Memnox.Spacing.xSmall)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        FactList(facts: PlainRules.written(rule.match).map { ($0.label, $0.value) }, agents: ["Agents": rule.match.agents ?? []])
                        CodeBlock(code: RuleToml.text(RuleToml.table(of: rule)), label: RuleToml.file)
                    }
                    .padding(.top, Memnox.Spacing.medium)
                } label: {
                    Text(PlainRules.asWritten)
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
                        .foregroundStyle(Memnox.Console.foreground)
                }
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

/// The three effects said once over the rules, so every word below is already explained, as the console's legend.
private struct EffectLegend: View {
    /// One under another where the window is too narrow for three across.
    let stacked: Bool

    private enum Layout {
        static let icon: CGFloat = 14
    }

    var body: some View {
        let layout = stacked ? AnyLayout(VStackLayout(spacing: Memnox.Spacing.small))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Memnox.Spacing.small))
        layout {
            ForEach(RuleEffect.allCases, id: \.self) { effect in
                let words = StudioLines.words(effect)
                HStack(alignment: .firstTextBaseline, spacing: Memnox.Spacing.medium) {
                    Image(systemName: RuleSymbols.effect(effect))
                        .font(.system(size: Layout.icon, weight: .medium))
                        .foregroundStyle(Memnox.Console.muted)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                        Text(words.title)
                            .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
                            .foregroundStyle(Memnox.Console.foreground)
                        Text(words.says)
                            .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                            .foregroundStyle(Memnox.Console.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, Memnox.Spacing.xLarge)
                .padding(.vertical, Memnox.Spacing.large)
                .background(Memnox.Console.card, in: RoundedRectangle(cornerRadius: Memnox.Console.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Memnox.Console.cardRadius, style: .continuous)
                    .strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
                .accessibilityElement(children: .combine)
            }
        }
        // Every card as tall as the tallest, so the three read as one row however their lines wrap.
        .fixedSize(horizontal: false, vertical: true)
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

