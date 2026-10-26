import MemnoxVoiceCore
import SwiftUI

/// The person's own tools in the console's connectors layout: Connected, Recommended and All as tabs over a categories
/// rail, one search and one grid of the console's cards. Connecting needs a Memnox Cloud account, so while the daemon
/// says nobody is signed in the page leads with that step and Connect starts the app's own sign in. The console's
/// Pull history and enable switch are left out: they act on a workspace's team sources, and the daemon has no call
/// that does either for the person's own apps.
struct YourAppsPage: View {
    @ObservedObject var tools: ToolsModel

    /// The app asked to be disconnected, held while the person confirms.
    @State private var leaving: YourAppCard?
    /// Nil until somebody picks, so the page opens where something is, as the console's does.
    @State private var chosenTab: YourAppsTab?
    /// The folded tag the rail narrows to, nil for every toolkit.
    @State private var category: String?

    private enum Layout {
        /// Wide enough that a name, its pill and a full width Connect never crowd, three across in the page's column.
        static let cardMinimum: CGFloat = 240
        static let gridSpacing: CGFloat = 16
        static let railWidth: CGFloat = 200
        static let railSpacing: CGFloat = 24
        static let railRowSpacing: CGFloat = 2
        static let railRowPadH: CGFloat = 10
        static let railRowPadV: CGFloat = 6
        /// The console shows about twenty before the rest are folded away.
        static let railLeading = 20
    }

