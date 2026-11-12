import AppKit
import MemnoxVoiceCore
import SwiftUI

/// One agent as its job: the name and purpose line, who answers for it, each way Memnox reaches it as a pill wearing
/// its level, and the work it carries now. A default profile is the agent itself, offered a job; a profile with no
/// agent behind it stays grey and shows no activity and no numbers.
struct AgentProfileCard: View {
    let profile: ProfileView
    /// The open work its agent carries, newest first; nil where this Mac's runtime keeps no work.
    let work: AgentWork?
    /// Opens the job: a default gets a new job bound to its agent, any other its own job to edit; nil for a job kept
    /// in the workspace, which is edited in the console.
    let giveJob: ((ProfileView) -> Void)?

    private static let logo: CGFloat = 30
    /// How faint a card with nobody behind it is drawn, so it never reads as an agent at work.
    private static let unboundOpacity = 0.7

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ShellMetrics.radius, style: .continuous)
        let bound = profile.hasAgent
        VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
            HStack(spacing: Memnox.Spacing.regular) {
                BrandLogo(agent: profile.connections.first?.agentKind, name: profile.name, size: Self.logo)
                VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                    Text(profile.name)
                        .font(Memnox.Console.sans(Memnox.TextSize.headline, .semibold))
                        .foregroundStyle(Memnox.Console.foreground)
                        .lineLimit(1)
                    Text(AgentProfileLines.purpose(profile))
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                        .foregroundStyle(Memnox.Console.muted)
                        .lineLimit(2)
                }
                Spacer(minLength: Memnox.Spacing.small)
                if bound { LevelPill(level: CapabilityLevelLines.headline(profile.levels)) }
            }
            if let responsible = AgentProfileLines.responsible(profile) {
                Label(responsible, systemImage: "person")
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                    .foregroundStyle(Memnox.Console.muted)
            }
            if bound {
                connections
                if let work { WorkLine(work: work) }
            } else {
                StatusWord(.quiet, AgentProfileLines.noAgent)
            }
            Spacer(minLength: 0)
            if let giveJob {
                Button(profile.isDefault ? AgentProfileLines.giveJob : "Edit the job", systemImage: profile.isDefault ? "briefcase" : "pencil") {
                    giveJob(profile)
                }
                .buttonStyle(KitButton(kind: profile.isDefault ? .primary : .secondary))
            }
        }
        .padding(Memnox.Spacing.xLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Memnox.Console.card, in: shape)
        .overlay(shape.strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
        .opacity(bound ? 1 : Self.unboundOpacity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(profile.name)
    }

    private var connections: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
            Text("Connected through")
                .font(Memnox.Console.sans(Memnox.Console.TextSize.label, .medium))
                .foregroundStyle(Memnox.Console.muted)
            ForEach(AgentProfileLines.shownConnections(profile)) { connection in
                HStack(spacing: Memnox.Spacing.small) {
                    ConnectionPill(connection: connection)
                    Text(CapabilityLevelLines.status(connection))
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                        .foregroundStyle(Memnox.Console.muted)
                        .lineLimit(1)
                }
            }
        }
    }
}

/// The issue an agent carries, its state and its latest word, opening the issue in its tracker where it has a link.
struct WorkLine: View {
    let work: AgentWork

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
            HStack(spacing: Memnox.Spacing.small) {
                Image(systemName: "checklist")
                    .foregroundStyle(Memnox.Console.muted)
                    .accessibilityHidden(true)
                if let link = AgentWorkLines.link(work) {
                    Button(AgentWorkLines.issue(work)) { NSWorkspace.shared.open(link) }
                        .buttonStyle(.link)
                        .help("Open it in \(AgentWorkLines.trackerName(work.target.source))")
                        .lineLimit(1)
                } else {
                    Text(AgentWorkLines.issue(work))
                        .foregroundStyle(Memnox.Console.foreground)
                        .lineLimit(1)
                }
                Spacer(minLength: Memnox.Spacing.small)
                StatusWord(AgentWorkLines.needsYou(work) ? .attention : .quiet, AgentWorkLines.status(work))
            }
            .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
            Text(AgentWorkLines.latest(work))
                .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                .foregroundStyle(Memnox.Console.muted)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }
}
