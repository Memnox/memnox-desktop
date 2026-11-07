import MemnoxVoiceCore
import SwiftUI

/// The Skills Hub for the views: redrawn whenever the core's hub changes, with the line the last press ended in.
@MainActor
final class SkillsScreen: ObservableObject {
    let skills: SkillsHub
    /// Bumped when the hub changes, so every view reading it is drawn again.
    @Published private(set) var tick = 0
    /// What the last press came to, shown above the page until the next one.
    @Published var note: String?
    /// Each skill's use and its fixes, nil until the app wires it, which leaves a skill's page without that section.
    @Published var care: SkillCareScreen?

    init(skills: SkillsHub) {
        self.skills = skills
        skills.changed = { [weak self] in
            Task { @MainActor [weak self] in self?.tick += 1 }
        }
    }

    func said(_ outcome: SkillOutcome) {
        switch outcome {
        case .proposed: note = "Waiting for you on the island: confirm it with Touch ID and the runtime writes it."
        case .failed(let why): note = why
        case .done(let line): note = line
        }
    }

    /// Runs one press and says how it ended.
    func press(_ work: @escaping (SkillsHub) async -> SkillOutcome) {
        Task { said(await work(skills)) }
    }

    /// How far an Import all has come, nil while none runs.
    @Published private(set) var importing: ImportProgress?

    /// Imports every skill given, one request each, and says in one line what it came to.
    func importAll(_ found: [FoundSkillView]) {
        guard importing == nil, !found.isEmpty else { return }
        importing = ImportProgress(done: 0, total: found.count)
        Task {
            let results = await skills.importAll(found) { [weak self] done in await self?.advance(done) }
            importing = nil
            note = SkillSearch.imported(results)
        }
    }

    private func advance(_ done: Int) {
        if let total = importing?.total { importing = ImportProgress(done: done, total: total) }
    }
}

/// How many of an Import all have answered, of how many.
struct ImportProgress: Equatable {
    let done: Int
    let total: Int
}

/// The Skills Hub: skills kept once and written into each agent's own format. Giving a skill to an agent and accepting
/// a folder that reaches further wait for a signature on the island; taking away is at once.
struct SkillsDestination: View {
    @ObservedObject var screen: SkillsScreen
    @ObservedObject var island: IslandModel
    let tab: String?
    /// The project the top bar's switcher picked, nil for every project.
    var current: ProjectView?
    /// Whose skills show: both, the person's, or the organization's once Memnox Cloud hands any down.
    var scope: ShownScope = .all
    let width: WidthClass
    /// The skill whose Assign sheet is open, by name.
    @State private var assigning: String?

    var body: some View {
        page
            .task(id: tab) { await screen.skills.refresh() }
            // A signature on the island changes what the hub holds, so it is read again.
            .onChange(of: island.waiting.count) { Task { await screen.skills.refresh() } }
    }

