import MemnoxVoiceCore
import SwiftUI

/// One project's own pages, opened from Projects with the sidebar swapped for the project's: its Overview with what it
/// learned lately, its agents, its memory, and what its AI may do. Each is a page; nothing opens a sheet. The
/// desktop is one person's, so people and the cloud's own actions show only once this Mac is joined to a workspace.
struct ProjectPages: View {
    @ObservedObject var screen: ProjectsScreen
    @ObservedObject var shell: AppShellModel
    let project: ProjectView
    let page: ProjectPage
    let joined: Bool
    let width: WidthClass

    var body: some View {
        let team = ProjectPageLines.showsTeam(project, joined: joined)
        ShellScroll(width: width) {
            switch page {
            // Tools is left off for now, so a route to it shows the Overview, which holds its folder.
            case .overview, .tools: ProjectOverviewPage(screen: screen, shell: shell, project: project, team: team)
            case .agents: ProjectAgentsPage(shell: shell, project: project)
            case .memory:
                if let memory = shell.memory {
                    ProjectMemoryPage(memory: memory, shell: shell, project: project)
                } else {
                    ProjectMuted(ProjectContext.memoryHereEmpty)
                }
            case .rules: ProjectRulesPage(shell: shell, project: project)
            }
        }
        .task { await screen.projects.refresh() }
        .task { await shell.memory?.memory.refreshSources() }
        // Opening a project narrows the shared pages to what applies here, as the top bar's picker does.
        .onAppear { if shell.projectId != project.id { shell.projectId = project.id } }
    }
}

/// Where a shared page lives, nil while the daemon answers none of its tabs, so no badge links nowhere.
@MainActor
func sharedRoute(_ id: SidebarRowId, shell: AppShellModel) -> WindowRoute? {
    Sidebar.rows.first { $0.id == id }.flatMap { Sidebar.target($0, supports: shell.supports) }
}

/// The small badge saying whether an item belongs to this project alone or is shared with every project; a shared
/// one opens the page where it is changed.
struct ReachBadge: View {
    let reach: ItemReach
    var open: (() -> Void)?

    var body: some View {
        if let open, reach == .everyProject {
            Button(action: open) { face(link: true) }
                .buttonStyle(.plain)
                .pointingHand()
                .help("\(reach.hint). Opens that page.")
                .accessibilityLabel(reach.word)
                .accessibilityHint(reach.hint)
        } else {
            face(link: false)
                .help(reach.hint)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(reach.word)
        }
    }

    private func face(link: Bool) -> some View {
        HStack(spacing: Memnox.Spacing.xxSmall) {
            Image(systemName: reach == .onlyHere ? "folder" : "square.stack")
                .font(.system(size: Memnox.TextSize.micro, weight: .semibold))
            Text(reach.word)
            if link {
                Image(systemName: "arrow.up.right").font(.system(size: Memnox.TextSize.micro, weight: .semibold))
            }
        }
        .font(Memnox.Console.sans(Memnox.Console.TextSize.label, .medium))
        .foregroundStyle(reach == .onlyHere ? Memnox.Console.primary : Memnox.Console.muted)
        .padding(.horizontal, Memnox.Spacing.regular)
        .padding(.vertical, Memnox.Spacing.xxSmall)
        .background(reach == .onlyHere ? Memnox.Console.primary.opacity(ReachLayout.wash) : Memnox.Console.hover, in: Capsule())
        .fixedSize()
    }
}

private enum ReachLayout {
    /// A wash light enough that the word stays what is read.
    static let wash = 0.1
}

/// What one project learned, each fact marked as only here, then the few facts every project knows, which are
/// changed on the shared Memory page.
private struct ProjectMemoryPage: View {
    @ObservedObject var memory: MemoryScreen
    @ObservedObject var shell: AppShellModel
    let project: ProjectView

