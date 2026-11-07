import AppKit
import MemnoxVoiceCore
import SwiftUI

/// Profiles for the views: redrawn whenever the core's profiles change, with the line the last press ended in.
@MainActor
final class ProfilesScreen: ObservableObject {
    let profiles: Profiles
    /// Bumped when the profiles change, so every view reading them is drawn again.
    @Published private(set) var tick = 0
    /// What the last press came to, shown above the page until the next one.
    @Published var note: String?

    init(profiles: Profiles) {
        self.profiles = profiles
        profiles.changed = { [weak self] in
            Task { @MainActor [weak self] in self?.tick += 1 }
        }
    }

    func said(_ outcome: ProfileOutcome) {
        switch outcome {
        case .done(let line): note = line
        case .failed(let why): note = why
        }
    }
}

private enum ProfilesLayout {
    static let cardWidth: CGFloat = 280
    /// How faint a template is drawn, so a job with no agent behind it never reads as an agent at work.
    static let templateOpacity = 0.75
}

/// The profile editor under AI agents: each job with who answers for it and the agents it works through, an agent's
/// default offered a job, and the templates, which are jobs with no agent behind them. Keeping or binding one grants
/// nothing; applying one raises a proposal for each piece, and each waits for Touch ID on the island.
struct ProfilesDestination: View {
    @ObservedObject var shell: AppShellModel
    @ObservedObject var screen: ProfilesScreen
    let width: WidthClass
    @State private var creating = false
    /// The job being given to an agent's default, opened from Give it a job.
    @State private var givingJob: ProfileView?
    @State private var template: ProfileTemplate?

    var body: some View {
        page
            .task {
                await screen.profiles.refresh()
                await screen.profiles.readTemplates()
                // The hubs and packs are what a profile is made from, and the agents and projects what it is applied to.
                await shell.skills?.skills.refresh()
                await shell.hub?.hub.refresh()
                await shell.studio?.studio.readPacks()
                await shell.projects?.projects.refresh()
                await shell.agents?.agents.refresh()
                openAsked()
            }
            .consoleSheet(isPresented: $creating) {
                ProfileSheet(shell: shell, screen: screen) { creating = false }
            }
            .consoleSheet(isPresented: Binding(get: { givingJob != nil }, set: { if !$0 { givingJob = nil } })) {
                if let givingJob {
                    ProfileSheet(shell: shell, screen: screen, jobFor: givingJob) { self.givingJob = nil }
                }
            }
            .consoleSheet(isPresented: Binding(get: { template != nil }, set: { if !$0 { template = nil } })) {
                if let template { TemplateSheet(screen: screen, template: template) { self.template = nil } }
            }
    }

    /// Give it a job on an agent's card names the profile it was pressed on, opened here once it is read.
    private func openAsked() {
        guard let asked = shell.jobFor else { return }
        shell.jobFor = nil
        guard let profile = screen.profiles.profiles?.first(where: { $0.id == asked }) else { return }
        if profile.isDefault { givingJob = profile }
    }

    @ViewBuilder private var page: some View {
        let profiles = screen.profiles
        if let list = profiles.profiles {
            let kept = AgentProfileLines.ordered(list.filter { !$0.isDefault })
            let defaults = list.filter(\.isDefault)
            ShellScroll(width: width) {
                NoteBanner(text: screen.note)
                HStack(alignment: .top, spacing: Memnox.Spacing.regular) {
                    QuietLine("A job gives nothing until you apply it. Applying it waits for your signature with Touch ID on the island, once for each piece.")
                    Spacer(minLength: Memnox.Spacing.medium)
                    Button { creating = true } label: { Label("New job", systemImage: "plus") }
                        .buttonStyle(KitButton(kind: .primary))
                }
                if kept.isEmpty && defaults.isEmpty {
                    EmptyState(symbol: "briefcase", title: "No jobs yet",
                               detail: "Write what an agent is for, who answers for it and what it needs, or start from a template below.")
                }
                if !kept.isEmpty {
                    ShellSection(title: "Jobs") { grid(kept) { ProfileCard(shell: shell, screen: screen, profile: $0) } }
                }
                if !defaults.isEmpty {
                    ShellSection(title: "Agents with no job yet") {
                        grid(defaults) { profile in
                            AgentProfileCard(profile: profile, work: nil) { givingJob = $0 }
                        }
                    }
                }
                if let templates = profiles.templates, !templates.isEmpty {
                    ShellSection(title: "Start from a template") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: ProfilesLayout.cardWidth), spacing: Memnox.Spacing.large)],
                                  spacing: Memnox.Spacing.large) {
                            ForEach(templates) { each in TemplateCard(template: each) { template = each } }
                        }
                    }
                }
            }
        } else if profiles.unreadable {
            ShellScroll(width: width) { ReadFailed(what: "the profiles") { Task { await profiles.refresh() } } }
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func grid<Card: View>(_ profiles: [ProfileView], @ViewBuilder card: @escaping (ProfileView) -> Card) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: ProfilesLayout.cardWidth), spacing: Memnox.Spacing.large)],
                  spacing: Memnox.Spacing.large) {
            ForEach(profiles) { card($0) }
        }
    }
}

