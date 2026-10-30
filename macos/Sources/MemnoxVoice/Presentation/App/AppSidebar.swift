import MemnoxVoiceCore
import SwiftUI

/// The window's one navigation, laid on the ground beside the page's panel with no rule between them: the mark and a
/// search at the top, Today, Home and what waits on you, then each destination as a heading that folds over its pages, and
/// Settings at the foot. The chosen row is filled in the Memnox blue. Only Settings keeps a tree of its own in the page.
/// As a rail it keeps only the icons, each named for VoiceOver and on hover, so nothing is lost when the window is narrow.
struct AppSidebar: View {
    @ObservedObject var shell: AppShellModel
    let route: WindowRoute
    let rail: Bool
    /// Whether the person may fold it themselves, which only a window wide enough for labels offers.
    let canFold: Bool
    let home: HomeModel?
    /// The headings the person folded shut, by title; every heading starts open, as the console's tree does.
    @State private var folded: Set<String> = []

    enum Layout {
        static let width: CGFloat = 240
        static let railWidth: CGFloat = 64
        /// The window's buttons sit at the head's start, so the mark begins after them.
        static let trafficLightsRoom: CGFloat = 76
        static let padding: CGFloat = 12
        static let rowHeight: CGFloat = 30
        static let railRow: CGFloat = 40
        static let rowRadius: CGFloat = Memnox.Console.controlRadius
        static let iconWidth: CGFloat = 18
        static let iconSize: CGFloat = 13
        static let wordmark: CGFloat = 15
        static let headingHeight: CGFloat = 26
        static let headingGap: CGFloat = 10
        static let chevron: CGFloat = 9
        /// The chevron turns from pointing at the heading to pointing down at its pages.
        static let openTurn: Double = 90
        static let searchHeight: CGFloat = 30
    }

    /// One heading of the tree and the pages under it, which may come from more than one destination.
    struct Branch {
        let title: String
        /// The icon that stands for the whole heading on the rail.
        let symbol: String
        let pages: [WindowRoute]
    }

    /// The pages the sidebar holds for now, under headings as Memnox Cloud groups them: what can act, what it may do,
    /// the servers handed to it, and what Memnox reads. The rest stay one search away, so it reads simply.
    static let tree: [Branch] = [
        Branch(title: "Agents", symbol: "cpu",
               pages: [WindowRoute(.agents, tab: "list"), WindowRoute(.agents, tab: "sessions"),
                       WindowRoute(.agents, tab: "computer")]),
        Branch(title: "Workspaces", symbol: "folder",
               pages: [WindowRoute(.workspaces, tab: "projects"), WindowRoute(.workspaces, tab: "memory"), WindowRoute(.workspaces, tab: "skills")]),
        Branch(title: "Govern", symbol: "checkmark.shield",
               pages: [WindowRoute(.governance, tab: "policies"), WindowRoute(.governance, tab: "activity")]),
        // MCP servers apart from the connectors, since one is handed to agents and the other is what Memnox reads.
        Branch(title: "MCP Hub", symbol: "powerplug", pages: [WindowRoute(.mcp, tab: "servers")]),
        Branch(title: "Inputs", symbol: "globe",
               pages: [WindowRoute(.mcp, tab: "apps"), WindowRoute(.workspaces, tab: "sources")]),
    ]

    /// Waiting on you stands beside Home, as in Memnox Cloud, since it is the one row that asks something of the person.
    static let waiting = WindowRoute(.governance, tab: "approvals")

    static func symbol(_ destination: Destination) -> String {
        switch destination {
        case .today: "sun.max"
        case .home: "house"
        case .agents: "cpu"
        case .workspaces: "folder"
        case .mcp: "powerplug"
        case .governance: "checkmark.shield"
        case .settings: "gearshape"
        }
    }

