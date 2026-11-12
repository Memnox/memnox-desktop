import MemnoxVoiceCore
import SwiftUI

/// The end's card of what Memnox can and cannot do: each agent found here with its weakest level as a pill, and the
/// levels the service stated behind one press, so the list never buries the button above it. It shows only what the
/// service said, so it can say less than is true and never more.
struct CoverageCard: View {
    @State private var details = false

    var body: some View {
        KitCard(symbol: "checkmark.shield", title: FirstRunCoverage.title, detail: FirstRunCoverage.lead) {
            if let agents = AppWindow.shared.shell.agents {
                LocalCoverage(screen: agents, details: details)
                Button(details ? FirstRunCoverage.hideDetails : FirstRunCoverage.showDetails,
                       systemImage: details ? "chevron.up" : "chevron.down") {
                    withAnimation(.snappy) { details.toggle() }
                }
                .buttonStyle(.plain)
                .pointingHand()
                .font(Memnox.sans(Memnox.TextSize.footnote, .medium))
                .foregroundStyle(Memnox.Console.primary)
                .padding(.vertical, Memnox.Spacing.regular)
            }
            Text(FirstRunCoverage.cannot)
                .font(Memnox.sans(Memnox.TextSize.footnote))
                .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The agents found on this Mac, each a name and a pill, with what sits at each level under it once asked for.
private struct LocalCoverage: View {
    @ObservedObject var screen: AgentsScreen
    let details: Bool

    private static let logo: CGFloat = 26

    var body: some View {
        let found = screen.agents.agents ?? []
        VStack(alignment: .leading, spacing: 0) {
            if found.isEmpty {
                KitRow(symbol: "desktopcomputer", title: "On this Mac", detail: FirstRunCoverage.nothingFound) { EmptyView() }
            }
            ForEach(Array(found.enumerated()), id: \.element.kind) { index, agent in
                if index > 0 { KitDivider() }
                KitRow(title: agent.name, detail: details ? nil : FirstRunLines.agentDetail(agent),
                       leading: { BrandLogo(agent: agent.kind, name: agent.name, size: Self.logo) }) {
                    if let levels = agent.levels { LevelPill(level: CapabilityLevelLines.headline(levels)) }
                }
                if details, let levels = agent.levels { sentences(levels) }
            }
        }
        .task { await screen.agents.refresh() }
    }

    /// Each level the service stated in a sentence of its own, the full width of the card, so none is squeezed
    /// beside the pill.
    private func sentences(_ levels: CapabilityLevels) -> some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
            ForEach(FirstRunCoverage.lines(levels)) { line in
                Text(line.sentence)
                    .font(Memnox.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, Kit.tileSide + Memnox.Spacing.large)
        .padding(.bottom, Memnox.Spacing.regular)
    }
}