/// A job description with no agent behind it, drawn grey with no activity and no numbers.
private struct TemplateCard: View {
    let template: ProfileTemplate
    let use: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            HStack(spacing: Memnox.Spacing.medium) {
                Text(template.name)
                    .font(Memnox.Console.sans(Memnox.TextSize.headline, .semibold))
                    .foregroundStyle(Memnox.Console.foreground)
                    .lineLimit(1)
                Spacer(minLength: Memnox.Spacing.small)
                StatusWord(.quiet, AgentProfileLines.noAgent)
            }
            Text(template.purpose)
                .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                .foregroundStyle(Memnox.Console.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Use this job", systemImage: "doc.on.doc", action: use).buttonStyle(KitButton(kind: .secondary))
        }
        .padding(Memnox.Spacing.xLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Memnox.Console.card, in: shape)
        .overlay(shape.strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
        .opacity(ProfilesLayout.templateOpacity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(template.name), \(AgentProfileLines.noAgent)")
    }
}

/// Copying a template: name the copy and tick the suggested skills to take. The suggested rules are shown in plain
/// words for the person to write as rules later; none is applied by the copy.
private struct TemplateSheet: View {
    @ObservedObject var screen: ProfilesScreen
    let template: ProfileTemplate
    let close: () -> Void
    @State private var name = ""
    @State private var skills: Set<String> = []
    @State private var problem: String?

    var body: some View {
        SkillSheetFrame(title: "Use \(template.name)") {
            labelled("Name") { TextField(template.name, text: $name).kitField() }
            labelled("What it is for") { QuietLine(template.purpose) }
            if !template.responsibilities.isEmpty {
                labelled("Responsibilities") { QuietLine(template.responsibilities.joined(separator: "\n")) }
            }
            if !template.suggestedSkills.isEmpty {
                labelled("Suggested skills, each off until you take it") {
                    VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
                        ForEach(template.suggestedSkills, id: \.self) { skill in
                            Toggle(skill, isOn: Binding(get: { skills.contains(skill) }, set: { on in
                                if on { skills.insert(skill) } else { skills.remove(skill) }
                            }))
                            .toggleStyle(CheckboxStyle())
                        }
                    }
                }
            }
            if !template.suggestedRules.isEmpty {
                labelled("Suggested rules, none applied") {
                    QuietLine(template.suggestedRules.joined(separator: "\n"))
                }
            }
            QuietLine("The copy has no agent behind it yet. Bind one of your agents to it once it is kept.")
            if let problem {
                Text(problem)
                    .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Console.destructive)
            }
        } footer: {
            Button("Cancel", action: close).buttonStyle(KitButton(kind: .secondary)).keyboardShortcut(.cancelAction)
            Spacer(minLength: Memnox.Spacing.medium)
            Button("Keep the job") {
                Task {
                    let outcome = await screen.profiles.fromTemplate(template.id, named: name.isEmpty ? template.name : name,
                                                                     skills: template.suggestedSkills.filter(skills.contains))
                    if case .failed(let why) = outcome {
                        problem = why
                        return
                    }
                    screen.said(outcome)
                    close()
                }
            }
            .buttonStyle(KitButton(kind: .primary))
            .keyboardShortcut(.defaultAction)
            .disabled(screen.profiles.busy != nil)
        }
    }
}

/// A form field under its label, as every sheet here lays them.
private func labelled<Field: View>(_ label: String, @ViewBuilder field: () -> Field) -> some View {
    VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
        Text(label)
            .font(Memnox.Console.sans(Memnox.TextSize.footnote, .medium))
            .foregroundStyle(Memnox.Console.muted)
        field()
    }
}

