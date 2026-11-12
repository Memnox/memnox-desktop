import AppKit
import MemnoxVoiceCore
import SwiftUI

/// The projects for the views: redrawn whenever the core's projects change, with the line the last press ended in.
@MainActor
final class ProjectsScreen: ObservableObject {
    let projects: Projects
    /// Bumped when the projects change, so every view reading them is drawn again.
    @Published private(set) var tick = 0
    /// What the last press came to, shown above the page until the next one.
    @Published var note: String?

    init(projects: Projects) {
        self.projects = projects
        projects.changed = { [weak self] in
            Task { @MainActor [weak self] in self?.tick += 1 }
        }
    }

    /// What the last Apply on each project came to and when, by project id, shown under its button rather than as the page note.
    @Published private(set) var applied: [String: (outcome: ProjectOutcome, at: Date)] = [:]

    /// Applies one project and keeps what the runtime said beside its button.
    func apply(_ id: String) {
        applied[id] = nil
        Task {
            let outcome = await projects.apply(id)
            applied[id] = (outcome, Date())
        }
    }

    /// Runs one press and says how it ended, the part waiting on the island named with Touch ID.
    func press(_ work: @escaping (Projects) async -> ProjectOutcome, then: ((ProjectOutcome) -> Void)? = nil) {
        Task {
            let outcome = await work(projects)
            note = ProjectLines.note(outcome)
            then?(outcome)
        }
    }
}

extension Tone {
    init(_ tone: ProjectTone) {
        switch tone {
        case .good: self = .good
        case .attention: self = .attention
        case .bad: self = .bad
        case .quiet: self = .quiet
        }
    }
}

enum ProjectsLayout {
    static let cardWidth: CGFloat = 280
    static let searchWidth: CGFloat = 240
    static let logo: CGFloat = 20
    static let bigLogo: CGFloat = 24
    static let overlap: CGFloat = -6
    static let ring: CGFloat = 2
}

/// Projects as the runtime keeps them, modelled on the console's projects page: a card each, most recently active first,
/// saying who works there now, what waits on the person there and when anything last happened; the folders the agents
/// already worked in are offered to add with one press. A press on a card opens the project, which swaps the sidebar
/// for the project's own pages.
struct ProjectsDestination: View {
    @ObservedObject var screen: ProjectsScreen
    @ObservedObject var shell: AppShellModel
    @ObservedObject var island: IslandModel
    let account: AccountModel?
    let width: WidthClass
    @State private var query = ""
    /// The folder being added, so its button says so and the others wait.
    @State private var adding: String?

    var body: some View {
        page
            .task { await screen.projects.refresh() }
            // A signature on the island changes what a project gives, so the projects are read again.
            .onChange(of: island.waiting.count) { Task { await screen.projects.refresh() } }
    }

