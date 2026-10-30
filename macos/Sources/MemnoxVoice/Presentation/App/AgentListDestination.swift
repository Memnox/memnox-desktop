import AppKit
import MemnoxVoiceCore
import SwiftUI

/// Every agent on this Mac as the runtime sees it, the ones needing a decision first: paused, then not protected, then
/// protected, then dormant. Pausing is at once; resuming gives an agent back its reach, so it waits for Touch ID.
struct AgentListDestination: View {
    @ObservedObject var screen: AgentsScreen
    /// The sessions lately, whose workspaces are the folders offered to launch an agent in.
    @ObservedObject var island: IslandModel
    let home: HomeModel?
    /// Profiles to apply as an agent opens, nil where this Mac's runtime keeps none.
    var profiles: ProfilesScreen?
    /// The project the top bar's switcher picked, which the launch form starts on.
    var current: ProjectView?
    let width: WidthClass
    @State private var launching: String?

    private static let cardWidth: CGFloat = 300

    var body: some View {
        page.task {
            await screen.agents.refresh()
            await profiles?.profiles.refresh()
        }
    }

    @ViewBuilder private var page: some View {
        let agents = screen.agents
        if let list = agents.agents {
            ShellScroll(width: width) {
                NoteBanner(text: screen.note)
                if list.isEmpty {
                    EmptyState(symbol: "cpu", title: "No agents found yet",
                               detail: "Install Claude Code, Codex, Cursor or another agent and it appears here.")
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.cardWidth), spacing: Memnox.Spacing.large)],
                              spacing: Memnox.Spacing.large) {
                        let seen = SeenWorkspaces.from(island.cards, now: Date()).map { FolderPick(path: $0.path, name: $0.name) }
                        let folders = ShellLines.withCurrent(seen, current: current)
                        ForEach(StudioLines.sortedAgents(list)) { agent in
                            AgentCard(screen: screen, home: home, agent: agent, folders: folders,
                                      profiles: profiles?.profiles.profiles ?? [], launching: $launching)
                        }
                    }
                }
            }
        } else if agents.unreadable {
            ShellScroll(width: width) { ReadFailed(what: "the agents") { Task { await agents.refresh() } } }
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct AgentCard: View {
    @ObservedObject var screen: AgentsScreen
    let home: HomeModel?
    let agent: AgentStanding
    let folders: [FolderPick]
    let profiles: [ProfileView]
    /// The one card whose Launch form is open, by agent kind.
    @Binding var launching: String?

    private static let logo: CGFloat = 30

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
        let standing = StudioLines.statusWord(agent.status)
        VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
            HStack(spacing: Memnox.Spacing.regular) {
                BrandLogo(agent: agent.kind, name: agent.name, size: Self.logo)
                VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                    Text(agent.name)
                        .font(Memnox.Console.sans(Memnox.TextSize.headline, .semibold))
                        .foregroundStyle(Memnox.Console.foreground)
                        .lineLimit(1)
                    StatusWord(Tone(standing.tone), standing.word)
                }
                Spacer(minLength: 0)
            }
            QuietLine(StudioLines.agentCounts(agent))
            if !agent.mcpServers.isEmpty {
                Text("Servers: \(agent.mcpServers.joined(separator: ", "))")
                    .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Console.muted)
                    .lineLimit(1)
            }
            if let skills = agent.skills, !skills.isEmpty {
                Text("Skills: \(skills.joined(separator: ", "))")
                    .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Console.muted)
                    .lineLimit(1)
            }
            if !agent.recent.isEmpty {
                VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
                    ForEach(agent.recent) { action in
                        HStack(spacing: Memnox.Spacing.medium) {
                            Text(StudioLines.activityLine(operation: action.operation, target: action.target))
                                .font(Memnox.Console.code(Memnox.TextSize.footnote))
                                .foregroundStyle(Memnox.Console.foreground)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: Memnox.Spacing.small)
                            if let ago = SessionText.ago(action.at, now: Date()) {
                                Text(ago)
                                    .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                                    .foregroundStyle(Memnox.Console.muted)
                            }
                            StatusWord(Tone(effect: action.effect), StudioLines.title(action.effect))
                        }
                    }
                }
            }
            HStack(spacing: Memnox.Spacing.medium) {
                let busy = screen.agents.busy == agent.kind
                if agent.agentStatus == .paused {
                    Button { screen.press { await $0.resume(agent.kind) } } label: { Label("Resume", systemImage: "play.fill") }
                        .buttonStyle(KitButton(kind: .secondary))
                        .disabled(busy)
                        .help("Lets it carry on once you confirm with Touch ID")
                } else {
                    Button { screen.press { await $0.pause(agent.kind) } } label: { Label("Pause", systemImage: "pause.fill") }
                        .buttonStyle(KitButton(kind: .secondary))
                        .disabled(busy)
                        .help("Holds everything it tries until you resume it")
                }
                if agent.canLaunch, launching != agent.kind {
                    Button { launching = agent.kind } label: { Label("Launch", systemImage: "apple.terminal") }
                        .buttonStyle(KitButton(kind: .secondary))
                        .help("Opens it in a new terminal in a folder you choose")
                }
                if agent.agentStatus == .unprotected, let home, !home.remote() {
                    ProtectButton(home: home)
                }
            }
            if launching == agent.kind {
                LaunchForm(folders: folders, profiles: profiles, busy: screen.agents.busy == Agents.launching(agent.kind)) {
                    launching = nil
                } launch: { folder, profile in
                    let kind = agent.kind
                    Task {
                        let outcome = await screen.agents.launch(kind, in: folder, profile: profile)
                        screen.note = StudioNotes.line(outcome, proposed: "Waiting for you on the island: confirm it with Touch ID.")
                        if case .failed = outcome { return }
                        launching = nil
                    }
                }
            }
        }
        .padding(Memnox.Spacing.xLarge)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Memnox.Console.card, in: shape)
        .overlay(shape.strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(agent.name)
    }
}

