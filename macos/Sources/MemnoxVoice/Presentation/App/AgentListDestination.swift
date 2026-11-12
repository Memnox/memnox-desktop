import AppKit
import MemnoxVoiceCore
import SwiftUI

/// Every agent on this Mac as the runtime sees it: a summary with filters on top, a strip naming any agent running
/// outside Memnox with the one Protect press, then the cards, the ones needing a decision first, in rows that line up.
/// Pausing is at once; resuming gives an agent back its reach, so it waits for Touch ID.
struct AgentListDestination: View {
    @ObservedObject var screen: AgentsScreen
    /// The sessions lately, whose workspaces are the folders offered to launch an agent in.
    @ObservedObject var island: IslandModel
    let home: HomeModel?
    /// Profiles to apply as an agent opens, nil where this Mac's runtime keeps none.
    var profiles: ProfilesScreen?
    /// The project the top bar's switcher picked, which the launch form starts on.
    var current: ProjectView?
    /// The work each agent carries, nil where this Mac's runtime keeps none.
    var work: AgentWorkScreen?
    /// The agents Memnox Cloud reaches, shown only while the person is signed in.
    var workspace: WorkspaceAgentsScreen?
    /// Opens a profile's job, from Give it a job or Edit the job on its card.
    var giveJob: (ProfileView) -> Void = { _ in }
    let width: WidthClass
    @State private var launching: String?
    @State private var filter = AgentFilter.all

    var body: some View {
        page.task {
            await screen.agents.refresh()
            await profiles?.profiles.refresh()
            await work?.desk.refresh()
        }
    }