private struct ProfileCard: View {
    @ObservedObject var shell: AppShellModel
    @ObservedObject var screen: ProfilesScreen
    let profile: ProfileView
    @State private var applying = false
    @State private var removing = false
    @State private var editing = false
    @State private var binding = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
        let busy = screen.profiles.busy == profile.id
        VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
            VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                HStack(spacing: Memnox.Spacing.medium) {
                    Text(profile.name)
                        .font(Memnox.Console.sans(Memnox.TextSize.headline, .semibold))
                        .foregroundStyle(Memnox.Console.foreground)
                        .lineLimit(1)
                    Spacer(minLength: Memnox.Spacing.small)
                    ScopeChip(ScopeLines.profile)
                }
                Text(AgentProfileLines.purpose(profile))
                    .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Console.muted)
                    .lineLimit(2)
            }
            if let responsible = AgentProfileLines.responsible(profile) { muted(responsible) }
            if !profile.responsibilities.isEmpty { muted(profile.responsibilities.joined(separator: ", ")) }
            JobConnections(screen: screen, profile: profile)
            muted(ProfileLines.contents(profile))
            if let description = profile.description, description != profile.purpose {
                Text(description)
                    .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Console.foreground)
                    .lineLimit(2)
            }
            if !profile.skills.isEmpty { muted("Skills: \(profile.skills.joined(separator: ", "))") }
            if !profile.mcpServers.isEmpty { muted("Servers: \(profile.mcpServers.joined(separator: ", "))") }
            ForEach(profile.missing, id: \.self) { missing in StatusWord(.attention, missing) }
            ShellDivider()
            HStack(spacing: Memnox.Spacing.medium) {
                if !applying {
                    Button("Apply", systemImage: "play") { applying = true }.buttonStyle(KitButton(kind: .secondary))
                }
                Button("Edit", systemImage: "pencil") { editing = true }.buttonStyle(KitButton(kind: .secondary))
                if !binding {
                    Button("Bind an agent", systemImage: "link") { binding = true }.buttonStyle(KitButton(kind: .secondary))
                }
                if removing {
                    Button("Remove \(profile.name)", systemImage: "trash") {
                        let id = profile.id
                        Task { screen.said(await screen.profiles.remove(id)) }
                    }
                    .buttonStyle(KitButton(kind: .primary))
                    .disabled(busy)
                    Button("Cancel") { removing = false }.buttonStyle(KitButton(kind: .secondary))
                } else {
                    Button("Remove", systemImage: "trash") { removing = true }.buttonStyle(KitButton(kind: .secondary))
                }
            }
            if removing { QuietLine("What it already gave stays where it was given.") }
            if binding {
                BindForm(shell: shell, busy: busy) { binding = false } bind: { agent in
                    let id = profile.id
                    Task {
                        let outcome = await screen.profiles.bind(id, agent: agent)
                        screen.said(outcome)
                        if case .done = outcome { binding = false }
                    }
                }
            }
            if applying {
                ApplyForm(shell: shell, busy: busy) { applying = false } apply: { agent, project in
                    let id = profile.id
                    Task {
                        let outcome = await screen.profiles.apply(id, agent: agent, project: project)
                        screen.said(outcome)
                        if case .failed = outcome { return }
                        applying = false
                    }
                }
            }
        }
        .padding(Memnox.Spacing.xLarge)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Memnox.Console.card, in: shape)
        .overlay(shape.strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(profile.name)
        .consoleSheet(isPresented: $editing) {
            ProfileSheet(shell: shell, screen: screen, editing: profile) { editing = false }
        }
    }

    private func muted(_ text: String) -> some View {
        Text(text)
            .font(Memnox.Console.sans(Memnox.TextSize.footnote))
            .foregroundStyle(Memnox.Console.muted)
            .lineLimit(1)
    }
}

/// The agents a job works through, each with its level and an Unbind press, and the strip of how sure Memnox is.
private struct JobConnections: View {
    @ObservedObject var screen: ProfilesScreen
    let profile: ProfileView
    @State private var levels = false