    @ViewBuilder private var page: some View {
        let projects = screen.projects
        if let list = projects.projects, let place = ProjectSidebar.place(of: shell.route) {
            if let project = list.first(where: { $0.id == place.id }) {
                if let account {
                    SignedInReading(account: account) { joined in
                        ProjectPages(screen: screen, shell: shell, project: project, page: place.page, joined: joined, width: width)
                    }
                } else {
                    ProjectPages(screen: screen, shell: shell, project: project, page: place.page, joined: false, width: width)
                }
            } else {
                ShellScroll(width: width) {
                    EmptyState(symbol: "folder", title: ProjectSidebar.goneTitle, detail: ProjectSidebar.goneLine)
                    GoLink(ProjectSidebar.backTitle) { shell.go(ProjectSidebar.list) }
                }
            }
        } else if let list = projects.projects {
            ShellScroll(width: width) {
                let suggestions = folders(list)
                header(list)
                NoteBanner(text: screen.note)
                if list.isEmpty {
                    EmptyState(symbol: "folder.badge.plus", title: ProjectContext.emptyTitle, detail: ProjectContext.emptyLine)
                } else {
                    cards(list)
                }
                if !suggestions.isEmpty { suggested(suggestions, busy: projects.busy != nil) }
            }
        } else if projects.unreadable {
            ShellScroll(width: width) { ReadFailed(what: "the projects") { Task { await projects.refresh() } } }
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The count, the search once there are enough to need one, and Choose a folder.
    private func header(_ list: [ProjectView]) -> some View {
        HStack(spacing: Memnox.Spacing.large) {
            if !list.isEmpty {
                Text("\(ProjectLines.counted(list.count, "project", "projects")), most recently active first.")
                    .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Console.muted)
            }
            Spacer(minLength: Memnox.Spacing.medium)
            if list.count >= ProjectContext.searchFrom {
                SearchField(prompt: ProjectContext.searchPrompt, text: $query).frame(maxWidth: ProjectsLayout.searchWidth)
            }
            Button(adding == nil ? ProjectContext.chooseTitle : "Adding", systemImage: "folder.badge.plus", action: choose)
                .buttonStyle(KitButton(kind: list.isEmpty ? .primary : .secondary))
                .disabled(screen.projects.busy != nil)
                .help(ProjectLines.openLine)
        }
    }

    @ViewBuilder private func cards(_ list: [ProjectView]) -> some View {
        let shown = ProjectContext.matching(ProjectContext.recent(list), query: query)
        if shown.isEmpty {
            EmptyState(symbol: "magnifyingglass", title: "No project matches that.", detail: "Try another word, or clear the search.")
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: ProjectsLayout.cardWidth), spacing: Memnox.Spacing.large)],
                      spacing: Memnox.Spacing.large) {
                ForEach(shown) { each in
                    ProjectCard(project: each, chips: ProjectPageLines.chips(each, sources: shell.memory?.memory.sources ?? []),
                                pulse: ProjectContext.pulse(each, sessions: island.cards,
                                                            waitingPlaces: island.waiting.entries.map(\.card.place), now: Date()),
                                busy: screen.projects.busy != nil,
                                pick: { open(each.id) },
                                rename: { name in
                                    guard let draft = ProjectPageLines.draft(of: each, renamed: name) else { return }
                                    let path = each.path
                                    screen.press { await $0.put(path, draft: draft) }
                                })
                }
            }
        }
    }

    /// The folders the agents already worked in that are not projects yet, each one press from being one.
    private func suggested(_ seen: [SeenWorkspace], busy: Bool) -> some View {
        ShellSection(title: ProjectContext.suggestionsTitle) {
            ProjectMuted(ProjectContext.suggestionsNote)
            ShellPanel {
                ForEach(Array(seen.enumerated()), id: \.element.id) { index, folder in
                    if index > 0 { ShellDivider() }
                    ShellRow(title: folder.name,
                             caption: [folder.path, folder.lastActive.map { "Active \($0)" }].compactMap { $0 }.joined(separator: SessionText.separator)) {
                        Image(systemName: "folder")
                            .foregroundStyle(Memnox.Console.muted)
                            .accessibilityHidden(true)
                    } trailing: {
                        AgentLogos(agents: folder.agents.map(\.kind))
                        Button(adding == folder.path ? "Adding" : ProjectContext.addTitle, systemImage: "plus") { add(folder.path) }
                            .buttonStyle(KitButton(kind: .secondary))
                            .disabled(busy)
                            .accessibilityLabel("Add \(folder.name) as a project")
                    }
                }
            }
            ProjectMuted(ProjectLines.openLine)
        }
    }

    /// The folders the sessions ran in that are not projects yet, the most recently active first.
    private func folders(_ list: [ProjectView]) -> [SeenWorkspace] {
        let seen = SeenWorkspaces.from(island.cards, now: Date())
        let open = Set(ProjectLines.foldersToOpen(seen.map { FolderPick(path: $0.path, name: $0.name) }, projects: list).map(\.path))
        return seen.filter { open.contains($0.path) }
    }

    private func open(_ id: String) {
        shell.projectId = id
        shell.go(ProjectSidebar.route(id))
    }

    /// Takes a folder in through the daemon's own open, then opens the project it became.
    private func add(_ folder: String) {
        if let problem = LaunchLines.folderProblem(folder) {
            screen.note = problem
            return
        }
        adding = folder
        screen.press({ await $0.open(folder) }) { outcome in
            adding = nil
            if case .failed = outcome { return }
            let made = screen.projects.projects?.first { ShellLines.inside(folder, project: $0.path) && ShellLines.inside($0.path, project: folder) }
            if let made { open(made.id) }
        }
    }

    /// Finder's own panel, which also takes a typed path with Command Shift G.
    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add as a project"
        panel.message = ProjectContext.emptyLine
        guard panel.runModal() == .OK, let url = panel.url else { return }
        add(url.path)
    }
}

/// One project as the console's Projects grid draws it: its name and standing, what it is for, the agents given it,
/// chips for its tools and memory, and a menu to rename or remove it. A press anywhere else opens it. Its repository is one of its tools, so it
/// is not what the card leads with.
private struct ProjectCard: View {
    let project: ProjectView
    let chips: [String]
    /// Who works there now, what waits on the person there, and when anything last happened.
    let pulse: ProjectPulse
    let busy: Bool
    let pick: () -> Void
    /// Saves a new name, on the person's own project; the organization's is renamed in Memnox Cloud.
    let rename: (String) -> Void
    /// The name being typed while the card is renamed in place, nil otherwise.
    @State private var renaming: String?
    @Environment(\.openURL) private var openURL

