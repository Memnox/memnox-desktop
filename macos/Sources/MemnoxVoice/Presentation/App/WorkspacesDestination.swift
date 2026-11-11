import MemnoxVoiceCore
import SwiftUI

/// Projects as the runtime keeps them, with what each gives the agents opened in it. A runtime too old to answer
/// `projects` still shows every repository a session ran in, with who worked there.
struct WorkspacesDestination: View {
    @ObservedObject var shell: AppShellModel
    @ObservedObject var island: IslandModel
    /// The person's sign in to Memnox Cloud, which decides whether a project shows a team.
    let account: AccountModel?
    let width: WidthClass

    var body: some View {
        if shell.supports("projects") == true, let projects = shell.projects {
            ProjectsDestination(screen: projects, shell: shell, island: island, account: account, width: width)
        } else {
            SeenWorkspacesPage(shell: shell, island: island, width: width)
        }
    }
}

/// Repositories as the sessions met them, for a runtime that does not answer `projects`.
private struct SeenWorkspacesPage: View {
    @ObservedObject var shell: AppShellModel
    @ObservedObject var island: IslandModel
    let width: WidthClass

    private static let cardWidth: CGFloat = 260

    var body: some View {
        let workspaces = SeenWorkspaces.from(island.cards, now: Date())
        let picked = workspaces.first { $0.path == shell.inspecting }
        InspectorLayout(width: width, title: picked?.name, close: { shell.inspecting = nil }) {
            ShellScroll(width: width) {
                if workspaces.isEmpty {
                    EmptyState(symbol: "folder", title: "No projects yet",
                               detail: "A project appears once an agent works in a repository on this Mac, with every agent that has worked there.")
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.cardWidth), spacing: Memnox.Spacing.large)],
                              spacing: Memnox.Spacing.large) {
                        ForEach(workspaces) { each in
                            WorkspaceCard(workspace: each, chosen: each.path == shell.inspecting) { shell.inspecting = each.path }
                        }
                    }
                }
            }
        } detail: {
            if let picked { WorkspaceOverview(workspace: picked) { shell.go(WindowRoute(.agents, tab: "agents")) } }
        }
    }
}

private struct WorkspaceCard: View {
    let workspace: SeenWorkspace
    let chosen: Bool
    let pick: () -> Void

    private static let logo: CGFloat = 20
    private static let overlap: CGFloat = -6
    private static let ring: CGFloat = 2

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
        Button(action: pick) {
            VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
                HStack(spacing: Memnox.Spacing.medium) {
                    Image(systemName: "folder").foregroundStyle(Memnox.Console.muted).accessibilityHidden(true)
                    Text(workspace.name)
                        .font(Memnox.Console.sans(Memnox.TextSize.body, .semibold))
                        .foregroundStyle(Memnox.Console.foreground)
                        .lineLimit(1)
                }
                Text(workspace.path)
                    .font(Memnox.Console.sans(Memnox.TextSize.micro))
                    .foregroundStyle(Memnox.Console.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack {
                    HStack(spacing: Self.overlap) {
                        ForEach(workspace.agents, id: \.kind) { agent in
                            BrandLogo(agent: agent.kind, name: agent.name, size: Self.logo)
                                .overlay(RoundedRectangle(cornerRadius: Self.logo / 4, style: .continuous)
                                    .strokeBorder(Memnox.Console.card, lineWidth: Self.ring))
                        }
                    }
                    Spacer(minLength: Memnox.Spacing.medium)
                    if let ago = workspace.lastActive {
                        Text("Active \(ago)")
                            .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                            .foregroundStyle(Memnox.Console.muted)
                    }
                }
            }
            .padding(Memnox.Spacing.xLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Memnox.Console.card, in: shape)
            .overlay(shape.strokeBorder(chosen ? Memnox.Console.primary : Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .pointingHand()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(workspace.name)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }
}

private struct WorkspaceOverview: View {
    let workspace: SeenWorkspace
    let sessions: () -> Void

    private static let logo: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.xxLarge) {
            HStack(spacing: Memnox.Spacing.regular) {
                StatTile(value: workspace.agents.count, label: workspace.agents.count == 1 ? "Agent" : "Agents",
                         symbol: "cpu", tint: Memnox.Console.faint)
                StatTile(value: workspace.sessions, label: workspace.sessions == 1 ? "Session" : "Sessions",
                         symbol: "text.bubble", tint: Memnox.Console.faint)
            }
            ShellSection(title: "Agents that worked here") {
                VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
                    ForEach(workspace.agents, id: \.kind) { agent in
                        HStack(spacing: Memnox.Spacing.regular) {
                            BrandLogo(agent: agent.kind, name: agent.name, size: Self.logo)
                            Text(agent.name)
                                .font(Memnox.Console.sans(Memnox.TextSize.body))
                                .foregroundStyle(Memnox.Console.foreground)
                        }
                    }
                }
            }
            GoLink("Its sessions", action: sessions)
            Text("Last active \(SessionText.ago(workspace.lastActiveAt, now: Date()) ?? "a while ago").")
                .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                .foregroundStyle(Memnox.Console.muted)
        }
    }
}
