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

private enum ProjectsLayout {
    static let cardWidth: CGFloat = 260
    static let logo: CGFloat = 20
    static let bigLogo: CGFloat = 24
    static let overlap: CGFloat = -6
    static let ring: CGFloat = 2
}

/// Projects as the runtime keeps them, with what each gives the agents opened in it: a card each, Open a folder above,
/// and the inspector beside them with a tab for each thing a project carries.
struct ProjectsDestination: View {
    @ObservedObject var screen: ProjectsScreen
    @ObservedObject var shell: AppShellModel
    @ObservedObject var island: IslandModel
    let width: WidthClass
    @State private var opening = false

    var body: some View {
        page
            .task { await screen.projects.refresh() }
            // A signature on the island changes what a project gives, so the projects are read again.
            .onChange(of: island.waiting.count) { Task { await screen.projects.refresh() } }
    }

    @ViewBuilder private var page: some View {
        let projects = screen.projects
        if let list = projects.projects {
            let picked = list.first { $0.id == shell.inspecting }
            InspectorLayout(width: width, title: picked?.name, close: { shell.inspecting = nil }) {
                ShellScroll(width: width) {
                    HStack(spacing: Memnox.Spacing.large) {
                        Text("\(ProjectLines.counted(list.count, "project", "projects")), most recently active first.")
                            .font(Memnox.sans(Memnox.TextSize.footnote))
                            .foregroundStyle(Memnox.Palette.muted)
                        Spacer(minLength: Memnox.Spacing.medium)
                        Button("Open a folder", systemImage: "folder.badge.plus") { opening.toggle() }
                            .buttonStyle(KitButton(kind: .secondary))
                            .accessibilityAddTraits(opening ? .isSelected : [])
                    }
                    if opening {
                        OpenFolderForm(folders: folders(list), busy: projects.busy != nil, cancel: { opening = false }) { folder in
                            screen.press({ await $0.open(folder) }) { outcome in
                                if case .failed = outcome { return }
                                opening = false
                            }
                        }
                    }
                    NoteBanner(text: screen.note)
                    if list.isEmpty {
                        EmptyState(symbol: "folder", title: "No projects yet",
                                   detail: "Open a folder to make it a project, or start an agent in a repository and it appears here with every agent that worked there.")
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: ProjectsLayout.cardWidth), spacing: Memnox.Spacing.large)],
                                  spacing: Memnox.Spacing.large) {
                            // The top bar's switcher narrows the list to the project picked.
                            ForEach(ShellLines.projectsShown(list, current: shell.currentProject)) { each in
                                ProjectCard(project: each, chosen: each.id == shell.inspecting) { shell.inspecting = each.id }
                            }
                        }
                    }
                }
            } detail: {
                if let picked {
                    ProjectInspector(screen: screen, studio: shell.studio, project: picked).id(picked.id)
                }
            }
        } else if projects.unreadable {
            ShellScroll(width: width) { ReadFailed(what: "the projects") { Task { await projects.refresh() } } }
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The folders the sessions ran in that are not projects yet, offered as quick picks to open.
    private func folders(_ list: [ProjectView]) -> [FolderPick] {
        let seen = SeenWorkspaces.from(island.cards, now: Date()).map { FolderPick(path: $0.path, name: $0.name) }
        // The switcher's project comes first, so the form starts on it.
        return ShellLines.withCurrent(ProjectLines.foldersToOpen(seen, projects: list), current: shell.currentProject)
    }
}