    private static let menuWidth: CGFloat = 24

    var body: some View {
        if let draft = renaming {
            renameForm(draft)
        } else {
            card
        }
    }

    /// The card renamed in place, with no sheet: the name in a field, Save and Cancel.
    private func renameForm(_ draft: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
        let text = Binding(get: { renaming ?? draft }, set: { renaming = $0 })
        return VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
            Text(ProjectPageLines.renameHeading(project))
                .font(Memnox.Console.sans(Memnox.TextSize.footnote, .medium))
                .foregroundStyle(Memnox.Console.muted)
            TextField(ProjectPageLines.namePrompt, text: text)
                .kitField()
                .onSubmit(save)
                .accessibilityLabel("The project\u{2019}s new name")
            HStack(spacing: Memnox.Spacing.medium) {
                Button("Save", action: save)
                    .buttonStyle(KitButton(kind: .primary))
                    .disabled(busy || ProjectPageLines.draft(of: project, renamed: draft) == nil)
                Button("Cancel") { renaming = nil }.buttonStyle(KitButton(kind: .secondary))
            }
        }
        .padding(Memnox.Spacing.xLarge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Memnox.Console.card, in: shape)
        .overlay(shape.strokeBorder(Memnox.Console.primary, lineWidth: Memnox.Stroke.hairline))
    }

    private func save() {
        if let name = renaming { rename(name) }
        renaming = nil
    }

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
        let standing = ProjectLines.standing(project)
        return Button(action: pick) {
            VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
                HStack(spacing: Memnox.Spacing.medium) {
                    Image(systemName: "folder").foregroundStyle(Memnox.Console.muted).accessibilityHidden(true)
                    Text(project.name)
                        .font(Memnox.Console.sans(Memnox.TextSize.body, .semibold))
                        .foregroundStyle(Memnox.Console.foreground)
                        .lineLimit(1)
                    Spacer(minLength: Memnox.Spacing.small)
                    if project.sharedBy != nil { OrganizationBadge() } else { StatusWord(Tone(standing.tone), standing.word) }
                    // Room for the menu laid over the corner, outside the card's own button.
                    Color.clear.frame(width: Self.menuWidth, height: 1)
                }
                Text(project.path)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                    .foregroundStyle(Memnox.Console.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(project.path)
                Text(ProjectLines.cardLine(project))
                    .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Console.foreground)
                    .lineLimit(2, reservesSpace: true)
                VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
                    if let working = pulse.workingLine { pulseLine(.good, working) }
                    if let waiting = pulse.waitingLine { pulseLine(.attention, waiting) }
                    pulseLine(.quiet, pulse.lastActivity)
                }
                HStack(spacing: Memnox.Spacing.small) {
                    ForEach(chips, id: \.self) { chip in
                        Text(chip)
                            .font(Memnox.Console.sans(Memnox.Console.TextSize.label, .medium))
                            .foregroundStyle(Memnox.Console.muted)
                            .padding(.horizontal, Memnox.Spacing.regular)
                            .padding(.vertical, Memnox.Spacing.xxSmall)
                            .background(Memnox.Console.hover, in: Capsule())
                    }
                    Spacer(minLength: Memnox.Spacing.medium)
                    AgentLogos(agents: project.agents)
                }
            }
            .padding(Memnox.Spacing.xLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Memnox.Console.card, in: shape)
            .overlay(shape.strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
            .hoverLight(radius: ShellMetrics.radius, inset: 0)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .pointingHand()
        .accessibilityElement(children: .combine)
        .accessibilityLabel([project.name, project.sharedBy == nil ? standing.word : ProjectLines.fromOrganization,
                             pulse.workingLine, pulse.waitingLine, pulse.lastActivity].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint("Opens the project")
        .accessibilityAddTraits(.isButton)
        .overlay(alignment: .topTrailing) { menu.padding(Memnox.Spacing.large) }
    }

    private func pulseLine(_ tone: Tone, _ words: String) -> some View {
        HStack(spacing: Memnox.Spacing.small) {
            Circle().fill(tone.dot).frame(width: ShellMetrics.dot, height: ShellMetrics.dot)
            Text(words)
                .font(Memnox.Console.sans(Memnox.Console.TextSize.meta, tone == .quiet ? .regular : .medium))
                .foregroundStyle(tone == .quiet ? Memnox.Console.muted : tone.color)
                .lineLimit(1)
        }
    }

    private var menu: some View {
        Menu {
            if project.sharedBy != nil, let url = ProjectPageLines.cloudLink(project) {
                // The organization keeps this project, so both are done where it is kept.
                Button(ProjectPageLines.renameInCloud, systemImage: "pencil") { openURL(url) }
                Button(ProjectPageLines.removeInCloud, systemImage: "trash") { openURL(url) }
            } else {
                // No remove is offered, since the runtime keeps no way to forget a project and a button that never
                // works is a dead end.
                Button(ProjectPageLines.renameTitle, systemImage: "pencil") { renaming = project.name }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: Memnox.TextSize.caption, weight: .semibold))
                .foregroundStyle(Memnox.Console.muted)
                .frame(width: Self.menuWidth, height: Self.menuWidth)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More for \(project.name)")
        .accessibilityLabel("More for \(project.name)")
    }
}