    @ViewBuilder private var page: some View {
        let agents = screen.agents
        if let list = agents.agents {
            ShellScroll(width: width) {
                NoteBanner(text: screen.note)
                if let profiles { ProfileCards(profiles: profiles, work: work, giveJob: giveJob) }
                if let workspace { WorkspaceAgentsSection(screen: workspace) }
                if list.isEmpty {
                    EmptyState(symbol: "cpu", title: "No agents found yet",
                               detail: "Install Claude Code, Codex, Cursor or another agent and it appears here.")
                } else {
                    AgentsHeader(list: list, filter: $filter)
                    if let open = AgentLines.needsProtecting(list) {
                        NeedsYouStrip(screen: screen, line: open, kinds: AgentLines.unprotectedKinds(list), home: home)
                    }
                    let shown = AgentLines.shown(list, filter)
                    if shown.isEmpty {
                        QuietLine(AgentLines.noneShown(filter))
                    } else {
                        let seen = SeenWorkspaces.from(island.cards, now: Date()).map { FolderPick(path: $0.path, name: $0.name) }
                        EqualRowsGrid(items: shown, cardWidth: AgentGridMetrics.cardWidth) { agent in
                            AgentStandingCard(screen: screen, agent: agent, home: home, folders: ShellLines.withCurrent(seen, current: current),
                                      profiles: profiles?.profiles.profiles ?? [], launching: $launching)
                        }
                    }
                }
            }
            // A filter that no agent is in any more, after a protect or a resume, falls back to all of them.
            .onChange(of: AgentLines.filters(list)) { _, offered in
                if !offered.contains(filter) { filter = .all }
            }
        } else if agents.unreadable {
            ShellScroll(width: width) { ReadFailed(what: "the agents") { Task { await agents.refresh() } } }
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The agents as their jobs, over the connections Memnox reaches them through, from a runtime that sends connections;
/// an older one sends none, and the cards of what was found stand alone as before.
private struct ProfileCards: View {
    @ObservedObject var profiles: ProfilesScreen
    let work: AgentWorkScreen?
    let giveJob: (ProfileView) -> Void

    var body: some View {
        let kept = profiles.profiles.profiles ?? []
        if kept.contains(where: { $0.hasAgent || $0.isDefault }) {
            ShellSection(title: "Your agents") {
                if let work {
                    WorkingProfiles(profiles: kept, work: work, giveJob: giveJob)
                } else {
                    ProfileGrid(profiles: kept, work: [], giveJob: giveJob)
                }
            }
        }
    }
}

/// Redrawn as work changes, so a card's current issue and its latest word stay fresh.
private struct WorkingProfiles: View {
    let profiles: [ProfileView]
    @ObservedObject var work: AgentWorkScreen
    let giveJob: (ProfileView) -> Void

    var body: some View {
        ProfileGrid(profiles: profiles, work: work.desk.work ?? [], giveJob: giveJob)
    }
}

struct ProfileGrid: View {
    let profiles: [ProfileView]
    let work: [AgentWork]
    let giveJob: (ProfileView) -> Void

    var body: some View {
        EqualRowsGrid(items: AgentProfileLines.ordered(profiles), cardWidth: AgentGridMetrics.cardWidth) { profile in
            AgentProfileCard(profile: profile, work: AgentWorkLines.current(for: profile.id, in: work), giveJob: giveJob)
        }
    }
}

/// How many agents there are and how many are protected and running, with chips to narrow the cards to some of them.
private struct AgentsHeader: View {
    let list: [AgentStanding]
    @Binding var filter: AgentFilter

    var body: some View {
        HStack(alignment: .center, spacing: Memnox.Spacing.large) {
            Text(AgentLines.summary(list))
                .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
                .foregroundStyle(Memnox.Console.muted)
                .lineLimit(1)
            Spacer(minLength: Memnox.Spacing.medium)
            HStack(spacing: Memnox.Spacing.small) {
                ForEach(AgentLines.filters(list)) { each in
                    FilterChip(title: each.title, chosen: filter == each, count: AgentLines.count(list, each)) { filter = each }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Show")
        }
    }
}

/// The agents running outside Memnox, named in amber with the one Protect press, since that is the thing to act on.
private struct NeedsYouStrip: View {
    @ObservedObject var screen: AgentsScreen
    let line: String
    /// The agents it names, which its Protect press is for.
    let kinds: [String]
    let home: HomeModel?

    /// The strip's amber edge and wash, a little stronger than a pill's so it reads as the page's call to act.
    private static let edge = 0.45
    private static let wash = 0.08

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
        HStack(spacing: Memnox.Spacing.large) {
            Image(systemName: "exclamationmark.shield")
                .font(Memnox.Console.sans(Memnox.Console.TextSize.base, .medium))
                .foregroundStyle(Memnox.Console.warm)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                HStack(spacing: Memnox.Spacing.small) {
                    NamedAgentLogos(agents: kinds)
                    Text(line)
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .semibold))
                        .foregroundStyle(Memnox.Console.foreground)
                }
                // What the last press came to stands in for the reminder, since it is the newer thing to read.
                if let result = screen.protectResult, kinds.contains(where: result.covers) {
                    ProtectResultLine(result: result, screen: screen, home: home)
                } else {
                    Text("Outside Memnox, nothing an agent tries is ruled on.")
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                        .foregroundStyle(Memnox.Console.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Memnox.Spacing.medium)
            if let home, !home.remote() { ProtectButton(home: home, screen: screen, kinds: kinds) }
        }
        .padding(.horizontal, ShellMetrics.rowPaddingH)
        .padding(.vertical, ShellMetrics.rowPaddingV)
        .background(Memnox.Console.warm.opacity(Self.wash), in: shape)
        .overlay(shape.strokeBorder(Memnox.Console.warm.opacity(Self.edge), lineWidth: Memnox.Stroke.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Needs you")
    }
}

/// Cards in as many columns as fit, each row top aligned and every card in it as tall as the tallest, which a lazy
/// grid does not do; a card fills its cell with a frame whose height is unbounded.
struct EqualRowsGrid<Item: Identifiable, Card: View>: View {
    let items: [Item]
    /// The narrowest a card reads well at, which sets how many columns fit.
    let cardWidth: CGFloat
    @ViewBuilder let card: (Item) -> Card
    @State private var available: CGFloat = 0

    var body: some View {
        let columns = max(1, Int((available + Memnox.Spacing.large) / (cardWidth + Memnox.Spacing.large)))
        let rows = stride(from: 0, to: items.count, by: columns).map { Array(items[$0 ..< min($0 + columns, items.count)]) }
        Grid(alignment: .topLeading, horizontalSpacing: Memnox.Spacing.large, verticalSpacing: Memnox.Spacing.large) {
            ForEach(rows, id: \.first?.id) { row in
                GridRow(alignment: .top) {
                    ForEach(row) { card($0) }
                    // Empty cells keep a short last row's cards as wide as the rows above it.
                    ForEach(row.count ..< columns, id: \.self) { _ in Color.clear.gridCellUnsizedAxes(.vertical) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GeometryReader { geometry in
            Color.clear
                .onAppear { available = geometry.size.width }
                .onChange(of: geometry.size.width) { _, now in available = now }
        })
    }
}

/// The agent grid's measure.
enum AgentGridMetrics {
    /// The narrowest a card reads well at, its name, pill and numbers on their lines.
    static let cardWidth: CGFloat = 300
}

/// The home's own Protect press, which hooks every agent found on this Mac into Memnox the way setup does, then reads
/// the cards again so the ones it was pressed for show what it came to. It waits while a press or a restart runs.
struct ProtectButton: View {
    @ObservedObject var home: HomeModel
    @ObservedObject var screen: AgentsScreen
    /// The agents this press is for, whose cards and strip report the result.
    let kinds: [String]

    var body: some View {
        let busy = home.protecting || home.restarting
        Button { screen.protect(kinds, with: home) } label: {
            HStack(spacing: Memnox.Spacing.small) {
                if home.protecting { ProgressView().controlSize(.small) }
                Text(home.protecting ? "Protecting" : "Protect")
            }
        }
        .buttonStyle(KitButton(kind: .primary))
        .disabled(busy)
        .help("Puts every agent found on this Mac under Memnox the way setup does")
    }
}

/// What a Protect press came to, in green once the agents are held and in amber while something keeps one outside,
/// with when it was read and the one step the app can take for the person where there is one.
struct ProtectResultLine: View {
    let result: ProtectResult
    @ObservedObject var screen: AgentsScreen
    let home: HomeModel?

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
            Label {
                Text(lineWithTime)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } icon: {
                Image(systemName: result.held ? "checkmark.shield" : "exclamationmark.triangle")
                    .accessibilityHidden(true)
            }
            .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
            .foregroundStyle(result.held ? Memnox.Console.success : Memnox.Console.warm)
            if let home, let followUp = result.followUp { followUpButton(followUp, home: home) }
        }
    }

    private var lineWithTime: String {
        guard let at = result.at else { return result.line }
        return "\(result.line) \u{00B7} \(at.formatted(date: .omitted, time: .shortened))"
    }

    @ViewBuilder private func followUpButton(_ followUp: ProtectFollowUp, home: HomeModel) -> some View {
        switch followUp {
        case .restartService:
            RestartServiceButton(home: home, screen: screen, kinds: result.kinds)
        }
    }
}

/// Rebuilds and restarts the Memnox service the way Update does, for a service too old to see an agent is held.
private struct RestartServiceButton: View {
    @ObservedObject var home: HomeModel
    @ObservedObject var screen: AgentsScreen
    let kinds: [String]

    var body: some View {
        Button { screen.restartService(kinds, with: home) } label: {
            HStack(spacing: Memnox.Spacing.small) {
                if home.restarting { ProgressView().controlSize(.small) }
                Text(home.restarting ? "Restarting Memnox service" : "Restart Memnox service")
            }
        }
        .buttonStyle(KitButton(kind: .secondary))
        .disabled(home.restarting || home.protecting)
        .help("Starts the Memnox service again on the newest runtime on this Mac, then reads your agents again")
    }
}