    @ViewBuilder private var page: some View {
        let skills = screen.skills
        if let view = skills.hub {
            Group {
                if tab == "assigned" {
                    ShellScroll(width: width) {
                        NoteBanner(text: screen.note)
                        AssignedGrid(view: view) { assigning = $0 }
                    }
                } else {
                    MySkills(screen: screen, view: view, current: current, scope: scope, width: width) { assigning = $0 }
                }
            }
            .consoleSheet(isPresented: Binding(get: { assigning != nil }, set: { if !$0 { assigning = nil } })) {
                if let skill = view.skills.first(where: { $0.name == assigning }) {
                    AssignSkillSheet(screen: screen, view: view, skill: skill) { assigning = nil }
                }
            }
        } else if skills.unreadable {
            ShellScroll(width: width) { ReadFailed(what: "the Skills Hub") { Task { await skills.refresh() } } }
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private enum SkillsLayout {
    static let cardWidth: CGFloat = 260
    static let searchWidth: CGFloat = 320
    static let logo: CGFloat = 22
    static let smallLogo: CGFloat = 20
    static let column: CGFloat = 96
    /// The wide column takes this much more than the narrow one, as the console sets a skill's page.
    static let leftShare: CGFloat = 1.4
    static let instructionsPadding: CGFloat = 20
}

/// Every skill as a card, with search, Sync and New skill above, and what agents already had below. One search narrows
/// both, and each says how many of how many it shows.
private struct MySkills: View {
    @ObservedObject var screen: SkillsScreen
    let view: SkillsHubView
    let current: ProjectView?
    let scope: ShownScope
    let width: WidthClass
    let manage: (String) -> Void
    @State private var query = ""
    @State private var opened: String?
    @State private var creating = false
    @State private var previewing: FoundSkillView?

    var body: some View {
        Group {
            if let picked = view.skills.first(where: { $0.name == opened }) {
                ShellScroll(width: width) {
                    NoteBanner(text: screen.note)
                    SkillDetail(screen: screen, view: view, skill: picked, width: width, back: { opened = nil }) { manage(picked.name) }
                }
            } else {
                list
            }
        }
        .consoleSheet(isPresented: $creating) {
            NewSkillSheet(screen: screen) { creating = false }
        }
        .consoleSheet(item: $previewing) { found in
            FoundSkillSheet(screen: screen, found: found, label: labelOf(view, found.agent)) { previewing = nil }
        }
    }

    private var list: some View {
        let label: (String) -> String = { labelOf(view, $0) }
        let searching = SkillSearch.words(query) != nil
        let scoped = inScope
        let hub = SkillSearch.hub(scoped, query, label: label)
        let found = SkillSearch.found(view.found, query, label: label)
        let foundTotal = view.found.filter { !$0.imported }.count
        return ShellScroll(width: width) {
            NoteBanner(text: screen.note)
            toolbar
            if scope == .organization {
                QuietLine(scoped.isEmpty ? ShellLines.noOrganizationItems : ShellLines.organizationReadOnly)
            }
            if searching {
                QuietLine("\(SkillSearch.counted(shown: hub.count, of: scoped.count, searching: true)) in the hub, \(SkillSearch.counted(shown: found.count, of: foundTotal, searching: true)) found on this computer")
            }
            if hub.isEmpty, searching {
                EmptyState(symbol: "magnifyingglass", title: SkillSearch.noMatch(query),
                           detail: SkillSearch.noMatchDetail(foundMatching: found.count))
            } else if view.skills.isEmpty {
                EmptyState(symbol: "sparkles", title: "No skills in the hub yet",
                           detail: "Write one with New skill and give it to any agent, or import one an agent already has from Found on this computer below.")
            } else if !hub.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: SkillsLayout.cardWidth), spacing: Memnox.Spacing.large)],
                          spacing: Memnox.Spacing.large) {
                    ForEach(hub) { skill in
                        SkillCard(screen: screen, skill: skill, view: { opened = skill.name }) { manage(skill.name) }
                    }
                }
            }
            SkillsFound(screen: screen, view: view, found: found, total: foundTotal, searching: searching) { previewing = $0 }
        }
    }

    /// The switcher's project and the scope selector narrow the hub before the search does.
    private var inScope: [SkillView] {
        let inProject = ShellLines.skillsShown(view.skills, current: current)
        return ShellLines.inScope(inProject, scope) { ScopeLines.skill($0) == .organization }
    }

    private var toolbar: some View {
        HStack(spacing: Memnox.Spacing.regular) {
            SearchField(prompt: "Search skills and what agents have", text: $query).frame(maxWidth: SkillsLayout.searchWidth)
            Spacer(minLength: Memnox.Spacing.medium)
            Button { screen.press { await $0.sync() } } label: { Label("Sync", systemImage: "arrow.clockwise") }
                .buttonStyle(KitButton(kind: .secondary))
                .disabled(screen.skills.busy == SkillsHub.syncing)
                .help("Write what the hub gives each agent into its folder again")
            Button { creating = true } label: { Label("New skill", systemImage: "plus") }
                .buttonStyle(KitButton(kind: .primary))
        }
    }
}

