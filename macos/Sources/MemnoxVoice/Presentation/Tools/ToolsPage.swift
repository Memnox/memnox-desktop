import MemnoxVoiceCore
import SwiftUI

/// The agents on this Mac and the person's connected apps, each a row in Vorssaint's card with its own logo for a tile.
struct ToolsPage: View {
    @ObservedObject var tools: ToolsModel

    @State private var adding = false
    /// The app asked to be disconnected, held while the person confirms.
    @State private var leaving: ToolConnection?

    private static let refreshSymbol = "arrow.clockwise"
    private static let noteSymbol = "person.crop.circle.badge.exclamationmark"
    private static let addSymbol = "plus"
    private static let chevronSymbol = "chevron.right"

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
                } else {
                    if tools.connections.isEmpty {
                        SettingsRow(symbol: "link", title: tools.loading ? "Reading your apps" : "No apps connected yet",
                                    caption: tools.loading ? nil : "Add any app you use and Memnox can work in it for you.")
                    } else {
                        ForEach(tools.connections) { connection in
                            if connection.id != tools.connections.first?.id { SettingsDivider() }
                            ToolRow(title: ToolkitName.of(connection.toolkit), caption: caption(connection), ok: connection.connected) {
                                ToolMark(toolkit: connection.toolkit, side: SettingsMetrics.tileSide)
                            } accessory: {
                                actions(connection)
                            }
                        }
                    }
                    SettingsDivider()
                    addRow
                }
                if let why = tools.actionNote {
                    SettingsRow(symbol: Self.noteSymbol, title: "That did not work", caption: why, tint: Memnox.Palette.warm)
                }
            }
            HStack {
                Spacer()
                Button { tools.refresh() } label: { Label("Check again", systemImage: Self.refreshSymbol) }
            }
        }
        .onAppear { tools.refresh() }
        // Back from the browser's sign in, the list is read again so a tool just connected shows at once.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in tools.refresh() }
        .sheet(isPresented: $adding) { AddAppSheet(tools: tools, done: { adding = false }) }
        .confirmationDialog(leavingTitle, isPresented: leavingShown, presenting: leaving) { connection in
            Button("Disconnect", role: .destructive) { tools.disconnect(connection.toolkit) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Memnox stops working in it for you until you connect it again.")
        }
    }

    private var addRow: some View {
        Button { adding = true } label: {
            SettingsRow(symbol: Self.addSymbol, title: "Add an app", caption: "Search every app Memnox can connect to and sign in with your own account.") {
                Image(systemName: Self.chevronSymbol).foregroundStyle(Memnox.Palette.muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverLight()
        .disabled(tools.busy != nil)
    }

    private func caption(_ connection: ToolConnection) -> String {
        if tools.waitingFor == connection.toolkit { return "Finish signing in in your browser" }
        return ToolStatus.connection(connection)
    }

    @ViewBuilder private func actions(_ connection: ToolConnection) -> some View {
        HStack(spacing: Memnox.Spacing.medium) {
            if tools.busy == connection.toolkit {
                ProgressView().controlSize(.small)
            }
            if !connection.connected {
                Button("Sign in again") { tools.connect(connection.toolkit, again: true) }
                    .buttonStyle(KitButton(kind: .primary))
            }
            Button("Disconnect") { leaving = connection }
                .buttonStyle(KitButton(kind: .secondary))
        }
        .disabled(tools.busy != nil)
    }

    private var leavingTitle: String {
        "Disconnect \(ToolkitName.of(leaving?.toolkit ?? ""))?"
    }

    private var leavingShown: Binding<Bool> {
        Binding(get: { leaving != nil }, set: { if !$0 { leaving = nil } })
    }
}

/// The catalogue searched as the person types, each tool one press from its own sign in.
struct AddAppSheet: View {
    @ObservedObject var tools: ToolsModel
    let done: () -> Void

    private static let width: CGFloat = 420
    private static let listHeight: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.cardSpacing) {
            Text("Add an app")
                .font(.system(size: SettingsMetrics.sectionTitleSize, weight: .semibold))
                .foregroundStyle(Memnox.Palette.foreground)
                .accessibilityAddTraits(.isHeader)
            Text("Pick the app and sign in to it in your browser. Nobody else has to approve it.")
                .font(.system(size: SettingsMetrics.captionSize))
                .foregroundStyle(Memnox.Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            SearchField(prompt: "Search apps", text: $tools.query)
            ScrollView {
                VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
                    if let note = tools.searchNote {
                        SettingsRow(symbol: "exclamationmark.circle", title: "The apps are not showing", caption: note, tint: Memnox.Palette.warm)
                    } else if tools.found.isEmpty {
                        Text(tools.searching ? "Looking" : "No app by that name")
                            .font(.system(size: SettingsMetrics.captionSize))
                            .foregroundStyle(Memnox.Palette.muted)
                    }
                    ForEach(tools.found) { toolkit in
                        Button {
                            tools.connect(toolkit.slug)
                            done()
                        } label: {
                            HStack(spacing: SettingsMetrics.rowSpacing) {
                                ToolMark(toolkit: toolkit.slug, side: SettingsMetrics.tileSide)
                                Text(toolkit.name)
                                    .font(.system(size: SettingsMetrics.rowTextSize))
                                    .foregroundStyle(Memnox.Palette.foreground)
                                Spacer(minLength: SettingsMetrics.rowSpacing)
                            }
                            .padding(.vertical, Memnox.Spacing.xSmall)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .hoverLight()
                        .accessibilityLabel("Connect \(toolkit.name)")
                    }
                }
                .padding(.horizontal, SettingsMetrics.hoverInset)
            }
            .frame(height: Self.listHeight)
            HStack {
                Spacer()
                Button("Done", action: done).buttonStyle(KitButton(kind: .secondary))
            }
        }
        .padding(SettingsMetrics.cardPadding)
        .frame(width: Self.width)
        .background(Memnox.Palette.card)
        .onAppear { tools.search() }
        .onChange(of: tools.query) { tools.search() }
    }
}

/// A tool's row: its own logo where a Settings row has its tile, its name, and how it stands in green or orange.
struct ToolRow<Mark: View, Accessory: View>: View {
    let title: String
    let caption: String
    let ok: Bool
    @ViewBuilder let mark: Mark
    @ViewBuilder let accessory: Accessory

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
            accessory
            Circle()
                .fill(ok ? Memnox.Palette.success : Memnox.Palette.warm)
                .frame(width: toolRowDotSide, height: toolRowDotSide)
                .accessibilityLabel(ok ? "Working" : "Needs you")
        }
        .accessibilityElement(children: .contain)
    }
}

extension ToolRow where Accessory == EmptyView {
    init(title: String, caption: String, ok: Bool, @ViewBuilder mark: () -> Mark) {
        self.init(title: title, caption: caption, ok: ok, mark: mark) { EmptyView() }
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
