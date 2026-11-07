import AppKit
import MemnoxVoiceCore
import SwiftUI

/// The workspace's agents for the views, redrawn whenever they change.
@MainActor
final class WorkspaceAgentsScreen: ObservableObject {
    let agents: WorkspaceAgents
    @Published private(set) var tick = 0
    @Published var note: String?

    init(agents: WorkspaceAgents) {
        self.agents = agents
        agents.changed = { [weak self] in
            Task { @MainActor [weak self] in self?.tick += 1 }
        }
    }
}

/// In your workspace: the jobs Memnox Cloud keeps, for agents hosted elsewhere, drawn as the cards on this Mac are.
/// Shown only while the person is signed in, so with no account the list here is the whole of it.
struct WorkspaceAgentsSection: View {
    @ObservedObject var screen: WorkspaceAgentsScreen

    var body: some View {
        let remote = screen.agents.remote
        let profiles = remote.flatMap(\.profiles)
        Group {
            if screen.agents.signedIn, !profiles.isEmpty {
                let work = remote.flatMap(\.work)
                ShellSection(title: "In your workspace") {
                    QuietLine("Agents Memnox Cloud reaches beyond this Mac. Edit their jobs in the console.")
                    EqualRowsGrid(items: AgentProfileLines.ordered(profiles), cardWidth: AgentGridMetrics.cardWidth) { profile in
                        AgentProfileCard(profile: profile, work: AgentWorkLines.current(for: profile.id, in: work), giveJob: nil)
                    }
                }
            }
        }
        .task { await screen.agents.refresh() }
    }
}

/// The workspace's handoffs waiting on the person, for Needs your attention, each answered through the workspace.
struct WorkspaceHandoffs: View {
    @ObservedObject var screen: WorkspaceAgentsScreen

    var body: some View {
        let waiting = screen.agents.remote.flatMap { each in
            each.work.compactMap { work in work.waitingHandoff.map { (workspace: each.workspace, work: work, handoff: $0) } }
        }
        let names = WorkNames(screen.agents.remote.flatMap(\.profiles))
        Group {
            if !waiting.isEmpty {
                ShellSection(title: "In your workspace \u{00B7} \(waiting.count)") {
                    NoteBanner(text: screen.note)
                    VStack(spacing: Memnox.Spacing.large) {
                        ForEach(waiting, id: \.handoff.id) { each in
                            HandoffCard(screen: screen, workspace: each.workspace, work: each.work, handoff: each.handoff, names: names)
                        }
                    }
                }
            }
        }
        .task { if screen.agents.signedIn { await screen.agents.refresh() } }
    }
}

private struct HandoffCard: View {
    @ObservedObject var screen: WorkspaceAgentsScreen
    let workspace: String
    let work: AgentWork
    let handoff: WorkHandoff
    let names: WorkNames

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            WorkLine(work: work)
            Text(AgentWorkLines.handoffLine(handoff, profileName: names.name))
                .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                .foregroundStyle(Memnox.Console.foreground)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Memnox.Spacing.medium) {
                Button("Accept") { answer(.accept) }.buttonStyle(KitButton(kind: .primary))
                Button("Decline") { answer(.decline) }.buttonStyle(KitButton(kind: .secondary))
            }
            .disabled(screen.agents.busy != nil)
        }
        .padding(Memnox.Spacing.xLarge)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Memnox.Console.card, in: shape)
        .overlay(shape.strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AgentWorkLines.issue(work))
    }

    private func answer(_ word: HandoffAnswerWord) {
        Task {
            switch await screen.agents.answer(handoff.id, in: workspace, word) {
            case .done(let line): screen.note = line
            case .failed(let why): screen.note = why
            }
        }
    }
}