    var body: some View {
        if profile.hasAgent {
            VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
                ForEach(AgentProfileLines.shownConnections(profile)) { connection in
                    HStack(spacing: Memnox.Spacing.small) {
                        ConnectionPill(connection: connection)
                        Text(CapabilityLevelLines.status(connection))
                            .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                            .foregroundStyle(Memnox.Console.muted)
                            .lineLimit(1)
                        Spacer(minLength: Memnox.Spacing.small)
                        if let agent = connection.agentId ?? connection.agentKind {
                            Button("Unbind") {
                                let id = profile.id
                                Task { screen.said(await screen.profiles.unbind(agent: agent, from: id)) }
                            }
                            .buttonStyle(KitButton(kind: .secondary))
                            .help("Puts the agent back on its own default, with no job")
                            .disabled(screen.profiles.busy != nil)
                        }
                    }
                }
                DisclosureGroup("How sure Memnox is", isExpanded: $levels) { CapabilityStrip(levels: profile.levels) }
                    .font(Memnox.Console.sans(Memnox.TextSize.footnote, .medium))
                    .foregroundStyle(Memnox.Console.muted)
            }
        } else {
            StatusWord(.quiet, AgentProfileLines.noAgent)
        }
    }
}

/// An agent found on this Mac to put under the job; its record keeps its own key, so nothing it did is renamed.
private struct BindForm: View {
    @ObservedObject var shell: AppShellModel
    let busy: Bool
    let cancel: () -> Void
    let bind: (String) -> Void
    @State private var agent = ""

    var body: some View {
        let found = shell.agents?.agents.agents ?? []
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            ShellDivider()
            if found.isEmpty {
                QuietLine("No agent is found on this Mac yet. Install one and it appears here.")
            } else {
                ConsoleSelect(label: "Agent", selection: $agent, options: found.map { SelectOption(value: $0.kind, title: $0.name) })
            }
            HStack(spacing: Memnox.Spacing.medium) {
                Button(busy ? "Binding" : "Bind", systemImage: "link") { bind(agent) }
                    .buttonStyle(KitButton(kind: .primary))
                    .disabled(busy || agent.isEmpty)
                Button("Cancel", action: cancel).buttonStyle(KitButton(kind: .secondary))
            }
        }
        .onAppear { if agent.isEmpty, let first = found.first { agent = first.kind } }
    }
}

/// The agent a profile goes to and the repository its skills are written into, or the agent's home folder.
private struct ApplyForm: View {
    @ObservedObject var shell: AppShellModel
    let busy: Bool
    let cancel: () -> Void
    let apply: (String, String) -> Void
    @State private var agent = ""
    @State private var project = ""

    var body: some View {
        let agents = shell.skills?.skills.hub?.agents.filter(\.installed) ?? []
        let projects = shell.projects?.projects.projects ?? []
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            ShellDivider()
            ConsoleSelect(label: "Agent", selection: $agent, options: agents.map { SelectOption(value: $0.agent, title: $0.label) })
            HStack(spacing: Memnox.Spacing.medium) {
                TextField("Repository, optional", text: $project)
                    .kitField()
                    .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                    .accessibilityLabel("The repository its skills are written into")
                Button("Choose", systemImage: "folder", action: choose)
                    .buttonStyle(KitButton(kind: .secondary))
                    .help("Pick the repository in Finder")
            }
            if !projects.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: Memnox.Spacing.small) {
                        ForEach(projects) { each in
                            Button(each.name) { project = project == each.path ? "" : each.path }
                                .buttonStyle(KitButton(kind: project == each.path ? .primary : .secondary))
                                .help(each.path)
                                .accessibilityAddTraits(project == each.path ? .isSelected : [])
                        }
                    }
                }
                .scrollIndicators(.never)
                .accessibilityLabel("Your projects")
            }
            QuietLine(ProfileLines.applyWhere(project))
            HStack(spacing: Memnox.Spacing.medium) {
                Button(busy ? "Applying" : "Apply to \(agent.isEmpty ? "the agent" : McpHubLines.agentLabel(agent))", systemImage: "play") {
                    apply(agent, project)
                }
                .buttonStyle(KitButton(kind: .primary))
                .disabled(busy || agent.isEmpty)
                Button("Cancel", action: cancel).buttonStyle(KitButton(kind: .secondary))
            }
        }
        .onAppear { if agent.isEmpty, let first = agents.first { agent = first.agent } }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Apply here"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        project = url.path
    }
}

/// A profile chosen from what the Skills Hub, the MCP Hub and the rule packs hold now, new or as kept when `editing`;
/// saving grants nothing. An edit keeps the name, since the runtime finds a profile by it and a new name is a new profile.
private struct ProfileSheet: View {
    @ObservedObject var shell: AppShellModel
    @ObservedObject var screen: ProfilesScreen
    var editing: ProfileView?
    /// An agent's default given a job: the job is kept and the agent bound to it in one press.
    var jobFor: ProfileView?
    let close: () -> Void
    @State private var form = ProfileForm()
    @State private var problem: String?
    @State private var opened = false