/// The agents' logos overlapping, as the cards and the grants show who has a thing.
struct AgentLogos: View {
    let agents: [String]

    var body: some View {
        HStack(spacing: ProjectsLayout.overlap) {
            ForEach(agents, id: \.self) { kind in
                BrandLogo(agent: kind, name: McpHubLines.agentLabel(kind), size: ProjectsLayout.logo)
                    .overlay(RoundedRectangle(cornerRadius: ProjectsLayout.logo / 4, style: .continuous)
                        .strokeBorder(Memnox.Console.card, lineWidth: ProjectsLayout.ring))
            }
        }
    }
}

/// A quiet line of a project's pages.
struct ProjectMuted: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(Memnox.Console.sans(Memnox.TextSize.footnote))
            .foregroundStyle(Memnox.Console.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// What the last Apply came to, under its button: a tick for a change, a note for nothing to change, amber for what
/// waits on the island, red for a refusal, with the time it was said.
struct ApplyResultLine: View {
    let outcome: ProjectOutcome
    let at: Date

    var body: some View {
        let mark = ProjectLines.mark(outcome)
        Label {
            Text("\(ProjectLines.note(outcome))\(SessionText.separator)\(at.formatted(date: .omitted, time: .shortened))")
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        } icon: {
            Image(systemName: Self.symbol(mark)).accessibilityHidden(true)
        }
        .font(Memnox.Console.sans(Memnox.TextSize.footnote))
        .foregroundStyle(Self.tint(mark))
        .accessibilityAddTraits(.updatesFrequently)
    }

    private static func symbol(_ mark: ProjectResultMark) -> String {
        switch mark {
        case .changed: "checkmark.circle"
        case .waiting: "hand.raised"
        case .upToDate: "checkmark"
        case .failed: "exclamationmark.triangle"
        }
    }

    private static func tint(_ mark: ProjectResultMark) -> Color {
        switch mark {
        case .changed: Memnox.Console.success
        case .waiting: Memnox.Console.warm
        case .upToDate: Memnox.Console.muted
        case .failed: Memnox.Console.destructive
        }
    }
}

/// The badge a project the organization shares carries in place of its standing.
struct OrganizationBadge: View {
    var body: some View {
        Label(ProjectLines.fromOrganization, systemImage: "building.2")
            .font(Memnox.Console.sans(Memnox.TextSize.footnote, .medium))
            .foregroundStyle(Memnox.Console.muted)
            .padding(.horizontal, Memnox.Spacing.medium)
            .padding(.vertical, Memnox.Spacing.xSmall)
            .overlay(Capsule().strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
            .lineLimit(1)
    }
}

/// What the organization hands a shared project, read only: servers, skills, its rule pack, memory, and what was left out.
struct OrganizationPanel: View {
    let organization: ProjectOrganizationView

    var body: some View {
        ShellSection(title: "From your organization") {
            if let description = organization.description { ProjectMuted(description) }
            ShellPanel {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { ShellDivider() }
                    ShellRow(title: row.title, caption: row.caption) { EmptyView() } trailing: { EmptyView() }
                }
            }
            ForEach(organization.skipped, id: \.self) { ProjectMuted($0) }
        }
    }

    private var rows: [(title: String, caption: String)] {
        [("Repository", organization.repository),
         ("MCP servers", names(organization.servers)),
         ("Skills", names(organization.skills)),
         ("Rule pack", ProjectLines.organizationRulesLine(organization)),
         ("Memory", ProjectLines.organizationMemoryLine(organization.memory))]
    }

    private func names(_ list: [String]) -> String {
        list.isEmpty ? "None" : list.joined(separator: ", ")
    }
}