private struct SkillCard: View {
    @ObservedObject var screen: SkillsScreen
    let skill: SkillView
    let view: () -> Void
    let manage: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
        let busy = screen.skills.busy == skill.name
        VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
            HStack(alignment: .top, spacing: Memnox.Spacing.medium) {
                VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                    Text(skill.name)
                        .font(Memnox.Console.sans(Memnox.TextSize.headline, .semibold))
                        .foregroundStyle(Memnox.Console.foreground)
                        .lineLimit(1)
                    Text(SkillsLines.categoryVersion(skill))
                        .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                        .foregroundStyle(Memnox.Console.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: Memnox.Spacing.medium)
                Toggle("", isOn: Binding(get: { skill.enabled }, set: { on in
                    let name = skill.name
                    screen.press { on ? await $0.enable(name) : await $0.disable(name) }
                }))
                .toggleStyle(MemnoxSwitch())
                .labelsHidden()
                .disabled(busy)
                .accessibilityLabel(skill.enabled ? "Turn \(skill.name) off for every agent" : "Hand \(skill.name) back to its agents")
            }
            Text(skill.description)
                .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                .foregroundStyle(Memnox.Console.foreground)
                .lineLimit(1)
            HStack(spacing: Memnox.Spacing.large) {
                ScopeChip(ScopeLines.skill(skill))
                if skill.held != nil { StatusWord(.attention, "Held") }
                if !skill.enabled { StatusWord(.quiet, "Off") }
                Text(SkillsLines.assigned(skill.agents.count))
                Text(SkillsLines.updated(skill.updatedAt, now: Date()))
            }
            .font(Memnox.Console.sans(Memnox.TextSize.footnote))
            .foregroundStyle(Memnox.Console.muted)
            .lineLimit(1)
            ShellDivider()
            HStack(spacing: Memnox.Spacing.medium) {
                Button("View skill", action: view).buttonStyle(KitButton(kind: .secondary))
                Button("Manage agents", action: manage).buttonStyle(KitButton(kind: .secondary))
            }
        }
        .padding(Memnox.Spacing.xLarge)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Memnox.Console.card, in: shape)
        .overlay(shape.strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(skill.name)
    }
}

