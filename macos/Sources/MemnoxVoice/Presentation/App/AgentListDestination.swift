import MemnoxVoiceCore
import SwiftUI

/// Every agent on this Mac as the runtime sees it, the ones needing a decision first: paused, then not protected, then
/// protected, then dormant. Pausing is at once; resuming gives an agent back its reach, so it waits for Touch ID.
struct AgentListDestination: View {
    @ObservedObject var screen: AgentsScreen
    let home: HomeModel?
    let width: WidthClass

    private static let cardWidth: CGFloat = 300

    var body: some View {
        page.task { await screen.agents.refresh() }
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
                        ForEach(StudioLines.sortedAgents(list)) { agent in
                            AgentCard(screen: screen, home: home, agent: agent)
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

    private static let logo: CGFloat = 30

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
        let standing = StudioLines.statusWord(agent.status)
        VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
            HStack(spacing: Memnox.Spacing.regular) {
                BrandLogo(agent: agent.kind, name: agent.name, size: Self.logo)
                VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                    Text(agent.name)
                        .font(Memnox.sans(Memnox.TextSize.headline, .semibold))
                        .foregroundStyle(Memnox.Palette.foreground)
                        .lineLimit(1)
                    StatusWord(Tone(standing.tone), standing.word)
                }
                Spacer(minLength: 0)
            }
            QuietLine(StudioLines.agentCounts(agent))
            if !agent.mcpServers.isEmpty {
                Text("Servers: \(agent.mcpServers.joined(separator: ", "))")
                    .font(Memnox.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Palette.muted)
                    .lineLimit(1)
            }
            if !agent.recent.isEmpty {
                VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
                    ForEach(agent.recent) { action in
                        HStack(spacing: Memnox.Spacing.medium) {
                            Text(StudioLines.activityLine(operation: action.operation, target: action.target))
                                .font(Memnox.mono(Memnox.TextSize.footnote))
                                .foregroundStyle(Memnox.Palette.foreground)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: Memnox.Spacing.small)
                            if let ago = SessionText.ago(action.at, now: Date()) {
                                Text(ago)
                                    .font(Memnox.sans(Memnox.TextSize.footnote))
                                    .foregroundStyle(Memnox.Palette.muted)
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
                if agent.agentStatus == .unprotected, let home, !home.remote() {
                    ProtectButton(home: home)
                }
            }
        }
        .padding(Memnox.Spacing.xLarge)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Memnox.Palette.card, in: shape)
        .overlay(shape.strokeBorder(Memnox.Palette.panelEdge, lineWidth: Memnox.Stroke.hairline))
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