/// The home's own Protect press, which hooks every agent found on this Mac into Memnox the way setup does.
private struct ProtectButton: View {
    @ObservedObject var home: HomeModel

    var body: some View {
        Button(home.protecting ? "Protecting" : "Protect", action: home.protect)
            .buttonStyle(KitButton(kind: .primary))
            .disabled(home.protecting)
            .help("Hooks every agent found on this Mac into Memnox, the way setup does")
    }
}

/// The folder an agent opens in, chosen in Finder's own panel, typed whole or one of the workspaces its sessions ran in,
/// and a profile to apply first.
private struct LaunchForm: View {
    let folders: [FolderPick]
    let profiles: [ProfileView]
    let busy: Bool
    let cancel: () -> Void
    let launch: (String, String?) -> Void
    @State private var folder = ""
    @State private var profile = ""
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            ShellDivider()
            Text("Open it in")
                .font(Memnox.Console.sans(Memnox.TextSize.footnote, .medium))
                .foregroundStyle(Memnox.Console.muted)
            HStack(spacing: Memnox.Spacing.medium) {
                TextField("/Users/you/code/project", text: $folder)
                    .kitField()
                    .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                    .onSubmit(go)
                    .accessibilityLabel("The folder it opens in")
                Button("Choose", systemImage: "folder", action: choose)
                    .buttonStyle(KitButton(kind: .secondary))
                    .help("Pick the folder in Finder")
            }
            if !folders.isEmpty {
                // The workspaces as quick picks, so the usual folder is one click away.
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
                .accessibilityLabel("Your workspaces")
            }
            if !profiles.isEmpty {
                Picker("With a profile", selection: $profile) {
                    Text("No profile").tag("")
                    ForEach(profiles) { each in Text(each.name).tag(each.id) }
                }
                if !profile.isEmpty { QuietLine("What the profile gives waits for your signature on the island as the agent opens.") }
            }
            if let problem {
                Text(problem)
                    .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Console.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Memnox.Spacing.medium) {
                Button(busy ? "Opening" : "Open a terminal", systemImage: "apple.terminal", action: go)
                    .buttonStyle(KitButton(kind: .primary))
                    .disabled(busy)
                Button("Cancel", action: cancel).buttonStyle(KitButton(kind: .secondary))
            }
        }
        .onAppear { if folder.isEmpty, let first = folders.first { folder = first.path } }
    }

    private func go() {
        problem = LaunchLines.folderProblem(folder)
        if problem == nil { launch(folder, profile.isEmpty ? nil : profile) }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Open here"
        if !folder.isEmpty { panel.directoryURL = URL(fileURLWithPath: folder) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folder = url.path
        problem = nil
    }
}
