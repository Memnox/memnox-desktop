import MemnoxVoiceCore
import SwiftUI

/// Needs you: what waits on the person, oldest first, each saying exactly what the agent wants to do, and below it
/// what was read from their sources waiting to be confirmed. Every answer goes through the island's own path, so a
/// yes that reaches outside the session is signed with Touch ID exactly as on the island.
struct NeedsYouDestination: View {
    @ObservedObject var shell: AppShellModel
    @ObservedObject var island: IslandModel
    let width: WidthClass

    var body: some View {
        ShellScroll(width: width) {
            HeldCalls(island: island, projects: shell.projects?.projects.projects ?? [],
                      work: shell.supports("agent-work") == true ? shell.work : nil,
                      profiles: shell.profiles?.profiles.profiles ?? [], workspace: shell.workspaceAgents)
            if shell.supports("memory-learn") == true, let memory = shell.memory {
                LearnQueue(screen: memory, island: island)
            }
        }
    }
}

/// The calls held for the person, oldest first, with the agent work and the workspace's handoffs that wait beside them.
private struct HeldCalls: View {
    @ObservedObject var island: IslandModel
    /// The projects on this computer, which name where each call waits.
    let projects: [ProjectView]
    /// Agent work whose handoffs and done claims wait here too, nil where this Mac's runtime keeps none.
    var work: AgentWorkScreen?
    /// The jobs, which name the agent a handoff is from and to.
    var profiles: [ProfileView] = []
    /// The workspace's handoffs, which wait here while the person is signed in.
    var workspace: WorkspaceAgentsScreen?

    var body: some View {
        let waiting = island.waiting.entries
        VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
            NoticesSwitch(notifier: HeldNotifier.shared)
            if let work { WorkNeedingYou(screen: work, names: WorkNames(profiles)) }
            if let workspace { WorkspaceHandoffs(screen: workspace) }
            if waiting.isEmpty {
                if let home = SettingsWindow.shared.home {
                    NothingWaiting(home: home)
                } else {
                    NothingWaiting.empty
                }
            } else {
                Text("\(waiting.count) waiting, oldest first.")
                    .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Console.muted)
                VStack(spacing: Memnox.Spacing.large) {
                    ForEach(waiting, id: \.subject) { entry in
                        HeldCallCard(card: entry.card, project: ProjectContext.projectName(place: entry.card.place, projects: projects), busy: island.answering || island.settledNote != nil) { answer in
                            answerHeld(entry.card, answer)
                        }
                    }
                }
            }
        }
        .task { await readWork() }
    }

    // Read here as well, so a handoff waits on this page even when the agents list was never opened.
    private func readWork() async {
        await work?.desk.refresh()
    }

    /// The same three steps the island's buttons take, so its bookkeeping and Touch ID sheet behave as for a tap there.
    private func answerHeld(_ card: HeldCard, _ answer: HoldAnswer) {
        island.answering = answer != .deny
        island.pressed = card.subject
        island.answer(card, answer)
    }
}

private struct HeldCallCard: View {
    let card: HeldCard
    /// The project it waits in, said first so a person with several projects sees where.
    let project: String?
    let busy: Bool
    let answer: (HoldAnswer) -> Void

    private static let logo: CGFloat = 26

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
        VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
            HStack(spacing: Memnox.Spacing.regular) {
                BrandLogo(agent: card.agent, name: card.who, size: Self.logo)
                Text(card.who)
                    .font(Memnox.Console.sans(Memnox.TextSize.body, .semibold))
                    .foregroundStyle(Memnox.Console.foreground)
                    .lineLimit(1)
                Spacer(minLength: Memnox.Spacing.medium)
                StatusWord(.attention, "Asks first")
            }
            Text(card.what)
                .font(Memnox.Console.sans(Memnox.TextSize.body))
                .foregroundStyle(Memnox.Console.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let impact = card.impact {
                HeldImpactLines(impact: impact, ink: Memnox.Console.foreground, muted: Memnox.Console.muted,
                                font: { Memnox.Console.sans($0, $1) })
            }
            FactList(facts: facts)
            HeldAnswers(size: .card, touchID: card.touchID) { answer($0) }
                .disabled(busy)
        }
        .padding(Memnox.Spacing.xLarge)
        .background(Memnox.Console.card, in: shape)
        .overlay(shape.strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(card.who) asks first")
    }

    private var facts: [(String, String)] {
        var facts: [(String, String)] = []
        if let project { facts.append(("Project", project)) }
        if let why = card.why { facts.append(("Why it asks", why)) }
        facts.append(("Signed", HeldSigning.line(touchID: card.touchID, actionDigest: card.actionDigest)))
        return facts
    }
}

/// Whether a held call the island is not showing is also said by the system; turning it on asks the system once.
private struct NoticesSwitch: View {
    @ObservedObject var notifier: HeldNotifier

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
            Toggle(isOn: $notifier.on) {
                VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                    Text(HeldNotices.title)
                        .font(Memnox.Console.sans(Memnox.TextSize.body, .medium))
                        .foregroundStyle(Memnox.Console.foreground)
                    Text(HeldNotices.detail)
                        .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                        .foregroundStyle(Memnox.Console.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            if notifier.on, notifier.refused {
                StatusWord(.attention, HeldNotices.denied)
            }
        }
    }
}

/// Nothing waits, said only while the runtime answers: with the runtime away nothing could reach this page, so it
/// says that instead and opens Connection, where Check again starts it.
private struct NothingWaiting: View {
    @ObservedObject var home: HomeModel

    static let empty = EmptyState(symbol: "checkmark.shield", title: "Nothing needs you",
                                  detail: "When an agent asks before doing something your rules hold, it waits here and on the island.")

    var body: some View {
        if home.unavailable {
            EmptyState(symbol: "exclamationmark.triangle", title: "The Memnox service is not answering",
                       detail: "Nothing an agent asks can reach you until it runs again.")
            Button("Open Connection", systemImage: "arrow.up.forward") { AppWindow.shared.shell.go(WindowRoute(.machines)) }
                .buttonStyle(KitButton(kind: .secondary))
        } else {
            Self.empty
        }
    }
}