    var body: some View {
        let packs = shell.studio?.studio.packs ?? []
        let skills = ProfileLines.choiceNames(shell.skills?.skills.hub?.skills.map(\.name) ?? [], kept: Set(editing?.skills ?? []))
        let servers = ProfileLines.choiceNames(shell.hub?.hub.hub?.servers.map(\.name) ?? [], kept: Set(editing?.mcpServers ?? []))
        SkillSheetFrame(title: editing.map { "Edit \($0.name)" } ?? jobFor.map { "Give \($0.name) a job" } ?? "New job") {
            if let editing {
                labelled("Name") { Text(editing.name).font(Memnox.Console.sans(Memnox.TextSize.body)).foregroundStyle(Memnox.Console.foreground) }
                QuietLine("The name stays, since a new name would keep a second profile beside this one.")
            } else {
                labelled("Name") { TextField("Backend Engineering", text: $form.name).kitField() }
            }
            labelled("What it is for") {
                TextField("Builds and changes code in the repositories it is given", text: $form.purpose).kitField()
            }
            labelled("Role, optional") { TextField("developer", text: $form.role).kitField() }
            labelled("Responsibilities, one a line") {
                TextField("Run the tests before handing back", text: $form.responsibilities, axis: .vertical)
                    .lineLimit(2...5)
                    .kitField()
            }
            labelled("Instructions, optional") {
                TextField("What it should always do", text: $form.instructions, axis: .vertical)
                    .lineLimit(2...5)
                    .kitField()
            }
            labelled("Who answers for it") { TextField("Your name", text: $form.responsiblePerson).kitField() }
            QuietLine("The agent never holds that person's authority; what it asks goes to them first.")
            choices("Skills from the Skills Hub", empty: "The Skills Hub holds no skill yet.", names: skills, chosen: $form.skills)
            choices("Servers from the MCP Hub", empty: "The MCP Hub holds no server yet.", names: servers, chosen: $form.servers)
            labelled("Rule pack") {
                ConsoleSelect(label: "Rule pack", selection: $form.pack,
                              options: [SelectOption(value: "", title: "No rule pack")] + packs.map { pack in
                                  SelectOption(value: pack.id, title: "\(pack.name), \(ProjectLines.counted(pack.ruleCount, "rule", "rules"))")
                              })
            }
            if let editing, let change = ProfileLines.packChange(kept: editing.rulePack, form: form, packs: packs) {
                QuietLine(change)
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
            Button(editing == nil ? (jobFor == nil ? "Keep job" : "Give it this job") : "Save changes") { save(packs) }
                .buttonStyle(KitButton(kind: .primary))
                .keyboardShortcut(.defaultAction)
                .disabled(screen.profiles.busy != nil)
        }
        .onAppear {
            // Opened once with the profile as kept, so a redraw never undoes what the person changed.
            guard !opened else { return }
            opened = true
            if let editing { form = ProfileLines.form(of: editing, packs: packs) }
            if let jobFor { form = ProfileLines.job(for: jobFor) }
        }
    }

    private func save(_ packs: [RulePackView]) {
        switch ProfileLines.draft(form, packs: packs) {
        case .failure(let missing):
            problem = missing.why
        case .success(let draft):
            let agent = jobFor?.connections.first?.agentId ?? jobFor?.connections.first?.agentKind
            Task {
                let outcome: ProfileOutcome
                if let agent {
                    outcome = await screen.profiles.putAndBind(draft, agent: agent)
                } else {
                    outcome = await screen.profiles.put(draft, editing: editing != nil)
                }
                if case .failed(let why) = outcome {
                    problem = why
                    return
                }
                screen.said(outcome)
                close()
            }
        }
    }

    private func choices(_ title: String, empty: String, names: [String], chosen: Binding<Set<String>>) -> some View {
        labelled(title) {
            if names.isEmpty {
                QuietLine(empty)
            } else {
                VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
                    ForEach(names, id: \.self) { name in
                        Toggle(name, isOn: Binding(get: { chosen.wrappedValue.contains(name) }, set: { on in
                            if on { chosen.wrappedValue.insert(name) } else { chosen.wrappedValue.remove(name) }
                        }))
                        .toggleStyle(CheckboxStyle())
                    }
                }
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
