import MemnoxVoiceCore
import SwiftUI

/// The agents on this Mac and the person's connected apps, each a row in Vorssaint's card with its own logo for a tile.
struct ToolsPage: View {
    @ObservedObject var tools: ToolsModel

    private static let refreshSymbol = "arrow.clockwise"
    private static let noteSymbol = "person.crop.circle.badge.exclamationmark"

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.pageSpacing) {
            SettingsCard(title: "Agents") {
                if tools.agents.isEmpty {
                    SettingsRow(symbol: "terminal", title: tools.loading ? "Looking for agents" : "No agents found",
                                caption: tools.loading ? nil : "Install Claude Code, Codex or Cursor and Memnox finds it.")
                } else {
                    ForEach(tools.agents) { agent in
                        if agent.id != tools.agents.first?.id { SettingsDivider() }
                        ToolRow(title: agent.label, caption: agent.because ?? ToolStatus.agent(agent), ok: agent.works != false) {
                            AgentMark(kind: agent.kind, name: agent.label, side: SettingsMetrics.tileSide)
                        }
                    }
                }
            }
            SettingsCard(title: "Apps") {
                if let note = tools.connectionsNote {
                    SettingsRow(symbol: Self.noteSymbol, title: "Your apps are not showing", caption: note, tint: Memnox.Palette.warm)
                } else if tools.connections.isEmpty {
                    SettingsRow(symbol: "link", title: tools.loading ? "Reading your apps" : "No apps connected yet",
                                caption: tools.loading ? nil : "Ask Memnox to do something in Gmail, Slack or GitHub and it opens the sign in for you.")
                } else {
                    ForEach(tools.connections) { connection in
                        if connection.id != tools.connections.first?.id { SettingsDivider() }
                        ToolRow(title: ToolkitName.of(connection.toolkit), caption: ToolStatus.connection(connection), ok: connection.connected) {
                            ToolMark(toolkit: connection.toolkit, side: SettingsMetrics.tileSide)
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button { tools.refresh() } label: { Label("Check again", systemImage: Self.refreshSymbol) }
            }
        }
        .onAppear { tools.refresh() }
    }
}

/// A tool's row: its own logo where a Settings row has its tile, its name, and how it stands in green or orange.
struct ToolRow<Mark: View>: View {
    let title: String
    let caption: String
    let ok: Bool
    @ViewBuilder let mark: Mark

    var body: some View {
        HStack(spacing: SettingsMetrics.rowSpacing) {
            mark
            VStack(alignment: .leading, spacing: SettingsMetrics.captionSpacing) {
                Text(title).font(.body).foregroundStyle(Memnox.Palette.foreground)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(Memnox.Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: SettingsMetrics.rowSpacing)
            Circle()
                .fill(ok ? Memnox.Palette.success : Memnox.Palette.warm)
                .frame(width: toolRowDotSide, height: toolRowDotSide)
                .accessibilityLabel(ok ? "Working" : "Needs you")
        }
        .accessibilityElement(children: .combine)
    }
}

/// The status dot at a tool row's end, kept outside the row because a generic type cannot hold a static one.
private let toolRowDotSide: CGFloat = 7

/// An agent's logo on a tile of its own colour, the agent's tile wherever tools are listed.
struct AgentMark: View {
    let kind: String
    let name: String
    let side: CGFloat

    /// The logo fills a little over half the tile, as a Settings tile's symbol does.
    private static let logoShare: CGFloat = 0.58
    private static let cornerShare: CGFloat = 0.26

    var body: some View {
        AgentLogo(kind: kind, name: name)
            .frame(width: side * Self.logoShare, height: side * Self.logoShare)
            .frame(width: side, height: side)
            .background(IslandPalette.color(kind), in: RoundedRectangle(cornerRadius: side * Self.cornerShare, style: .continuous))
            .accessibilityHidden(true)
    }
}
