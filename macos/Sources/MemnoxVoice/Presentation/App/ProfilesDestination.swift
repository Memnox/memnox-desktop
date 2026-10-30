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
}

/// Profiles under Workspaces: a named bundle of skills, servers and a rule pack. Keeping one gives nothing; applying it
/// to an agent raises a proposal for each piece, and each waits for Touch ID on the island.
struct ProfilesDestination: View {
    @ObservedObject var shell: AppShellModel
    @ObservedObject var screen: ProfilesScreen
    let width: WidthClass
    @State private var creating = false

    var body: some View {
        page
            .task {
                await screen.profiles.refresh()
                // The hubs and packs are what a profile is made from, and the agents and projects what it is applied to.
                await shell.skills?.skills.refresh()
                await shell.hub?.hub.refresh()
                await shell.studio?.studio.readPacks()
                await shell.projects?.projects.refresh()
            }
            .sheet(isPresented: $creating) {
                NewProfileSheet(shell: shell, screen: screen) { creating = false }
            }
    }

    @ViewBuilder private var page: some View {
        let profiles = screen.profiles
        if let list = profiles.profiles {
            ShellScroll(width: width) {
                NoteBanner(text: screen.note)
                HStack(alignment: .top, spacing: Memnox.Spacing.regular) {
                    QuietLine("A profile gives nothing until you apply it. Applying it waits for your signature with Touch ID on the island, once for each piece.")
                    Spacer(minLength: Memnox.Spacing.medium)
                    Button { creating = true } label: { Label("New profile", systemImage: "plus") }
                        .buttonStyle(KitButton(kind: .primary))
                }
                if list.isEmpty {
                    EmptyState(symbol: "square.stack.3d.up", title: "No profiles yet",
                               detail: "Bundle the skills, servers and rule pack one kind of work needs, such as Backend Engineering, and apply it to any agent in one go.")
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: ProfilesLayout.cardWidth), spacing: Memnox.Spacing.large)],
                              spacing: Memnox.Spacing.large) {
                        ForEach(list) { profile in
                            ProfileCard(shell: shell, screen: screen, profile: profile)
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
}

private struct ProfileCard: View {
    @ObservedObject var shell: AppShellModel
    @ObservedObject var screen: ProfilesScreen
    let profile: ProfileView
    @State private var applying = false
    @State private var removing = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
        let busy = screen.profiles.busy == profile.id
        VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
            VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                Text(profile.name)
                    .font(Memnox.sans(Memnox.TextSize.headline, .semibold))
                    .foregroundStyle(Memnox.Palette.foreground)
                    .lineLimit(1)
                Text(ProfileLines.contents(profile))
                    .font(Memnox.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Palette.muted)
                    .lineLimit(1)
            }
            if let description = profile.description {
                Text(description)
                    .font(Memnox.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Palette.foreground)
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
        .background(Memnox.Palette.card, in: shape)
        .overlay(shape.strokeBorder(Memnox.Palette.panelEdge, lineWidth: Memnox.Stroke.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(profile.name)
    }

    private func muted(_ text: String) -> some View {
        Text(text)
            .font(Memnox.sans(Memnox.TextSize.footnote))
            .foregroundStyle(Memnox.Palette.muted)
            .lineLimit(1)
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
            Picker("Agent", selection: $agent) {
                ForEach(agents, id: \.agent) { each in Text(each.label).tag(each.agent) }
            }
            HStack(spacing: Memnox.Spacing.medium) {
                TextField("Repository, optional", text: $project)
                    .kitField()
                    .font(Memnox.mono(Memnox.TextSize.footnote))
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

/// A profile chosen from what the Skills Hub, the MCP Hub and the rule packs hold now; keeping it grants nothing.
private struct NewProfileSheet: View {
    @ObservedObject var shell: AppShellModel
    @ObservedObject var screen: ProfilesScreen
    let close: () -> Void
    @State private var form = ProfileForm()
    @State private var problem: String?

    var body: some View {
        let packs = shell.studio?.studio.packs ?? []
        let skills = shell.skills?.skills.hub?.skills.map(\.name) ?? []
        let servers = shell.hub?.hub.hub?.servers.map(\.name) ?? []
        SkillSheetFrame(title: "New profile") {
            labelled("Name") { TextField("Backend Engineering", text: $form.name).kitField() }
            labelled("What it is for, optional") {
                TextField("Reviews, release notes and the local database", text: $form.description).kitField()
            }
            choices("Skills from the Skills Hub", empty: "The Skills Hub holds no skill yet.", names: skills, chosen: $form.skills)
            choices("Servers from the MCP Hub", empty: "The MCP Hub holds no server yet.", names: servers, chosen: $form.servers)
            labelled("Rule pack") {
                Picker("Rule pack", selection: $form.pack) {
                    Text("No rule pack").tag("")
                    ForEach(packs) { pack in
                        Text("\(pack.name), \(ProjectLines.counted(pack.ruleCount, "rule", "rules"))").tag(pack.id)
                    }
                }
                .labelsHidden()
            }
            if let problem {
                Text(problem)
                    .font(Memnox.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Palette.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } footer: {
            Button("Cancel", action: close).buttonStyle(KitButton(kind: .secondary)).keyboardShortcut(.cancelAction)
            Spacer(minLength: Memnox.Spacing.medium)
            Button("Keep profile") { save(packs) }
                .buttonStyle(KitButton(kind: .primary))
                .keyboardShortcut(.defaultAction)
                .disabled(screen.profiles.busy != nil)
        }
    }

    private func save(_ packs: [RulePackView]) {
        switch ProfileLines.draft(form, packs: packs) {
        case .failure(let missing):
            problem = missing.why
        case .success(let draft):
            Task {
                let outcome = await screen.profiles.put(draft)
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
                .font(Memnox.sans(Memnox.TextSize.footnote, .medium))
                .foregroundStyle(Memnox.Palette.muted)
            field()
        }
    }
}