/// One skill on the whole page: what it is on the left, where it goes and what it reaches on the right, folding to
/// one column under 900 points.
private struct SkillDetail: View {
    @ObservedObject var screen: SkillsScreen
    let view: SkillsHubView
    let skill: SkillView
    let width: WidthClass
    let back: () -> Void
    let manage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ShellMetrics.sectionSpacing) {
            HStack(spacing: Memnox.Spacing.regular) {
                Button("All skills", systemImage: "arrow.left", action: back).buttonStyle(KitButton(kind: .secondary))
                Text(skill.name)
                    .font(Memnox.Console.sans(Memnox.TextSize.headline, .semibold))
                    .foregroundStyle(Memnox.Console.foreground)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Memnox.Spacing.medium)
                Text(SkillsLines.categoryVersion(skill))
                    .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Console.muted)
            }
            if width == .wide || width == .medium {
                SharedColumns(leftShare: SkillsLayout.leftShare, gap: ShellMetrics.sectionSpacing) {
                    what
                    reach
                }
            } else {
                VStack(alignment: .leading, spacing: ShellMetrics.sectionSpacing) {
                    what
                    reach
                }
            }
        }
    }

    /// The description, the instructions, the facts, its files and its versions.
    private var what: some View {
        VStack(alignment: .leading, spacing: ShellMetrics.sectionSpacing) {
            Text(skill.description)
                .font(Memnox.Console.sans(Memnox.TextSize.body))
                .foregroundStyle(Memnox.Console.foreground)
                .fixedSize(horizontal: false, vertical: true)
            ShellSection(title: "Instructions") {
                SkillMarkdown(blocks: SkillMarkdownReader.parse(skill.instructions))
                .padding(SkillsLayout.instructionsPadding)
                .background(Memnox.Console.card, in: RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
                    .strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
            }
            if let care = screen.care { SkillCareSection(care: care, screen: screen, skill: skill) }
            FactList(facts: [
                ("Version", skill.version),
                ("Publisher", skill.publisher ?? "You"),
                ("Kept", skill.skillScope == .project ? "With \(skill.project ?? "its repository")" : "In your Memnox folder"),
            ])
            if !skill.files.isEmpty { listed("Files", skill.files, mono: true) }
            if !skill.dependencies.isEmpty { listed("Builds on", skill.dependencies) }
            ShellSection(title: "Versions") {
                ShellPanel {
                    ForEach(Array(skill.versions.reversed().enumerated()), id: \.element.version) { index, version in
                        if index > 0 { ShellDivider() }
                        ShellRow(title: "v\(version.version)",
                                 caption: version.acceptedAt.map { "Accepted \(StudioNotes.day($0))" } ?? "Never accepted") {
                            EmptyView()
                        } trailing: {
                            if version.current {
                                StatusWord(.good, "In use")
                            } else if skill.skillScope == .personal, version.acceptedAt != nil {
                                Button("Roll back") {
                                    let name = skill.name
                                    screen.press { await $0.rollback(name, to: version.version) }
                                }
                                .buttonStyle(KitButton(kind: .secondary))
                                .disabled(screen.skills.busy == skill.name)
                            }
                        }
                    }
                }
                QuietLine("Rolling back to a version that reaches further waits for your signature with Touch ID.")
            }
        }
    }

    /// Why it is held, who has it, where it is available, what it reaches and what each agent keeps of it.
    private var reach: some View {
        let permissions = SkillsLines.permissions(skill)
        return VStack(alignment: .leading, spacing: ShellMetrics.sectionSpacing) {
            if let hold = skill.held {
                VStack(alignment: .leading, spacing: Memnox.Spacing.regular) {
                    StatusWord(.attention, "Held")
                    Text(SkillsLines.held(hold))
                        .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                        .foregroundStyle(Memnox.Console.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Accept", systemImage: "checkmark") {
                        let name = skill.name
                        screen.press { await $0.accept(name) }
                    }
                    .buttonStyle(KitButton(kind: .primary))
                    .disabled(screen.skills.busy == skill.name)
                }
                .padding(ShellMetrics.rowPaddingH)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Memnox.Console.card, in: RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
                    .strokeBorder(Memnox.Console.warm.opacity(0.4), lineWidth: Memnox.Stroke.hairline))
                .accessibilityElement(children: .contain)
            }
            if let problems = skill.problems, !problems.isEmpty { listed("Why its folder would not read", problems) }
            ShellSection(title: "Assigned agents") {
                Button("Manage agents", action: manage).buttonStyle(KitButton(kind: .secondary))
            } content: {
                if skill.assignments.isEmpty {
                    QuietLine("Given to no agent yet.")
                } else {
                    ShellPanel {
                        ForEach(Array(skill.assignments.enumerated()), id: \.offset) { index, assignment in
                            if index > 0 { ShellDivider() }
                            let label = labelOf(view, assignment.agent)
                            ShellRow(title: label, caption: assignment.project.map { "In \($0)" } ?? "In its home folder") {
                                BrandLogo(agent: assignment.agent, name: label, size: SkillsLayout.logo)
                            } trailing: {
                                EmptyView()
                            }
                        }
                    }
                }
            }
            FactList(facts: [("Available", skill.skillScope == .project ? "Only in \(skill.project ?? "its repository")" : "In every workspace on this computer")])
            ShellSection(title: "Tools and permissions") {
                if permissions.isEmpty {
                    QuietLine("It asks for nothing beyond reading its own folder.")
                } else {
                    FactList(facts: permissions.map { ($0.title, $0.items.joined(separator: ", ")) })
                }
            }
            ShellSection(title: "Compatibility") {
                ShellPanel {
                    ForEach(Array(skill.compatibility.enumerated()), id: \.element.agent) { index, each in
                        if index > 0 { ShellDivider() }
                        VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
                            HStack(spacing: Memnox.Spacing.regular) {
                                BrandLogo(agent: each.agent, name: each.label, size: SkillsLayout.smallLogo)
                                Text(each.label)
                                    .font(Memnox.Console.sans(Memnox.TextSize.body))
                                    .foregroundStyle(Memnox.Console.foreground)
                                Spacer(minLength: Memnox.Spacing.medium)
                                StatusWord(!each.supported ? .bad : each.loses.isEmpty ? .good : .attention, SkillsLines.compatibility(each))
                            }
                            ForEach(each.loses, id: \.self) { loss in
                                QuietLine(loss).padding(.leading, SkillsLayout.smallLogo + Memnox.Spacing.regular)
                            }
                        }
                        .padding(.horizontal, ShellMetrics.rowPaddingH)
                        .padding(.vertical, ShellMetrics.rowPaddingV)
                    }
                }
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Memnox.Spacing.xLarge) {
                GridRow {
                    Text("Digest").font(Memnox.Console.sans(Memnox.TextSize.footnote)).foregroundStyle(Memnox.Console.muted)
                    Text(skill.digest)
                        .font(Memnox.Console.code(Memnox.TextSize.micro))
                        .foregroundStyle(Memnox.Console.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            if skill.skillScope == .personal { RemoveSkill(screen: screen, skill: skill, back: back) }
        }
    }

    private func listed(_ title: String, _ items: [String], mono: Bool = false) -> some View {
        ShellSection(title: title) {
            ShellPanel {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    if index > 0 { ShellDivider() }
                    if mono {
                        CodeRow(title: item) { EmptyView() } trailing: { EmptyView() }
                    } else {
                        ShellRow(title: item) { EmptyView() } trailing: { EmptyView() }
                    }
                }
            }
        }
    }
}