private struct ProjectCard: View {
    let project: ProjectView
    let chosen: Bool
    let pick: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
        let standing = ProjectLines.standing(project)
        Button(action: pick) {
            VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
                HStack(spacing: Memnox.Spacing.medium) {
                    Image(systemName: "folder").foregroundStyle(Memnox.Palette.muted).accessibilityHidden(true)
                    Text(project.name)
                        .font(Memnox.sans(Memnox.TextSize.body, .semibold))
                        .foregroundStyle(Memnox.Palette.foreground)
                        .lineLimit(1)
                    Spacer(minLength: Memnox.Spacing.small)
                    ScopeChip(ScopeLines.project(project))
                    if project.sharedBy != nil { OrganizationBadge() } else { StatusWord(Tone(standing.tone), standing.word) }
                }
                Text(project.path)
                    .font(Memnox.mono(Memnox.TextSize.micro))
                    .foregroundStyle(Memnox.Palette.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text([ProjectLines.counted(project.skills.count, "skill", "skills"),
                      ProjectLines.counted(project.servers.count, "server", "servers"),
                      ProjectLines.counted(project.openMissions.count, "open mission", "open missions")].joined(separator: SessionText.separator))
                    .font(Memnox.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Palette.muted)
                    .lineLimit(1)
                HStack {
                    AgentLogos(agents: project.agents)
                    Spacer(minLength: Memnox.Spacing.medium)
                    if let active = project.lastActive.flatMap({ SessionText.ago($0, now: Date()) }) {
                        Text("Active \(active)")
                            .font(Memnox.sans(Memnox.TextSize.footnote))
                            .foregroundStyle(Memnox.Palette.muted)
                    }
                }
            }
            .padding(Memnox.Spacing.xLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Memnox.Palette.card, in: shape)
            .overlay(shape.strokeBorder(chosen ? Memnox.Palette.primary : Memnox.Palette.panelEdge, lineWidth: Memnox.Stroke.hairline))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .pointingHand()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(project.name), \(project.sharedBy == nil ? standing.word : ProjectLines.fromOrganization)")
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }
}

/// The agents' logos overlapping, as the cards and the grants show who has a thing.
private struct AgentLogos: View {
    let agents: [String]

    var body: some View {
        HStack(spacing: ProjectsLayout.overlap) {
            ForEach(agents, id: \.self) { kind in
                BrandLogo(agent: kind, name: McpHubLines.agentLabel(kind), size: ProjectsLayout.logo)
                    .overlay(RoundedRectangle(cornerRadius: ProjectsLayout.logo / 4, style: .continuous)
                        .strokeBorder(Memnox.Palette.card, lineWidth: ProjectsLayout.ring))
            }
        }
    }
}

/// The folder to take in as a project: chosen in Finder's own panel, typed whole, or one the sessions ran in that is
/// not a project yet.
private struct OpenFolderForm: View {
    let folders: [FolderPick]
    let busy: Bool
    let cancel: () -> Void
    let open: (String) -> Void
    @State private var folder = ""
    @State private var problem: String?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            Text("The folder, from the top of the drive")
                .font(Memnox.sans(Memnox.TextSize.footnote, .medium))
                .foregroundStyle(Memnox.Palette.muted)
            HStack(spacing: Memnox.Spacing.medium) {
                TextField("/Users/you/code/project", text: $folder)
                    .kitField()
                    .font(Memnox.mono(Memnox.TextSize.footnote))
                    .onSubmit(go)
                    .accessibilityLabel("The folder to open as a project")
                Button("Choose", systemImage: "folder", action: choose)
                    .buttonStyle(KitButton(kind: .secondary))
                    .help("Pick the folder in Finder")
            }
            if !folders.isEmpty {
                // The folders the sessions ran in, so the usual one is one click away.
                ScrollView(.horizontal) {
                    HStack(spacing: Memnox.Spacing.small) {
                        ForEach(folders, id: \.path) { each in
                            Button(each.name) { folder = each.path }
                                .buttonStyle(KitButton(kind: folder == each.path ? .primary : .secondary))
                                .help(each.path)
                                .accessibilityAddTraits(folder == each.path ? .isSelected : [])
                        }
                    }
                }
                .scrollIndicators(.never)
                .accessibilityLabel("Folders your agents worked in")
            }
            if let problem {
                Text(problem)
                    .font(Memnox.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Palette.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(ProjectLines.openLine)
                .font(Memnox.sans(Memnox.TextSize.footnote))
                .foregroundStyle(Memnox.Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Memnox.Spacing.medium) {
                Button(busy ? "Opening" : "Open", systemImage: "folder.badge.plus", action: go)
                    .buttonStyle(KitButton(kind: .primary))
                    .disabled(busy)
                Button("Cancel", action: cancel).buttonStyle(KitButton(kind: .secondary))
            }
        }
        .padding(Memnox.Spacing.xLarge)
        .background(Memnox.Palette.card, in: shape)
        .overlay(shape.strokeBorder(Memnox.Palette.panelEdge, lineWidth: Memnox.Stroke.hairline))
        .onAppear { if folder.isEmpty, let first = folders.first { folder = first.path } }
    }

    private func go() {
        problem = LaunchLines.folderProblem(folder)
        if problem == nil { open(folder) }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open as a project"
        if !folder.isEmpty { panel.directoryURL = URL(fileURLWithPath: folder) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folder = url.path
        problem = nil
    }
}

/// One project's details, a tab each for what it gives its agents and the rules that hold in it.
private struct ProjectInspector: View {
    @ObservedObject var screen: ProjectsScreen
    let studio: StudioScreen?
    let project: ProjectView
    @State private var tab = "overview"

