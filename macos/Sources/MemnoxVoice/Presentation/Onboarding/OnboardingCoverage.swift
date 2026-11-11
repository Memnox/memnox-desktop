import MemnoxVoiceCore
import SwiftUI

/// The end's card of what Memnox can and cannot do, in the five plain levels: each agent found here with the levels
/// the service stated, and the agent the person said runs elsewhere. It shows only
/// what the service said, so it can say less than is true and never more.
struct CoverageCard: View {
    @ObservedObject var flow: OnboardingFlow

    var body: some View {
        KitCard(symbol: "checkmark.shield", title: FirstRunCoverage.title, detail: FirstRunCoverage.lead) {
            if let agents = AppWindow.shared.shell.agents {
                LocalCoverage(screen: agents)
            }
            if let place = flow.place, !place.isLocal, place != .noneYet {
                KitDivider()
                KitRow(symbol: "cloud", title: place.title, detail: FirstRunCoverage.place(place)) {
                    LevelPill(level: .noEvidence)
                }
            }
            KitDivider()
            Text(FirstRunCoverage.cannot)
                .font(Memnox.sans(Memnox.TextSize.footnote))
                .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Memnox.Spacing.regular)
        }
    }
}

/// The agents found on this Mac, each with its weakest level as a pill and what sits at each level under it.
private struct LocalCoverage: View {
    @ObservedObject var screen: AgentsScreen

    private static let logo: CGFloat = 26

    var body: some View {
        let found = screen.agents.agents ?? []
        VStack(alignment: .leading, spacing: 0) {
            if found.isEmpty {
                KitRow(symbol: "desktopcomputer", title: "On this Mac", detail: FirstRunQuestions.nothingFound) { EmptyView() }
            }
            ForEach(Array(found.enumerated()), id: \.element.kind) { index, agent in
                if index > 0 { KitDivider() }
                KitRow(title: agent.name, detail: detail(agent),
                       leading: { BrandLogo(agent: agent.kind, name: agent.name, size: Self.logo) }) {
                    if let levels = agent.levels { LevelPill(level: CapabilityLevelLines.headline(levels)) }
                }
            }
        }
        .task { await screen.agents.refresh() }
    }

    /// Each level the service stated for it in a sentence, or, from a service that states none, what it said instead.
    private func detail(_ agent: AgentStanding) -> String {
        guard let levels = agent.levels else { return FirstRunLines.agentDetail(agent) }
        return FirstRunCoverage.lines(levels).map(\.sentence).joined(separator: " ")
    }
}