/// Removing only narrows, so it is done at once once the console's confirm is answered, since its kept versions go
/// with it.
private struct RemoveSkill: View {
    @ObservedObject var screen: SkillsScreen
    let skill: SkillView
    let back: () -> Void
    @State private var confirming = false

    var body: some View {
        ShellSection(title: "Remove") {
            QuietLine("Takes \(skill.name) out of the hub and out of every agent it was given to, with every version kept of it.")
            Button("Remove skill", systemImage: "trash") { confirming = true }
                .buttonStyle(KitButton(kind: .secondary))
                .disabled(screen.skills.busy == skill.name)
        }
        .consoleSheet(isPresented: $confirming) {
            ConsoleConfirm(symbol: "trash", title: "Remove \(skill.name)?",
                           message: "It leaves the hub and every agent it was given to, and every version kept of it goes too.",
                           confirm: "Remove skill", cancel: { confirming = false }) {
                confirming = false
                remove()
            }
        }
    }

    private func remove() {
        let name = skill.name
        Task {
            let outcome = await screen.skills.remove(name)
            screen.said(outcome)
            if case .failed = outcome { return }
            back()
        }
    }
}

/// Two columns side by side, the first taking `leftShare` times the second's width, as tall as the taller of them.
struct SharedColumns: Layout {
    let leftShare: CGFloat
    let gap: CGFloat

    private func widths(_ total: CGFloat) -> (CGFloat, CGFloat) {
        let room = max(0, total - gap)
        let left = room * leftShare / (leftShare + 1)
        return (left, room - left)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 0
        let (left, right) = widths(total)
        let heights = zip(subviews, [left, right]).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }
        return CGSize(width: total, height: heights.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (left, right) = widths(bounds.width)
        var x = bounds.minX
        for (subview, width) in zip(subviews, [left, right]) {
            subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(width: width, height: nil))
            x += width + gap
        }
    }
}

/// The name an agent goes by, as the hub labels it, or as the MCP Hub does for one the hub does not list.
private func labelOf(_ view: SkillsHubView, _ agent: String) -> String {
    view.agents.first { $0.agent == agent }?.label ?? McpHubLines.agentLabel(agent)
}