    /// Each page's icon in the tree, falling back to its destination's for a page not listed.
    private static func symbol(tab: String, in destination: Destination) -> String {
        switch tab {
        case "list": "cpu"
        case "sessions": "bubble.left.and.text.bubble.right"
        case "computer": "desktopcomputer"
        case "projects": "folder"
        case "memory": "brain"
        case "skills": "book"
        case "servers": "server.rack"
        case "apps": "globe"
        case "sources": "doc.text"
        case "policies": "checkmark.shield"
        case "activity": "list.bullet.rectangle"
        default: symbol(destination)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !rail { search.padding(.horizontal, Layout.padding).padding(.bottom, Memnox.Spacing.medium) }
            ScrollView {
                VStack(alignment: rail ? .center : .leading, spacing: Memnox.Spacing.xxSmall) {
                    // Today stands first, since the window opens on it and it asks the most of the person.
                    let today = Destinations.info(.today)
                    row(symbol: Self.symbol(.today), title: today.title, hint: today.subtitle, chosen: route.destination == .today) {
                        shell.go(Destinations.landing)
                    }
                    let home = Destinations.info(.home)
                    row(symbol: Self.symbol(.home), title: home.title, hint: home.subtitle, chosen: route.destination == .home) {
                        shell.go(WindowRoute(.home))
                    }
                    row(symbol: "tray", title: "Waiting on you", hint: "What your agents are waiting on you for",
                        chosen: route == Self.waiting) {
                        shell.go(Self.waiting)
                    }
                    ForEach(Self.tree, id: \.title) { branch in
                        group(branch, pages: shown(branch))
                    }
                }
                .padding(.horizontal, rail ? Memnox.Spacing.medium : Layout.padding)
                .padding(.bottom, Memnox.Spacing.medium)
            }
            .scrollIndicators(.never)
            VStack(alignment: rail ? .center : .leading, spacing: Memnox.Spacing.xxSmall) {
                if let home {
                    RuntimeStanding(home: home, rail: rail)
                } else {
                    RuntimeWord(tone: .quiet, words: RuntimeStanding.reaching, rail: rail)
                }
                let settings = Destinations.info(.settings)
                row(symbol: Self.symbol(.settings), title: settings.title, hint: settings.subtitle, chosen: route.destination == .settings) {
                    shell.go(WindowRoute(.settings))
                }
                if canFold {
                    row(symbol: "sidebar.left", title: shell.collapsed ? "Show labels" : "Hide labels",
                        hint: "Fold the sidebar to its icons", chosen: false) {
                        withAnimation(.snappy) { shell.collapsed.toggle() }
                    }
                }
            }
            .padding(.horizontal, rail ? Memnox.Spacing.medium : Layout.padding)
            .padding(.vertical, Memnox.Spacing.medium)
            .frame(maxWidth: .infinity)
        }
        .frame(width: rail ? Layout.railWidth : Layout.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Memnox")
    }

    /// The wordmark beside the window's buttons; on the rail the buttons fill it.
    private var header: some View {
        HStack(spacing: Memnox.Spacing.regular) {
            if !rail {
                // The name in the brand's own letters, as the console's sidebar heads itself.
                Wordmark(height: Layout.wordmark)
                Spacer(minLength: 0)
            }
        }
        .padding(.leading, rail ? 0 : Layout.trafficLightsRoom)
        .padding(.trailing, rail ? 0 : Layout.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: ShellMetrics.barHeight)
    }

    /// A search field at the top, as the settings sidebar has, which opens Go to with everything Memnox holds.
    private var search: some View {
        let shape = RoundedRectangle(cornerRadius: Memnox.Console.controlRadius, style: .continuous)
        return Button { shell.palette = true } label: {
            HStack(spacing: Memnox.Spacing.small) {
                Image(systemName: "magnifyingglass").font(.system(size: Memnox.TextSize.caption, weight: .medium))
                Text("Search")
                Spacer(minLength: 0)
                Text("\u{2318}K").font(Memnox.Console.sans(Memnox.Console.TextSize.label, .medium)).foregroundStyle(Memnox.Console.faint)
            }
            .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
            .foregroundStyle(Memnox.Console.muted)
            .padding(.horizontal, Memnox.Spacing.regular)
            .frame(height: Layout.searchHeight)
            .background(Memnox.Console.card, in: shape)
            .overlay(shape.strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
            .hoverLight(radius: Memnox.Console.controlRadius, inset: 0)
            .contentShape(shape)
        }
        .buttonStyle(PressDip())
        .help("Search everything, \u{2318}K")
        .accessibilityLabel("Search everything")
    }

    /// The tree's pages under a heading that the runtime answers now, each with its tab, in the tree's order.
    private func shown(_ branch: Branch) -> [(route: WindowRoute, tab: TabInfo)] {
        branch.pages.compactMap { page in
            Destinations.visibleTabs(page.destination, supports: shell.supports)
                .first { $0.id == page.tab }
                .map { (page, $0) }
        }
    }

    /// A heading that folds over its pages, each page a row with its own icon. On the rail the heading is one icon,
    /// going to its first page.
    @ViewBuilder private func group(_ branch: Branch, pages: [(route: WindowRoute, tab: TabInfo)]) -> some View {
        let here = pages.contains { $0.route == route }
        if rail {
            if let first = pages.first {
                row(symbol: branch.symbol, title: branch.title, hint: first.tab.summary, chosen: here) {
                    shell.go(first.route)
                }
            }
        } else if !pages.isEmpty {
            let open = !folded.contains(branch.title)
            VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                heading(branch.title, open: open) {
                    withAnimation(.snappy(duration: Memnox.Motion.quick)) {
                        if open { folded.insert(branch.title) } else { folded.remove(branch.title) }
                    }
                }
                if open {
                    ForEach(pages, id: \.route) { page in
                        row(symbol: Self.symbol(tab: page.tab.id, in: page.route.destination), title: page.tab.title,
                            hint: page.tab.summary, chosen: route == page.route) {
                            shell.go(page.route)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .padding(.top, Layout.headingGap)
            // Arriving on a page under a folded heading opens it, so the chosen row is never hidden.
            .onChange(of: route) { if pages.contains(where: { $0.route == route }) { folded.remove(branch.title) } }
        }
    }

    /// A heading in the tree: a chevron and the destination's name, muted and small, folding its pages away on a press.
    private func heading(_ title: String, open: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(spacing: Memnox.Spacing.small) {
                Image(systemName: "chevron.right")
                    .font(.system(size: Layout.chevron, weight: .semibold))
                    .rotationEffect(.degrees(open ? Layout.openTurn : 0))
                    .frame(width: Layout.iconWidth)
                Text(title)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.meta, .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Memnox.Console.faint)
            .padding(.horizontal, Memnox.Spacing.small)
            .frame(height: Layout.headingHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressDip())
        .pointingHand()
        .accessibilityLabel(title)
        .accessibilityValue(open ? "Open" : "Folded")
        .accessibilityAddTraits(.isHeader)
    }

    /// One row: its icon and words, filled in the Memnox blue with white words when chosen, lit softly under the pointer.
    private func row(symbol: String, title: String, hint: String, chosen: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Memnox.Spacing.regular) {
                Image(systemName: symbol)
                    .font(.system(size: Layout.iconSize, weight: .regular))
                    .foregroundStyle(chosen ? Color.white : Memnox.Console.primary)
                    .frame(width: Layout.iconWidth)
                if !rail {
                    Text(title)
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, chosen ? .medium : .regular))
                        .foregroundStyle(chosen ? Color.white : Memnox.Console.foreground)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, rail ? 0 : Memnox.Spacing.small)
            .frame(width: rail ? Layout.railRow : nil, height: rail ? Layout.railRow : Layout.rowHeight)
            .frame(maxWidth: rail ? nil : .infinity, alignment: .leading)
            .background(chosen ? Memnox.Console.primary : Color.clear,
                        in: RoundedRectangle(cornerRadius: Layout.rowRadius, style: .continuous))
            .hoverLight(radius: Layout.rowRadius, inset: 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressDip())
        .help(rail ? title : hint)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// The runtime's standing at the sidebar's foot, read off the home the window already keeps.
private struct RuntimeStanding: View {
    @ObservedObject var home: HomeModel
    let rail: Bool

    static let reaching = "Reaching the runtime"

    var body: some View {
        if home.home != nil {
            RuntimeWord(tone: .good, words: "Runtime running", rail: rail)
        } else if home.unavailable {
            RuntimeWord(tone: .bad, words: "Runtime not answering", rail: rail)
        } else {
            RuntimeWord(tone: .quiet, words: Self.reaching, rail: rail)
        }
    }
}

/// The standing as a word with its dot, or as the dot alone on the rail with the word for hover and VoiceOver.
private struct RuntimeWord: View {
    let tone: Tone
    let words: String
    let rail: Bool

    var body: some View {
        Group {
            if rail {
                Circle().fill(tone.dot)
                    .frame(width: ShellMetrics.dot + 2, height: ShellMetrics.dot + 2)
                    .frame(width: AppSidebar.Layout.railRow, height: AppSidebar.Layout.rowHeight)
                    .help(words)
                    .accessibilityElement()
                    .accessibilityLabel(words)
            } else {
                StatusWord(tone, words)
                    .padding(.horizontal, Memnox.Spacing.small)
                    .frame(maxWidth: .infinity, minHeight: AppSidebar.Layout.rowHeight, alignment: .leading)
            }
        }
    }
}
