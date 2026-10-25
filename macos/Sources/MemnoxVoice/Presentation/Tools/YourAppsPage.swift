import MemnoxVoiceCore
import SwiftUI

/// The person's own tools: what this Mac already reaches, what they connected, and the catalogue to connect more,
/// each a card with its mark, its name, one line and its one button. Nothing here asks for a Memnox account.
struct YourAppsPage: View {
    @ObservedObject var tools: ToolsModel

    /// The app asked to be disconnected, held while the person confirms.
    @State private var leaving: YourAppCard?

    private static let columns = [GridItem(.adaptive(minimum: 220), spacing: SettingsMetrics.rowSpacing)]
    private static let refreshSymbol = "arrow.clockwise"
    private static let noteSymbol = "exclamationmark.circle"

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.pageSpacing) {
            SettingsSection(title: "Yours") {
                Button { tools.refresh() } label: { Label("Check again", systemImage: Self.refreshSymbol) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Memnox.Palette.muted)
            } content: {
                VStack(alignment: .leading, spacing: SettingsMetrics.cardSpacing) {
                    yours
                    Text(YourApps.allowanceLine)
                        .font(.system(size: SettingsMetrics.captionSize))
                        .foregroundStyle(Memnox.Palette.muted)
                }
            }
            if let why = tools.actionNote {
                SettingsCard {
                    SettingsRow(symbol: Self.noteSymbol, title: "That did not work", caption: why, tint: Memnox.Palette.warm)
                }
            }
            SettingsSection(title: "Connect an app") {
                Text(YourApps.countLine(tools.offered.count, query: tools.query))
                    .font(.system(size: SettingsMetrics.captionSize))
                    .foregroundStyle(Memnox.Palette.muted)
                    .contentTransition(.numericText())
            } content: {
                VStack(alignment: .leading, spacing: SettingsMetrics.cardSpacing) {
                    SearchField(prompt: "Search apps", text: $tools.query)
                    if let note = tools.searchNote {
                        Text(note)
                            .font(.system(size: SettingsMetrics.captionSize))
                            .foregroundStyle(Memnox.Palette.warm)
                    }
                    grid(tools.offered)
                }
            }
        }
        .onAppear {
            tools.refresh()
            tools.search()
        }
        .onChange(of: tools.query) { tools.search() }
        // Back from the browser's sign in, the list is read again so a tool just connected shows at once.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in tools.refresh() }
        .confirmationDialog(leavingTitle, isPresented: leavingShown, presenting: leaving) { card in
            Button("Disconnect", role: .destructive) { tools.disconnect(card.slug) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Your agents stop working in it as you until you connect it again.")
        }
    }

    @ViewBuilder private var yours: some View {
        let cards = tools.yourApps
        if cards.isEmpty {
            SettingsCard {
                SettingsRow(symbol: "square.grid.2x2", title: tools.loading ? "Reading your apps" : "No apps yet",
                            caption: tools.loading ? nil : (tools.connectionsNote ?? "Connect one below and sign in to it in your browser."))
            }
        } else {
            grid(cards)
        }
    }

    private func grid(_ cards: [YourAppCard]) -> some View {
        LazyVGrid(columns: Self.columns, alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
            ForEach(cards) { card in
                YourAppTile(card: card, busy: tools.busy == card.slug, waiting: tools.waitingFor == card.slug,
                            disabled: tools.busy != nil,
                            connect: { tools.connect(card.slug, again: card.standing == .signInAgain) },
                            disconnect: { leaving = card })
            }
        }
    }

    private var leavingTitle: String { "Disconnect \(leaving?.name ?? "")?" }

    private var leavingShown: Binding<Bool> {
        Binding(get: { leaving != nil }, set: { if !$0 { leaving = nil } })
    }
}

/// One tool's card: its mark, its name, where it stands in one line, and Connect or Disconnect.
private struct YourAppTile: View {
    let card: YourAppCard
    let busy: Bool
    let waiting: Bool
    let disabled: Bool
    let connect: () -> Void
    let disconnect: () -> Void

    private static let markSide: CGFloat = 32
    private static let height: CGFloat = 64
    private static let waitingLine = "Finish signing in in your browser"

    var body: some View {
        HStack(spacing: SettingsMetrics.rowSpacing) {
            ToolMark(toolkit: card.slug, side: Self.markSide)
            VStack(alignment: .leading, spacing: SettingsMetrics.captionSpacing) {
                Text(card.name)
                    .font(.system(size: SettingsMetrics.rowTextSize, weight: .medium))
                    .foregroundStyle(Memnox.Palette.foreground)
                    .lineLimit(1)
                Text(waiting ? Self.waitingLine : card.standing.line)
                    .font(.system(size: SettingsMetrics.captionSize))
                    .foregroundStyle(lineColor)
                    .lineLimit(1)
            }
            Spacer(minLength: Memnox.Spacing.small)
            if busy { ProgressView().controlSize(.small) }
            action
        }
        .padding(.horizontal, SettingsMetrics.cardPadding)
        .frame(height: Self.height)
        .background(Memnox.Palette.card, in: RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var action: some View {
        switch card.standing {
        case .onThisMac:
            EmptyView()
        case .connected:
            Button("Disconnect", action: disconnect)
                .buttonStyle(KitButton(kind: .secondary))
                .disabled(disabled)
        case .signInAgain:
            Button("Sign in", action: connect)
                .buttonStyle(KitButton(kind: .primary))
                .disabled(disabled)
        case .available:
            Button("Connect", action: connect)
                .buttonStyle(KitButton(kind: .secondary))
                .disabled(disabled)
                .accessibilityLabel("Connect \(card.name)")
        }
    }

    private var lineColor: Color {
        switch card.standing {
        case .connected, .onThisMac: Memnox.Palette.success
        case .signInAgain: Memnox.Palette.warm
        case .available: Memnox.Palette.muted
        }
    }
}