    private static let tabs = [
        TabInfo(id: "overview", title: "Overview"),
        TabInfo(id: "agents", title: "Agents"),
        TabInfo(id: "skills", title: "Skills"),
        TabInfo(id: "tools", title: "Tools"),
        TabInfo(id: "policies", title: "Policies"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.xLarge) {
            ShellTabBar(tabs: Self.tabs, chosen: tab) { tab = $0 }
            switch tab {
            case "agents": AgentsHere(project: project)
            case "skills": Grants(project: project, grants: project.skills, empty: "This project names no skills.")
            case "tools": Grants(project: project, grants: project.servers, empty: "This project names no MCP servers.")
            case "policies":
                if let studio { PoliciesHere(studio: studio, project: project) } else { Muted(ProjectLines.rulesLine(project.rules)) }
            default: Overview(screen: screen, project: project)
            }
        }
    }
}

/// A quiet line of a project's details.
private struct Muted: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(Memnox.sans(Memnox.TextSize.footnote))
            .foregroundStyle(Memnox.Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct Overview: View {
    @ObservedObject var screen: ProjectsScreen
    let project: ProjectView

    private static let symbols = ["cpu", "sparkles", "server.rack", "checkmark.shield"]

    var body: some View {
        let standing = ProjectLines.standing(project)
        let busy = screen.projects.busy == project.id || screen.projects.busy == project.path
        VStack(alignment: .leading, spacing: Memnox.Spacing.xxLarge) {
            HStack(spacing: Memnox.Spacing.medium) {
                if project.sharedBy != nil { OrganizationBadge() } else { StatusWord(Tone(standing.tone), standing.word) }
                Spacer(minLength: Memnox.Spacing.medium)
                Text(project.path)
                    .font(Memnox.mono(Memnox.TextSize.micro))
                    .foregroundStyle(Memnox.Palette.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(project.path)
            }
            if let problems = project.problems, !problems.isEmpty {
                VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
                    ForEach(problems, id: \.self) { problem in
                        Text(problem)
                            .font(Memnox.sans(Memnox.TextSize.footnote))
                            .foregroundStyle(Memnox.Palette.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Memnox.Spacing.regular), GridItem(.flexible())],
                      spacing: Memnox.Spacing.regular) {
                ForEach(Array(ProjectLines.tiles(project).enumerated()), id: \.offset) { index, tile in
                    StatTile(value: tile.value, label: tile.label, symbol: Self.symbols[index % Self.symbols.count], tint: Memnox.Palette.faint)
                }
            }
            if let organization = project.sharedBy { OrganizationPanel(organization: organization) }
            Muted(ProjectLines.rulesLine(project.rules))
            if let organization = project.sharedBy {
                // The organization's project is changed in Memnox Cloud, so its line stands where Apply and Save would.
                Muted(organization.editedIn)
                    .padding(.horizontal, Memnox.Spacing.xLarge)
                    .padding(.vertical, Memnox.Spacing.large)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Memnox.Palette.card, in: RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous))
            } else {
                editControls(busy: busy)
            }
            NoteBanner(text: screen.note)
            ShellSection(title: "Instructions") {
                if project.instructions.isEmpty {
                    Muted("No instruction file, so its agents get none from this project.")
                } else {
                    ShellPanel {
                        ForEach(Array(project.instructions.enumerated()), id: \.element.path) { index, each in
                            if index > 0 { ShellDivider() }
                            ShellRow(title: each.path,
                                     caption: "\(ProjectLines.instructionWord(each))\(SessionText.separator)\(ProjectLines.readersLine(each.agents))") {
                                Image(systemName: "doc.text").foregroundStyle(Memnox.Palette.muted).accessibilityHidden(true)
                            } trailing: {
                                EmptyView()
                            }
                        }
                    }
                }
            }
            ShellSection(title: "Open missions") {
                if project.openMissions.isEmpty {
                    Muted("No mission is open here.")
                } else {
                    ShellPanel {
                        ForEach(Array(project.openMissions.enumerated()), id: \.element.id) { index, mission in
                            if index > 0 { ShellDivider() }
                            ShellRow(title: mission.statement,
                                     caption: "Started \(SessionText.ago(mission.startedAt, now: Date()) ?? "a while ago")") {
                                EmptyView()
                            } trailing: {
                                EmptyView()
                            }
                        }
                    }
                }
                Muted(ProjectLines.questionsLine(project.openQuestions))
            }
            Muted(ProjectLines.sessionsLine(project, now: Date()))
        }
    }

    /// Apply or Save as project, on the person's own project only.
    @ViewBuilder private func editControls(busy: Bool) -> some View {
        Group {
            if project.declared {
                Button(busy ? "Applying" : "Apply", systemImage: "play") {
                    let id = project.id
                    screen.press { await $0.apply(id) }
                }
            } else {
                Button(busy ? "Saving" : "Save as project", systemImage: "square.and.arrow.down") {
                    let path = project.path, draft = ProjectLines.draft(of: project)
                    screen.press { await $0.put(path, draft: draft) }
                }
            }
        }
        .buttonStyle(KitButton(kind: .primary))
        .disabled(busy)
        Muted(ProjectLines.pressLine(declared: project.declared))
    }
}

/// The badge a project the organization shares carries in place of its standing.
private struct OrganizationBadge: View {
    var body: some View {
        Label(ProjectLines.fromOrganization, systemImage: "building.2")
            .font(Memnox.sans(Memnox.TextSize.footnote, .medium))
            .foregroundStyle(Memnox.Palette.muted)
            .padding(.horizontal, Memnox.Spacing.medium)
            .padding(.vertical, Memnox.Spacing.xSmall)
            .overlay(Capsule().strokeBorder(Memnox.Palette.panelEdge, lineWidth: Memnox.Stroke.hairline))
            .lineLimit(1)
    }
}

/// What the organization hands a shared project, read only: servers, skills, its rule pack, memory, and what was left out.
private struct OrganizationPanel: View {
    let organization: ProjectOrganizationView