    var body: some View {
        let split = ProjectContext.memory(memory.memory.facts?.items ?? [], in: project)
        let open = sharedRoute(.memory, shell: shell)
        ShellSection(title: ProjectContext.memoryHereTitle) {
            if memory.memory.unreadable.facts {
                ReadFailed(what: "what was learned") { Task { await memory.memory.show(MemoryFilter()) } }
            } else if memory.memory.facts == nil {
                ProgressView().controlSize(.small)
            } else if split.here.isEmpty {
                ProjectMuted(ProjectContext.memoryHereEmpty)
            } else {
                ShellPanel {
                    ForEach(Array(split.here.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { ShellDivider() }
                        ShellRow(title: item.statement, caption: MemoryLines.rowCaption(item)) { EmptyView() } trailing: {
                            ReachBadge(reach: .onlyHere)
                        }
                    }
                }
            }
        }
        ShellSection(title: ProjectContext.memoryEverywhereTitle) {
            ProjectMuted(ProjectContext.memoryEverywhereNote)
            if !split.everywhere.isEmpty {
                ShellPanel {
                    ForEach(Array(split.everywhere.prefix(ProjectContext.everywhereShown).enumerated()), id: \.element.id) { index, item in
                        if index > 0 { ShellDivider() }
                        ShellRow(title: item.statement, caption: MemoryLines.rowCaption(item)) { EmptyView() } trailing: {
                            ReachBadge(reach: .everyProject, open: open.map { route in { shell.go(route) } })
                        }
                    }
                }
            }
            if let open { GoLink("All memory, shared with every project") { shell.go(open) } }
        }
        .task { if memory.memory.facts == nil { await memory.memory.show(MemoryFilter()) } }
    }
}

/// Reads whether this Mac is joined to a Memnox Cloud workspace, by the person's sign in or the machine's own,
/// drawing again whenever the person signs in or out.
struct SignedInReading<Content: View>: View {
    @ObservedObject var account: AccountModel
    @ViewBuilder let content: (Bool) -> Content

    var body: some View { content(account.isSignedIn || account.machine?.isSignedIn == true) }
}

/// A plain link to the project in Memnox Cloud, for what is changed there rather than on this Mac.
struct CloudLink: View {
    let project: ProjectView
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let url = ProjectPageLines.cloudLink(project) {
            Button { openURL(url) } label: {
                Label(ProjectPageLines.openInCloud, systemImage: "arrow.up.right.square")
            }
            .buttonStyle(KitButton(kind: .secondary))
            .help(url.absoluteString)
        }
    }
}

private enum PagesLayout {
    static let stepMark: CGFloat = 16
    static let descriptionWidth: CGFloat = 560
}

/// The Overview in Memnox Cloud's order: the name and what it is for, Get it ready while it is still empty, what its AI
/// can use, what it learned lately, its people once this Mac is joined to a workspace, and at the foot its folder.
private struct ProjectOverviewPage: View {
    @ObservedObject var screen: ProjectsScreen
    @ObservedObject var shell: AppShellModel
    let project: ProjectView
    let team: Bool

    var body: some View {
        let sources = shell.memory?.memory.sources ?? []
        let rulesHere = shell.studio?.studio.rules.map { ProjectLines.rules($0.rules, in: project).here.count } ?? 0
        let steps = ProjectPageLines.readySteps(project, sources: sources, rulesHere: rulesHere)
        header
        if ProjectPageLines.showsChecklist(steps) {
            ShellSection(title: "Get it ready") {
                ShellPanel {
                    ForEach(Array(steps.enumerated()), id: \.element.title) { index, step in
                        if index > 0 { ShellDivider() }
                        ShellRow(title: step.title, caption: step.detail, action: { shell.go(ProjectSidebar.route(project.id, step.page)) }) {
                            Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: PagesLayout.stepMark))
                                .foregroundStyle(step.done ? Memnox.Console.success : Memnox.Console.faint)
                                .accessibilityLabel(step.done ? "Done" : "To do")
                        } trailing: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: Memnox.TextSize.caption, weight: .semibold))
                                .foregroundStyle(Memnox.Console.faint)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        ProjectCanUse(project: project, team: team) { target in
            switch target {
            case .page(let page): shell.go(ProjectSidebar.route(project.id, page))
            case .shared(let row): if let route = sharedRoute(row, shell: shell) { shell.go(route) }
            }
        }
        if let memory = shell.memory {
            LearnedLately(memory: memory, project: project) { shell.go(ProjectSidebar.route(project.id, .memory)) }
        }
        if team { ProjectTeam(project: project) }
        ProjectOnThisMac(screen: screen, project: project)
    }