/// Skills an agent already had in its own folder, offered to bring in and never touched until then: grouped by agent,
/// each group cut to a few rows until Show all, with one Import all for every row the search leaves.
private struct SkillsFound: View {
    @ObservedObject var screen: SkillsScreen
    let view: SkillsHubView
    /// What the search leaves, not yet in the hub.
    let found: [FoundSkillView]
    /// Everything not yet in the hub, before the search.
    let total: Int
    let searching: Bool
    let preview: (FoundSkillView) -> Void
    @State private var expanded: Set<String> = []

    var body: some View {
        if total > 0 {
            ShellSection(title: "Found on this computer \u{00B7} \(SkillSearch.counted(shown: found.count, of: total, searching: searching))") {
                importAll
            } content: {
                if found.isEmpty {
                    QuietLine("Nothing an agent already has matches that search.")
                } else {
                    ForEach(SkillSearch.grouped(found) { labelOf(view, $0) }, id: \.agent) { each in agentGroup(each) }
                }
                QuietLine("Importing a skill keeps it once in the hub, with its files, so it can be given to any agent in that agent\u{2019}s own format.")
            }
        }
    }

    @ViewBuilder private var importAll: some View {
        if let progress = screen.importing {
            HStack(spacing: Memnox.Spacing.medium) {
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                    .frame(width: FoundLayout.progressWidth)
                Text(SkillSearch.importing(done: progress.done, of: progress.total))
                    .font(Memnox.Console.sans(Memnox.TextSize.footnote).monospacedDigit())
                    .foregroundStyle(Memnox.Console.muted)
            }
            .accessibilityElement(children: .combine)
        } else if !found.isEmpty {
            Button(SkillSearch.importAllTitle(found.count, searching: searching), systemImage: "square.and.arrow.down.on.square") {
                screen.importAll(found)
            }
            .buttonStyle(KitButton(kind: .primary))
            .disabled(screen.skills.busy != nil)
            .help("Imports each one in turn; any that reaches further than reading its folder waits for your signature on the island")
        }
    }

    private func agentGroup(_ group: FoundSkillGroup) -> some View {
        let open = searching || expanded.contains(group.agent)
        let rows = open ? group.skills : Array(group.skills.prefix(SkillSearch.collapsedRows))
        let hidden = group.skills.count - rows.count
        return VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            HStack(spacing: Memnox.Spacing.regular) {
                BrandLogo(agent: group.agent, name: group.label, size: SkillsLayout.smallLogo)
                Text(group.label)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .semibold))
                    .foregroundStyle(Memnox.Console.foreground)
                Text("\(group.skills.count)")
                    .font(Memnox.Console.sans(Memnox.TextSize.footnote).monospacedDigit())
                    .foregroundStyle(Memnox.Console.muted)
                Spacer(minLength: Memnox.Spacing.medium)
            }
            .accessibilityElement(children: .combine)
            ShellPanel {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, each in
                    if index > 0 { ShellDivider() }
                    FoundRow(screen: screen, found: each) { preview(each) }
                }
                if hidden > 0 || (expanded.contains(group.agent) && !searching && group.skills.count > SkillSearch.collapsedRows) {
                    ShellDivider()
                    Button(hidden > 0 ? "Show all \(group.skills.count)" : "Show fewer") {
                        if hidden > 0 { expanded.insert(group.agent) } else { expanded.remove(group.agent) }
                    }
                    .buttonStyle(QuietButton())
                    .padding(.horizontal, ShellMetrics.rowPaddingH)
                    .padding(.vertical, ShellMetrics.rowPaddingV)
                }
            }
        }
    }
}

private enum FoundLayout {
    static let progressWidth: CGFloat = 120
}

/// One skill an agent has: its name, its folder from ~ cut in the middle so both ends read, what it uses when it says,
/// and View and Import at its end. The row itself opens its SKILL.md.
private struct FoundRow: View {
    @ObservedObject var screen: SkillsScreen
    let found: FoundSkillView
    let open: () -> Void

