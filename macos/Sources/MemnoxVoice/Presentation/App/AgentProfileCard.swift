import AppKit
import MemnoxVoiceCore
import SwiftUI

/// One agent: its name, whether Memnox can stop it, who answers for it, each way Memnox reaches it as a pill wearing
/// its level, and the work it carries now. A profile with no agent behind it stays grey and shows no activity.
struct AgentProfileCard: View {
    let profile: ProfileView
    /// The open work its agent carries, newest first; nil where this Mac's runtime keeps no work.
    let work: AgentWork?

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
                    Text(AgentProfileLines.summary(profile))
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
                if let kind = profile.connections.first?.agentKind, let studio = AppWindow.shared.shell.studio {
                    AgentPresetRow(studio: studio, agent: kind)
                }
            } else {
                StatusWord(.quiet, AgentProfileLines.noAgent)
            }
            Spacer(minLength: 0)
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
            Text("How Memnox reaches it")
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

/// Starting this one agent on a shipped pack, and what it was started on; each rule waits for Touch ID on the island.
private struct AgentPresetRow: View {
    @ObservedObject var studio: StudioScreen
    let agent: String
    @State private var note: String?

    var body: some View {
        let packs = studio.studio.packs ?? []
        let started = AgentPresets.started(studio.studio.rules?.rules ?? [], agent: agent, packs: packs)
        VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
            HStack(spacing: Memnox.Spacing.medium) {
                Text(AgentPresets.line(started))
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                    .foregroundStyle(Memnox.Console.muted)
                Spacer(minLength: Memnox.Spacing.small)
                if !packs.isEmpty {
                    Menu(AgentPresets.title) {
                        ForEach(packs.filter { $0.id != started?.id }, id: \.id) { pack in
                            Button(pack.name) { start(pack) }.help(pack.description)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
            if let note {
                Text(note)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                    .foregroundStyle(Memnox.Console.muted)
            }
        }
        .task { await studio.studio.readPacks() }
    }

    private func start(_ pack: RulePackView) {
        Task {
            switch await studio.studio.importPack(pack.toml, agent: agent) {
            case .done, .proposed: note = AgentPresets.waits
            case .failed(let why): note = why
            }
        }
    }
}