    private static let refreshSymbol = "arrow.clockwise"
    /// The console's unplug, as its disconnect dialog draws it.
    private static let disconnectSymbol = "powerplug"
    private static let emptySymbol = "square.grid.2x2"
    private static let signInSymbol = "person.crop.circle.badge.plus"
    private static let columns = [GridItem(.adaptive(minimum: Layout.cardMinimum), spacing: Layout.gridSpacing, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.pageSpacing) {
            HStack(alignment: .center, spacing: Memnox.Spacing.large) {
                InspectorTabs(tabs: YourAppsTab.allCases.map { (id: $0.rawValue, title: title($0)) },
                              chosen: tab.rawValue,
                              choose: { chosenTab = YourAppsTab(rawValue: $0) })
                Button { tools.refresh() } label: { Label("Check again", systemImage: Self.refreshSymbol) }
                    .buttonStyle(.plain)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
                    .foregroundStyle(Memnox.Console.muted)
                    .pointingHand()
                    .fixedSize()
            }
            if tools.signInNeeded { signInStep }
            if let note = pageNote {
                YourAppNoteView(note: note, dismiss: tools.dismissNote)
            }
            HStack(alignment: .top, spacing: Layout.railSpacing) {
                if !categories.isEmpty { rail }
                VStack(alignment: .leading, spacing: SettingsMetrics.pageSpacing) {
                    HStack(spacing: Memnox.Spacing.large) {
                        SearchField(prompt: tab == .all ? "Search every app you can connect" : "Search these apps", text: $tools.query)
                        Text(YourApps.showingLine(shown.count, of: pool.count))
                            .font(Memnox.Console.code(Memnox.Console.TextSize.meta).monospacedDigit())
                            .foregroundStyle(Memnox.Console.muted)
                            .contentTransition(.numericText())
                            .fixedSize()
                    }
                    if tab == .all, tools.found.contains(where: { $0.source != nil }) {
                        Text(ConnectorOrderLines.legend)
                            .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                            .foregroundStyle(Memnox.Console.faint)
                    }
                    if tab == .all, let note = tools.searchNote {
                        Text(note)
                            .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                            .foregroundStyle(Memnox.Console.warm)
                    }
                    results
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(YourApps.allowanceLine)
                .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                .foregroundStyle(Memnox.Console.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            tools.refresh()
            tools.search()
        }
        .onChange(of: tools.query) {
            // A category from one search means nothing in the next, as the console resets it.
            category = nil
            tools.search()
        }
        .onChange(of: tab) { category = nil }
        // Back from the browser's sign in, the list is read again so a tool just connected shows at once.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in tools.refresh() }
        .consoleSheet(item: $leaving) { card in
            ConsoleConfirm(symbol: Self.disconnectSymbol, title: YourAppDisconnect.title(card.name),
                           message: YourAppDisconnect.message(card.name), detail: YourAppDisconnect.detail(card.name),
                           confirm: YourAppDisconnect.confirm,
                           cancel: { leaving = nil },
                           act: {
                               leaving = nil
                               tools.disconnect(card.slug)
                           })
        }
    }

    @ViewBuilder private var results: some View {
        let cards = shown
        if cards.isEmpty {
            empty
        } else {
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: Layout.gridSpacing) {
                ForEach(cards) { card in
                    YourAppTile(card: card, recommended: featured.contains(card.slug),
                                busy: tools.busy == card.slug, waiting: tools.waitingFor == card.slug,
                                disabled: tools.busy != nil || tools.signingIn,
                                signInFirst: tools.signInNeeded,
                                note: tools.note?.toolkit == card.slug ? tools.note : nil,
                                connect: { tools.connect(card.slug, again: card.standing == .signInAgain) },
                                anotherAccount: { tools.connect(card.slug, again: true) },
                                disconnect: { leaving = card },
                                dismissNote: tools.dismissNote)
                }
            }
        }
    }

    @ViewBuilder private var empty: some View {
        if tab == .connected, tools.loading {
            EmptyState(symbol: Self.emptySymbol, title: "Reading your apps", detail: "This takes a moment.")
        } else if tab == .connected, typed.isEmpty {
            EmptyState(symbol: Self.emptySymbol, title: "No apps yet",
                       detail: tools.connectionsNote ?? "Connect one from Recommended or All and sign in to it in your browser.")
        } else {
            EmptyState(symbol: Self.emptySymbol, title: YourApps.countLine(0, query: tools.query),
                       detail: tab == .all ? "Try another name for the app." : "Search All to look through every app you can connect.")
        }
    }

    /// The tab on screen: the one picked, else All for a search, Connected for somebody with apps and Recommended otherwise.
    private var tab: YourAppsTab {
        if let chosenTab { return chosenTab }
        if !typed.isEmpty { return .all }
        return tools.yourApps.isEmpty ? .recommended : .connected
    }

    private func title(_ tab: YourAppsTab) -> String {
        switch tab {
        case .connected: "Connected (\(tools.yourApps.count))"
        case .recommended: "Recommended"
        case .all: "All"
        }
    }

    /// The step the page leads with while nobody is signed in to Memnox Cloud, starting the app's own sign in.
    private var signInStep: some View {
        SettingsCard {
            SettingsRow(symbol: Self.signInSymbol, title: YourApps.signInTitle, caption: YourApps.signInDetail,
                        tint: Memnox.Console.primary) {
                HStack(spacing: Memnox.Spacing.small) {
                    if tools.signingIn { ProgressView().controlSize(.small) }
                    Button("Sign in") { tools.signInForApps() }
                        .buttonStyle(KitButton(kind: .primary))
                        .disabled(tools.signingIn)
                        .accessibilityLabel(YourApps.signInTitle)
                }
            }
        }
    }

    /// The categories down the side with their counts, commonest first, as the console's rail.
    private var rail: some View {
        VStack(alignment: .leading, spacing: Layout.railRowSpacing) {
            Text("Categories")
                .textCase(.uppercase)
                .font(Memnox.Console.code(Memnox.Console.TextSize.meta))
                .tracking(Memnox.Console.headingTracking)
                .foregroundStyle(Memnox.Console.muted)
                .padding(.horizontal, Layout.railRowPadH)
                .padding(.bottom, Memnox.Spacing.small)
            railRow(label: "All toolkits", count: pool.count, chosen: category == nil) { category = nil }
            ForEach(categories.prefix(Layout.railLeading)) { each in
                railRow(label: each.label, count: each.count, chosen: category == each.id) { category = each.id }
            }
        }
        .frame(width: Layout.railWidth, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Categories")
    }

    private func railRow(label: String, count: Int, chosen: Bool, choose: @escaping () -> Void) -> some View {
        Button(action: choose) {
            HStack(spacing: Memnox.Spacing.small) {
                Text(label)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: Memnox.Spacing.small)
                Text("\(count)")
                    .font(Memnox.Console.code(Memnox.Console.TextSize.meta).monospacedDigit())
                    .foregroundStyle(Memnox.Console.faint)
            }
            .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, chosen ? .medium : .regular))
            .foregroundStyle(chosen ? Memnox.Console.foreground : Memnox.Console.muted)
            .padding(.horizontal, Layout.railRowPadH)
            .padding(.vertical, Layout.railRowPadV)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(chosen ? Memnox.Console.active : Color.clear,
                        in: RoundedRectangle(cornerRadius: Memnox.Console.controlRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHand()
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// The tab's cards before a category narrows them, which the rail and the count are taken from.
    private var pool: [YourAppCard] {
        switch tab {
        case .connected: narrowed(tools.yourApps)
        case .recommended: narrowed(recommended)
        case .all: tools.offered
        }
    }

    private var categories: [YourAppCategory] { YourApps.categories(pool) }

    /// The cards on screen: the tab's own, narrowed to the category picked.
    private var shown: [YourAppCard] {
        pool.filter { YourApps.inCategory($0, category) }
    }

    /// The featured tools, connected or not, named and drawn as the catalogue has them where it has answered.
    private var recommended: [YourAppCard] {
        let named = Dictionary(tools.found.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
        let summaries = FeaturedToolkits.slugs.map { named[$0] ?? ToolkitSummary(slug: $0, name: ToolkitName.of($0)) }
        return YourApps.catalogue(summaries, connections: tools.connections)
    }

    private var featured: Set<String> { Set(FeaturedToolkits.slugs) }

    private var typed: String { tools.query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func narrowed(_ cards: [YourAppCard]) -> [YourAppCard] {
        guard !typed.isEmpty else { return cards }
        return cards.filter { $0.name.localizedCaseInsensitiveContains(typed) || $0.slug.localizedCaseInsensitiveContains(typed) }
    }

    /// A note that belongs to no card on screen is said over the grid, so it is never lost behind a tab or a category.
    private var pageNote: YourAppNote? {
        guard let note = tools.note else { return nil }
        guard let toolkit = note.toolkit else { return note }
        return shown.contains { $0.slug == toolkit } ? nil : note
    }
}

/// The three views of the person's tools, as the console's connectors page has them.
private enum YourAppsTab: String, CaseIterable {
    case connected
    case recommended
    case all
}