    private var header: some View {
        let standing = ProjectLines.standing(project)
        return VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            HStack(alignment: .firstTextBaseline, spacing: Memnox.Spacing.medium) {
                Text(project.name)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.title, .semibold))
                    .tracking(Memnox.Console.titleTracking)
                    .foregroundStyle(Memnox.Console.foreground)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Memnox.Spacing.medium)
                if project.sharedBy != nil { OrganizationBadge() } else { StatusWord(Tone(standing.tone), standing.word) }
            }
            Text(ProjectPageLines.description(project) ?? "No description yet.")
                .font(Memnox.Console.sans(Memnox.Console.TextSize.base))
                .foregroundStyle(ProjectPageLines.description(project) == nil ? Memnox.Console.muted : Memnox.Console.foreground)
                .lineSpacing(Memnox.Spacing.xSmall)
                .frame(maxWidth: PagesLayout.descriptionWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let problems = project.problems, !problems.isEmpty {
                ForEach(problems, id: \.self) { problem in
                    Text(problem)
                        .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                        .foregroundStyle(Memnox.Console.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// The few facts learned here most recently, with the way to all of them.
private struct LearnedLately: View {
    @ObservedObject var memory: MemoryScreen
    let project: ProjectView
    let more: () -> Void

    var body: some View {
        let learned = ProjectPageLines.learned(memory.memory.facts?.items ?? [], in: project)
        ShellSection(title: "Learned lately") {
            if learned.isEmpty {
                ProjectMuted("Nothing learned here yet. As its AI works in the tools it lives in, what it learns shows here.")
            } else {
                ShellPanel {
                    ForEach(Array(learned.prefix(ProjectPageLines.learnedShown).enumerated()), id: \.element.id) { index, item in
                        if index > 0 { ShellDivider() }
                        ShellRow(title: item.statement, caption: MemoryLines.rowCaption(item)) { EmptyView() } trailing: { EmptyView() }
                    }
                }
                if learned.count > ProjectPageLines.learnedShown { GoLink("Everything it learned", action: more) }
            }
        }
        .task { if memory.memory.facts == nil { await memory.memory.show(MemoryFilter()) } }
    }
}

/// The project's people, shown only once this Mac is joined to a workspace or the organization shares it: who shares it, or the way
/// to share it, both in Memnox Cloud where people are added.
private struct ProjectTeam: View {
    let project: ProjectView

    var body: some View {
        ShellSection(title: ProjectPageLines.teamTitle) {
            ProjectMuted(ProjectPageLines.teamLine(project))
            if project.sharedBy == nil, let url = ProjectPageLines.cloudLink(project) {
                CloudButton(title: ProjectPageLines.shareTitle, url: url).fixedSize()
            } else {
                CloudLink(project: project)
            }
        }
    }
}

/// The project's folder at the Overview's foot, and Apply or Save as project on the person's own, or the line saying the
/// organization changes it in Memnox Cloud.
private struct ProjectOnThisMac: View {
    @ObservedObject var screen: ProjectsScreen
    let project: ProjectView

    var body: some View {
        let busy = screen.projects.busy == project.id || screen.projects.busy == project.path
        ShellSection(title: "Folder") {
            VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
                Text(project.path)
                    .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Console.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(project.path)
                    .textSelection(.enabled)
                if let organization = project.sharedBy {
                    ProjectMuted(organization.editedIn)
                    CloudLink(project: project)
                } else {
                    controls(busy: busy)
                }
                NoteBanner(text: screen.note)
                ProjectMuted(ProjectLines.sessionsLine(project, now: Date()))
            }
        }
    }

    @ViewBuilder private func controls(busy: Bool) -> some View {
        Group {
            if project.declared {
                let id = project.id
                let current = screen.applied[id].map { ProjectLines.mark($0.outcome) } == .upToDate
                Button { screen.apply(id) } label: {
                    HStack(spacing: Memnox.Spacing.small) {
                        if busy {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: current ? "checkmark" : "play").accessibilityHidden(true)
                        }
                        Text(busy ? "Applying" : current ? "Up to date" : "Apply")
                    }
                }
                .help(current ? "Nothing needed applying when you last pressed. Press to check again." : "Hands this project\u{2019}s setup to its agents")
            } else {
                Button(busy ? "Saving" : "Save as project", systemImage: "square.and.arrow.down") {
                    let path = project.path, draft = ProjectLines.draft(of: project)
                    screen.press { await $0.put(path, draft: draft) }
                }
            }
        }
        .buttonStyle(KitButton(kind: .primary))
        .disabled(busy)
        if project.declared, let last = screen.applied[project.id] {
            ApplyResultLine(outcome: last.outcome, at: last.at)
        } else {
            ProjectMuted(ProjectLines.pressLine(declared: project.declared))
        }
    }
}

/// The tools a project lives in, laid out as the Connectors page lays out its own: a categories rail, one search and a
/// grid of cards, a card for each kind of tool with what is linked to it and its add action on the card itself.
/// Left off for now with `ProjectPage.tools`, so nothing opens it.
private struct ProjectToolsPage: View {
    @ObservedObject var screen: ProjectsScreen
    @ObservedObject var shell: AppShellModel
    let project: ProjectView
    let joined: Bool
    @State private var category: ProjectToolCategory?
    @State private var query = ""

    private enum Layout {
        static let cardMinimum: CGFloat = 240
        static let gridSpacing: CGFloat = 16
        static let railSpacing: CGFloat = 24
    }

    private static let columns = [GridItem(.adaptive(minimum: Layout.cardMinimum), spacing: Layout.gridSpacing, alignment: .top)]

    var body: some View {
        let cards = ProjectToolCatalog.cards(project, sources: shell.memory?.memory.sources ?? [])
        let shown = ProjectToolCatalog.shown(cards, category: category, query: query)
        NoteBanner(text: screen.note)
        if project.sharedBy != nil { ProjectMuted(ProjectPageLines.sharedLine) }
        HStack(alignment: .top, spacing: Layout.railSpacing) {
            CategoryRail(heading: "Categories", allTitle: "All tools", total: cards.count,
                         categories: ProjectToolCatalog.categories(cards), chosen: category?.rawValue) {
                category = $0.flatMap(ProjectToolCategory.init(rawValue:))
            }
            VStack(alignment: .leading, spacing: SettingsMetrics.pageSpacing) {
                SearchField(prompt: "Search this project\u{2019}s tools", text: $query)
                if shown.isEmpty {
                    EmptyState(symbol: "magnifyingglass", title: "No tool matches that.", detail: "Try another word, or pick All tools.")
                } else {
                    LazyVGrid(columns: Self.columns, alignment: .leading, spacing: Layout.gridSpacing) {
                        ForEach(shown) { card in
                            ProjectToolTile(screen: screen, shell: shell, project: project, card: card, joined: joined)
                        }
                    }
                }
                if joined, !ProjectToolCatalog.showsTeamTools {
                    ProjectMuted(ProjectPageLines.cloudToolsLine)
                    CloudLink(project: project)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One card of the Tools page, drawn as the Connectors page draws a connector: its mark, name and line, what is
/// linked to it, and its add action at the foot.
private struct ProjectToolTile: View {
    @ObservedObject var screen: ProjectsScreen
    @ObservedObject var shell: AppShellModel
    let project: ProjectView
    let card: ProjectToolCard
    let joined: Bool

    private enum Layout {
        static let markSide: CGFloat = 40
        static let markSymbol: CGFloat = 17
        static let padding: CGFloat = 20
        static let headingSpacing: CGFloat = 12
        static let linkedShown = 3
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Memnox.Console.cardRadius, style: .continuous)
        let tone: Tone = card.linked.isEmpty ? .quiet : .good
        VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
            HStack(alignment: .top, spacing: Layout.headingSpacing) {
                Image(systemName: Self.symbol(card.slot))
                    .font(.system(size: Layout.markSymbol, weight: .medium))
                    .foregroundStyle(Memnox.Console.primary)
                    .frame(width: Layout.markSide, height: Layout.markSide)
                    .background(Memnox.Console.hover, in: RoundedRectangle(cornerRadius: Memnox.Console.controlRadius, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                    Text(card.slot.title)
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .semibold))
                        .foregroundStyle(Memnox.Console.foreground)
                    Text(card.slot.category.title)
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                        .foregroundStyle(Memnox.Console.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(card.slot.summary)
                .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                .foregroundStyle(Memnox.Console.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Memnox.Spacing.small) {
                Circle().fill(tone.dot).frame(width: ShellMetrics.dot, height: ShellMetrics.dot)
                Text(ProjectToolCatalog.linkedLine(card))
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.meta, .medium))
                    .foregroundStyle(tone.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            if !card.linked.isEmpty { linked }
            Spacer(minLength: 0)
            foot
        }
        .padding(Layout.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Memnox.Console.card, in: shape)
        .overlay(shape.strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
        .accessibilityElement(children: .contain)
    }

    /// The first few linked, an app of the project's own with its Remove beside it.
    private var linked: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
            ForEach(Array(card.linked.prefix(Layout.linkedShown).enumerated()), id: \.offset) { _, tool in
                HStack(spacing: Memnox.Spacing.small) {
                    Text(tool.name)
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                        .foregroundStyle(Memnox.Console.foreground)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(tool.caption)
                    Spacer(minLength: Memnox.Spacing.small)
                    if let server = tool.server {
                        let everywhere = (shell.hub?.hub.hub?.servers ?? []).contains { $0.name == server && ProjectContext.givenEverywhere($0) }
                        ReachBadge(reach: ProjectContext.reach(serverGivenEverywhere: everywhere),
                                   open: sharedRoute(.servers, shell: shell).map { route in { shell.go(route) } })
                    }
                    if project.sharedBy == nil, let server = tool.server {
                        Button("Remove") {
                            let path = project.path, draft = ProjectPageLines.draft(of: project, removing: server)
                            screen.press { await $0.put(path, draft: draft) }
                        }
                        .buttonStyle(.plain)
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                        .foregroundStyle(Memnox.Console.muted)
                        .pointingHand()
                        .disabled(screen.projects.busy != nil)
                        .accessibilityLabel("Remove \(tool.name)")
                    }
                }
            }
        }
    }

    /// The add action: on this Mac where it can be saved here, the way to Memnox Cloud once joined, else none.
    @ViewBuilder private var foot: some View {
        let adding = project.sharedBy == nil ? card.slot.adding(joined: joined) : .cloud
        switch adding {
        case nil:
            EmptyView()
        case .files:
            Button(card.slot.addTitle, systemImage: "plus") { shell.go(WindowRoute(.workspaces, tab: "sources")) }
                .buttonStyle(KitButton(kind: .primary, wide: true))
        case .apps:
            let added = Set(project.servers.map(\.name))
            let offered = (shell.hub?.hub.hub?.servers ?? []).filter { !added.contains($0.name) }
            if offered.isEmpty {
                Button("Connect an app", systemImage: "plus") { shell.go(WindowRoute(.mcp, tab: "apps")) }
                    .buttonStyle(KitButton(kind: .secondary, wide: true))
            } else {
                Menu {
                    ForEach(offered) { server in
                        Button(server.name) {
                            let path = project.path, draft = ProjectPageLines.draft(of: project, adding: server.name)
                            screen.press { await $0.put(path, draft: draft) }
                        }
                    }
                } label: {
                    Label(card.slot.addTitle, systemImage: "plus")
                }
                .menuStyle(.button)
                .buttonStyle(KitButton(kind: .primary, wide: true))
                .disabled(screen.projects.busy != nil)
                .help("Whatever widens an agent waits for your signature on the island.")
            }
        case .cloud:
            if let url = ProjectPageLines.cloudLink(project) {
                CloudButton(title: card.slot.addTitle, url: url)
            }
        }
    }

    static func symbol(_ slot: ProjectToolSlot) -> String {
        switch slot {
        case .files: "folder"
        case .docs: "doc.text"
        case .channels: "bubble.left.and.bubble.right"
        case .meetings: "video"
        case .tickets: "checklist"
        case .apps: "square.grid.2x2"
        case .repositories: "chevron.left.forwardslash.chevron.right"
        }
    }
}

/// What its AI can use, as Memnox Cloud's Overview draws it: a part each for its agents, skills and apps, every part
/// saying what its word means while it is empty, and a press on one opens the page that holds it.
private struct ProjectCanUse: View {
    let project: ProjectView
    let team: Bool
    let open: (ProjectCanUseTarget) -> Void

    private enum Layout {
        static let partMinimum: CGFloat = 180
        static let markSide: CGFloat = 32
        static let markSymbol: CGFloat = 14
    }

    private static let columns = [GridItem(.adaptive(minimum: Layout.partMinimum), spacing: Memnox.Spacing.large, alignment: .top)]

    var body: some View {
        ShellSection(title: ProjectPageLines.canUseTitle) {
            ProjectMuted(ProjectPageLines.canUseNote)
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: Memnox.Spacing.large) {
                ForEach(ProjectPageLines.canUse(project, joined: team)) { part($0) }
            }
        }
    }

    private func part(_ part: ProjectCanUsePart) -> some View {
        let shape = RoundedRectangle(cornerRadius: Memnox.Console.cardRadius, style: .continuous)
        return Button { open(part.target) } label: {
            VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
                HStack(spacing: Memnox.Spacing.medium) {
                    Image(systemName: Self.symbol(part.kind))
                        .font(.system(size: Layout.markSymbol, weight: .medium))
                        .foregroundStyle(Memnox.Console.foreground)
                        .frame(width: Layout.markSide, height: Layout.markSide)
                        .background(Memnox.Console.hover, in: RoundedRectangle(cornerRadius: Memnox.Console.controlRadius, style: .continuous))
                        .accessibilityHidden(true)
                    Text(part.title)
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
                        .foregroundStyle(Memnox.Console.foreground)
                    if part.counted {
                        Text("\(part.names.count)")
                            .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
                            .foregroundStyle(Memnox.Console.muted)
                            .monospacedDigit()
                    }
                    Spacer(minLength: 0)
                }
                if part.names.isEmpty {
                    Text(part.empty)
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
                        .foregroundStyle(Memnox.Console.foreground)
                    ProjectMuted(part.what)
                } else {
                    VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                        ForEach(part.names.prefix(ProjectPageLines.canUseShown), id: \.self) { name in
                            Text(name)
                                .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
                                .foregroundStyle(Memnox.Console.foreground)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        if let more = ProjectPageLines.moreLine(part) { ProjectMuted(more) }
                    }
                }
            }
            .padding(Memnox.Spacing.xLarge)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Memnox.Console.card, in: shape)
            .overlay(shape.strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .pointingHand()
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(part.target.title)")
    }

    private static func symbol(_ kind: ProjectCanUseKind) -> String {
        switch kind {
        case .agents: "cpu"
        case .skills: "sparkles"
        case .apps: "puzzlepiece.extension"
        }
    }
}

/// An add action only Memnox Cloud can do, opening the project there.
private struct CloudButton: View {
    let title: String
    let url: URL
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button { openURL(url) } label: { Label(title, systemImage: "arrow.up.right.square") }
            .buttonStyle(KitButton(kind: .secondary, wide: true))
            .help("\(ProjectPageLines.openInCloud): \(url.absoluteString)")
    }
}

/// The agents that work in this project, each with what the project gives it, and the way to where every agent on this
/// computer is set up once for every project.
private struct ProjectAgentsPage: View {
    @ObservedObject var shell: AppShellModel
    let project: ProjectView

    var body: some View {
        AgentsHere(project: project)
        if let open = sharedRoute(.agents, shell: shell) {
            HStack(spacing: Memnox.Spacing.medium) {
                ReachBadge(reach: .everyProject, open: { shell.go(open) })
                ProjectMuted("AI agents are set up once for every project on this computer. This page shows the ones that work here and what this project gives each.")
            }
        }
    }
}

/// What its AI may do: the rules that hold here in plain words, then the agents given it and the skills they carry.
private struct ProjectRulesPage: View {
    @ObservedObject var shell: AppShellModel
    let project: ProjectView

    var body: some View {
        if let studio = shell.studio {
            ProjectRulesHere(studio: studio, project: project) { shell.go(WindowRoute(.governance, tab: "policies")) }
        } else {
            ProjectMuted(ProjectLines.rulesLine(project.rules))
        }
        ShellSection(title: "Its agents") { AgentsHere(project: project) }
        ShellSection(title: "Skills it carries") {
            Grants(project: project, grants: project.skills, empty: "This project gives its agents no skills.",
                   reach: { _ in .onlyHere }, open: nil)
            SharedSkills(shell: shell, project: project)
        }
        if project.sharedBy != nil {
            ProjectMuted(ProjectPageLines.sharedLine)
            CloudLink(project: project)
        }
    }
}

/// The rules reaching into this project, each family said once with a count, and how many hold everywhere.
private struct ProjectRulesHere: View {
    @ObservedObject var studio: StudioScreen
    let project: ProjectView
    let open: () -> Void

    var body: some View {
        content.task { await studio.studio.refresh() }
    }

    @ViewBuilder private var content: some View {
        ShellSection(title: "Rules that hold here") {
            if let view = studio.studio.rules {
                let found = ProjectLines.rules(view.rules, in: project)
                if found.here.isEmpty {
                    ProjectMuted("No rule names this project, so the rules of this computer decide here.")
                } else {
                    ShellPanel {
                        ForEach(Array(PlainRules.grouped(found.here).enumerated()), id: \.element.id) { index, group in
                            if index > 0 { ShellDivider() }
                            ShellRow(title: group.plain.title, caption: group.plain.caption ?? ProjectLines.rulesLine(project.rules)) {
                                EmptyView()
                            } trailing: {
                                if let count = PlainRules.countLine(group.count) { ProjectMuted(count) }
                                ReachBadge(reach: .onlyHere)
                                StatusWord(Tone(effect: group.effect), StudioLines.title(group.effect))
                            }
                        }
                    }
                }
                HStack(spacing: Memnox.Spacing.medium) {
                    ReachBadge(reach: .everyProject, open: open)
                    ProjectMuted(ProjectLines.everywhereLine(found.everywhere))
                }
                GoLink("Choose what agents may do in Protection settings", action: open)
            } else if studio.studio.unreadable {
                ReadFailed(what: "the rules") { Task { await studio.studio.refresh() } }
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }
}

/// The agents the project names, then any seen working in it that it does not name.
private struct AgentsHere: View {
    let project: ProjectView

    var body: some View {
        let seenOnly = project.agentsSeen.filter { !project.agents.contains($0) }
        if project.agents.isEmpty, seenOnly.isEmpty {
            ProjectMuted("No agent has worked here yet, and the project names none.")
        } else {
            VStack(alignment: .leading, spacing: Memnox.Spacing.xxLarge) {
                if !project.agents.isEmpty {
                    ShellSection(title: "Given this project") {
                        ShellPanel {
                            ForEach(Array(project.agents.enumerated()), id: \.element) { index, kind in
                                if index > 0 { ShellDivider() }
                                ShellRow(title: McpHubLines.agentLabel(kind), caption: given(kind)) {
                                    BrandLogo(agent: kind, name: McpHubLines.agentLabel(kind), size: ProjectsLayout.bigLogo)
                                } trailing: {
                                    if project.agentsSeen.contains(kind) {
                                        StatusWord(.good, "Worked here")
                                    } else {
                                        StatusWord(.quiet, "Not seen here")
                                    }
                                }
                            }
                        }
                    }
                }
                if !seenOnly.isEmpty {
                    ShellSection(title: "Seen here, not named") {
                        ShellPanel {
                            ForEach(Array(seenOnly.enumerated()), id: \.element) { index, kind in
                                if index > 0 { ShellDivider() }
                                ShellRow(title: McpHubLines.agentLabel(kind), caption: "Ran a session here, and the project gives it nothing") {
                                    BrandLogo(agent: kind, name: McpHubLines.agentLabel(kind), size: ProjectsLayout.bigLogo)
                                } trailing: {
                                    EmptyView()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// "2 skills, 1 server" this agent has of what the project names.
    private func given(_ kind: String) -> String {
        let skills = project.skills.filter { $0.agents.contains(kind) }.count
        let servers = project.servers.filter { $0.agents.contains(kind) }.count
        return "\(ProjectLines.counted(skills, "skill", "skills")), \(ProjectLines.counted(servers, "server", "servers"))"
    }
}

/// A skill or a server the project names, with who has it now and whether it is only here.
private struct Grants: View {
    let project: ProjectView
    let grants: [ProjectGrantView]
    let empty: String
    let reach: (ProjectGrantView) -> ItemReach
    let open: (() -> Void)?

    var body: some View {
        if grants.isEmpty {
            ProjectMuted(empty)
        } else {
            ShellPanel {
                ForEach(Array(grants.enumerated()), id: \.element.name) { index, grant in
                    if index > 0 { ShellDivider() }
                    ShellRow(title: grant.name, caption: ProjectLines.grantLine(grant, of: project.agents.count)) {
                        EmptyView()
                    } trailing: {
                        ReachBadge(reach: reach(grant), open: open)
                        if grant.inHub {
                            AgentLogos(agents: grant.agents)
                        } else {
                            StatusWord(.attention, "Not in the hub")
                        }
                    }
                }
            }
        }
    }
}

/// The skills every project's agents carry, the person's own and the organization's, each linking to Skills.
private struct SharedSkills: View {
    @ObservedObject var shell: AppShellModel
    let project: ProjectView

    private static let shown = 5

    var body: some View {
        let open = sharedRoute(.skills, shell: shell)
        let skills = (shell.skills?.skills.hub?.skills ?? []).filter {
            ProjectContext.reach(skillScope: $0.scope, skillProject: $0.project, in: project) == .everyProject
        }
        if !skills.isEmpty {
            ShellPanel {
                ForEach(Array(skills.prefix(Self.shown).enumerated()), id: \.element.id) { index, skill in
                    if index > 0 { ShellDivider() }
                    ShellRow(title: skill.name, caption: skill.description) { EmptyView() } trailing: {
                        ReachBadge(reach: .everyProject, open: open.map { route in { shell.go(route) } })
                    }
                }
            }
            if skills.count > Self.shown, let open {
                GoLink("\(skills.count - Self.shown) more in Skills") { shell.go(open) }
            }
        }
    }
}