    var body: some View {
        ShellSection(title: "From your organization") {
            if let description = organization.description { Muted(description) }
            ShellPanel {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { ShellDivider() }
                    ShellRow(title: row.title, caption: row.caption) { EmptyView() } trailing: { EmptyView() }
                }
            }
            ForEach(organization.skipped, id: \.self) { Muted($0) }
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

/// The agents the project names, then any seen working in it that it does not name.
private struct AgentsHere: View {
    let project: ProjectView

    var body: some View {
        let seenOnly = project.agentsSeen.filter { !project.agents.contains($0) }
        if project.agents.isEmpty, seenOnly.isEmpty {
            Muted("No agent has worked here yet, and the project names none.")
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

/// A skill or a server the project names, with who has it now.
private struct Grants: View {
    let project: ProjectView
    let grants: [ProjectGrantView]
    let empty: String

    var body: some View {
        if grants.isEmpty {
            Muted(empty)
        } else {
            ShellPanel {
                ForEach(Array(grants.enumerated()), id: \.element.name) { index, grant in
                    if index > 0 { ShellDivider() }
                    ShellRow(title: grant.name, caption: ProjectLines.grantLine(grant, of: project.agents.count)) {
                        EmptyView()
                    } trailing: {
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

/// The rules that reach into this project; those holding everywhere are counted, since they are on Policies.
private struct PoliciesHere: View {
    @ObservedObject var studio: StudioScreen
    let project: ProjectView

    var body: some View {
        content.task { await studio.studio.refresh() }
    }

    @ViewBuilder private var content: some View {
        if let view = studio.studio.rules {
            let found = ProjectLines.rules(view.rules, in: project)
            VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
                if found.here.isEmpty {
                    EmptyState(symbol: "doc.text", title: "No rule of its own",
                               detail: "No rule names this folder or comes from its rule file, so the rules of this computer decide here.")
                } else {
                    ShellPanel {
                        ForEach(Array(found.here.enumerated()), id: \.element.name) { index, rule in
                            if index > 0 { ShellDivider() }
                            ShellRow(title: rule.sentence, caption: rule.reason ?? rule.file ?? rule.name) {
                                EmptyView()
                            } trailing: {
                                StatusWord(Tone(effect: rule.effect), StudioLines.title(rule.effect))
                            }
                        }
                    }
                }
                Muted(ProjectLines.everywhereLine(found.everywhere))
            }
        } else if studio.studio.unreadable {
            ReadFailed(what: "the rules") { Task { await studio.studio.refresh() } }
        } else {
            ProgressView().controlSize(.small)
        }
    }
}