    var body: some View {
        HStack(spacing: Memnox.Spacing.large) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                    Text(found.name)
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
                        .foregroundStyle(Memnox.Console.foreground)
                        .lineLimit(1)
                    HStack(spacing: Memnox.Spacing.small) {
                        Text(SkillSearch.shortPath(found.path, home: NSHomeDirectory()))
                            .font(Memnox.Console.code(Memnox.Console.TextSize.label))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let reach = SkillSearch.reach(found) {
                            Text("\u{00B7} \(reach)").lineLimit(1)
                        }
                    }
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                    .foregroundStyle(Memnox.Console.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressDip())
            .help(found.path)
            .accessibilityLabel("Read \(found.name)")
            Button("View", action: open).buttonStyle(KitButton(kind: .secondary))
            Button("Import") { screen.press { await $0.importFound(id: found.id, name: found.name) } }
                .buttonStyle(KitButton(kind: .secondary))
                .disabled(screen.skills.busy != nil || screen.importing != nil)
        }
        .padding(.horizontal, ShellMetrics.rowPaddingH)
        .padding(.vertical, ShellMetrics.rowPaddingV)
    }
}

/// Skills down, agents across: who has what at a glance, changed through Manage agents.
private struct AssignedGrid: View {
    let view: SkillsHubView
    let manage: (String) -> Void

    var body: some View {
        let agents = view.agents.filter(\.installed)
        if view.skills.isEmpty || agents.isEmpty {
            EmptyState(symbol: "sparkles", title: "Nothing assigned yet",
                       detail: "Once the hub holds a skill and an agent that takes skills is installed, who has what shows here.")
        } else {
            ShellPanel {
                ScrollView(.horizontal) {
                    Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                        GridRow {
                            header("Skill").frame(maxWidth: .infinity, alignment: .leading)
                            ForEach(agents, id: \.agent) { agent in
                                HStack(spacing: Memnox.Spacing.small) {
                                    BrandLogo(agent: agent.agent, name: agent.label, size: SkillsLayout.smallLogo - 2)
                                    header(agent.label)
                                }
                                .frame(minWidth: SkillsLayout.column)
                            }
                            Color.clear.frame(width: 1, height: 1)
                        }
                        .padding(.vertical, ShellMetrics.rowPaddingV)
                        ForEach(view.skills) { skill in
                            ShellDivider().gridCellUnsizedAxes(.horizontal)
                            GridRow {
                                HStack(spacing: Memnox.Spacing.medium) {
                                    Text(skill.name)
                                        .font(Memnox.Console.sans(Memnox.TextSize.body, .medium))
                                        .foregroundStyle(Memnox.Console.foreground)
                                        .lineLimit(1)
                                    if !skill.enabled {
                                        Text("Off").font(Memnox.Console.sans(Memnox.TextSize.footnote)).foregroundStyle(Memnox.Console.muted)
                                    }
                                }
                                .padding(.horizontal, ShellMetrics.rowPaddingH)
                                ForEach(agents, id: \.agent) { agent in
                                    cell(skill, agent).frame(minWidth: SkillsLayout.column)
                                }
                                Button("Manage agents") { manage(skill.name) }
                                    .buttonStyle(KitButton(kind: .secondary))
                                    .padding(.horizontal, ShellMetrics.rowPaddingH)
                            }
                            .padding(.vertical, ShellMetrics.rowPaddingV)
                        }
                    }
                }
                .scrollIndicators(.automatic)
            }
        }
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(Memnox.Console.sans(Memnox.TextSize.footnote, .semibold))
            .foregroundStyle(Memnox.Console.muted)
            .lineLimit(1)
            .padding(.horizontal, ShellMetrics.rowPaddingH)
    }

    @ViewBuilder private func cell(_ skill: SkillView, _ agent: SkillAgentView) -> some View {
        if skill.agents.contains(agent.agent) {
            Image(systemName: "checkmark")
                .font(.system(size: Memnox.TextSize.footnote, weight: .semibold))
                .foregroundStyle(Memnox.Console.success)
                .accessibilityLabel("\(skill.name) for \(agent.label)")
        } else {
            Color.clear.frame(width: 1, height: 1).accessibilityLabel("Not given to \(agent.label)")
        }
    }
}
