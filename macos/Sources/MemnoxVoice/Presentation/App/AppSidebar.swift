import MemnoxVoiceCore
import SwiftUI

/// The window's one navigation, laid on the ground beside the page's panel with no rule between them: the mark and a
/// search at the top, then the rows the web console's sidebar holds under the same headings, each heading folding over
/// its rows, and Settings at the foot. A row with more than one page opens a tab strip over the page. The chosen row is
/// filled in the Memnox blue. Only Settings keeps a tree of its own in the page.
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

    static let settingsSymbol = "gearshape"

    /// Each row's icon, the SF Symbol nearest the lucide icon the console draws on the same row.
    static func symbol(_ row: SidebarRowId) -> String {
        switch row {
        case .home: "house"
        case .projects: "folder"
        case .waiting: "tray"
        case .activity: "sun.max"
        case .agents: "cpu"
        case .protection: "checkmark.shield"
        case .memory: "brain"
        case .skills: "sparkles"
        case .servers: "powerplug"
        case .connectors: "square.grid.2x2"
        case .files: "doc.text"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !rail { search.padding(.horizontal, Layout.padding).padding(.bottom, Memnox.Spacing.medium) }
            ScrollView {
                VStack(alignment: rail ? .center : .leading, spacing: Memnox.Spacing.xxSmall) {
                    if let place = ProjectSidebar.place(of: route) {
                        project(place)
                    } else {
                        ForEach(Sidebar.sections, id: \.rows.first?.id) { section in
                            group(section)
                        }
                    }
                }
                .padding(.horizontal, rail ? Memnox.Spacing.medium : Layout.padding)
                .padding(.bottom, Memnox.Spacing.medium)
            }
            .scrollIndicators(.never)
            VStack(alignment: rail ? .center : .leading, spacing: Memnox.Spacing.xxSmall) {
                if let home {
                    RuntimeStanding(home: home, rail: rail) { shell.go(WindowRoute(.settings, tab: "connection")) }
                } else {
                    RuntimeWord(tone: .quiet, words: RuntimeStanding.reaching, rail: rail)
                }
                let settings = Destinations.info(.settings)
                row(symbol: Self.settingsSymbol, title: settings.title, hint: settings.subtitle, chosen: route.destination == .settings) {
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

    /// Each page of a project, as its own sidebar shows it.
    static func symbol(_ page: ProjectPage) -> String {
        switch page {
        case .overview: "square.grid.2x2"
        case .tools: "puzzlepiece.extension"
        case .agents: "cpu"
        case .memory: "brain"
        case .rules: "checkmark.shield"
        }
    }

    /// The sidebar a project swaps in once opened, as the Cloudflare dashboard swaps its own for a domain's: the way
    /// back to every project, a switcher on the project's name, and its own pages.
    @ViewBuilder private func project(_ place: ProjectPlace) -> some View {
        let name = shell.projects?.projects.projects?.first { $0.id == place.id }?.name ?? ProjectSidebar.unnamed
        row(symbol: "chevron.left", title: ProjectSidebar.backTitle, hint: "Every project", chosen: false) {
            shell.go(ProjectSidebar.list)
        }
        ProjectSwitcherButton(shell: shell, place: place, name: name, rail: rail)
            .padding(.top, rail ? 0 : Layout.headingGap)
        ForEach(ProjectSidebar.pages, id: \.self) { page in
            row(symbol: Self.symbol(page), title: page.title, hint: page.summary, chosen: place.page == page) {
                shell.go(ProjectSidebar.route(place.id, page))
            }
        }
        // The shared group is left off for now, since each item's badge already says it is shared.
        if ProjectContext.showsShared, let project = shell.projects?.projects.projects?.first(where: { $0.id == place.id }) {
            shared(project)
        }
    }

    /// The pages every project shares, each with how much of it applies here, under a heading saying so.
    @ViewBuilder private func shared(_ project: ProjectView) -> some View {
        let counts = ProjectContext.counts(project, rules: shell.studio?.studio.rules?.rules, skills: shell.skills?.skills.hub?.skills,
                                           servers: shell.hub?.hub.hub?.servers, connections: shell.island?.tools.connections,
                                           memory: shell.memory?.memory.facts?.items, agents: shell.agents?.agents.agents?.count)
        let links = ProjectContext.shared(counts, supports: shell.supports)
        if !links.isEmpty {
            if rail {
                Divider().padding(.vertical, Memnox.Spacing.small)
            } else {
                Text(ProjectContext.sharedTitle)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.meta, .medium))
                    .foregroundStyle(Memnox.Console.faint)
                    .padding(.horizontal, Memnox.Spacing.small)
                    .padding(.top, Layout.headingGap)
                    .frame(maxWidth: .infinity, minHeight: Layout.headingHeight, alignment: .leading)
                    .help(ProjectContext.sharedNote)
                    .accessibilityAddTraits(.isHeader)
            }
            ForEach(links) { link in
                row(symbol: Self.symbol(link.row), title: link.title, hint: link.hint, chosen: false, count: link.count) {
                    shell.go(link.route)
                }
            }
        }
    }

    /// A section's rows the runtime answers now, each with where a press lands.
    private func shown(_ section: SidebarSection) -> [(row: SidebarRow, target: WindowRoute)] {
        section.rows.compactMap { row in Sidebar.target(row, supports: shell.supports).map { (row, $0) } }
    }

    /// A section: its rows alone when it has no heading, otherwise under a heading that folds them away. On the rail
    /// every row keeps its icon and the headings give way to a little room between the sections.
    @ViewBuilder private func group(_ section: SidebarSection) -> some View {
        let rows = shown(section)
        if let title = section.title, !rail {
            if !rows.isEmpty {
                let open = !folded.contains(title)
                VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                    heading(title, open: open) {
                        withAnimation(.snappy(duration: Memnox.Motion.quick)) {
                            if open { folded.insert(title) } else { folded.remove(title) }
                        }
                    }
                    if open {
                        ForEach(rows, id: \.row.id) { item($0.row, $0.target) }
                            .transition(.opacity)
                    }
                }
                .padding(.top, Layout.headingGap)
                // Arriving on a page under a folded heading opens it, so the chosen row is never hidden.
                .onChange(of: route) {
                    if rows.contains(where: { $0.row.id == Sidebar.row(of: route)?.id }) { folded.remove(title) }
                }
            }
        } else {
            VStack(spacing: Memnox.Spacing.xxSmall) {
                ForEach(rows, id: \.row.id) { item($0.row, $0.target) }
            }
            .padding(.top, section.title == nil || rows.isEmpty ? 0 : Layout.headingGap)
        }
    }

    /// One row of the tree, chosen while the page drawn is any of its tabs.
    private func item(_ row: SidebarRow, _ target: WindowRoute) -> some View {
        let hint = Sidebar.tabs(row, supports: shell.supports).first?.summary ?? row.title
        return self.row(symbol: Self.symbol(row.id), title: row.title, hint: hint, chosen: Sidebar.row(of: route)?.id == row.id) {
            shell.go(target)
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
    private func row(symbol: String, title: String, hint: String, chosen: Bool, count: Int? = nil,
                     action: @escaping () -> Void) -> some View {
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
                    if let count {
                        Text("\(count)")
                            .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                            .foregroundStyle(chosen ? Color.white : Memnox.Console.faint)
                            .monospacedDigit()
                    }
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
        .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
        .accessibilityHint(hint)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// The project's name over its pages with a chevron, which opens every project on this computer to switch to, most
/// recent first, each with its folder and a dot while an agent works there. A switch keeps the page shown.
private struct ProjectSwitcherButton: View {
    @ObservedObject var shell: AppShellModel
    let place: ProjectPlace
    let name: String
    let rail: Bool
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: Memnox.Spacing.small) {
                if rail {
                    Image(systemName: "folder")
                        .font(.system(size: AppSidebar.Layout.iconSize))
                        .foregroundStyle(Memnox.Console.foreground)
                } else {
                    Text(name)
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .semibold))
                        .foregroundStyle(Memnox.Console.foreground)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: AppSidebar.Layout.chevron, weight: .semibold))
                        .foregroundStyle(Memnox.Console.muted)
                }
            }
            .padding(.horizontal, rail ? 0 : Memnox.Spacing.small)
            .frame(width: rail ? AppSidebar.Layout.railRow : nil, height: AppSidebar.Layout.rowHeight)
            .frame(maxWidth: rail ? nil : .infinity, alignment: .leading)
            .hoverLight(radius: AppSidebar.Layout.rowRadius, inset: 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressDip())
        .pointingHand()
        .help(ProjectContext.switcherHint)
        .accessibilityLabel("\(name), \(ProjectContext.switcherHint)")
        .accessibilityAddTraits(.isHeader)
        .popover(isPresented: $open, arrowEdge: .trailing) {
            ProjectSwitcherList(shell: shell, place: place) { open = false }
        }
    }
}

/// The switcher's list: a search, every project most recent first, and All projects at the foot.
private struct ProjectSwitcherList: View {
    @ObservedObject var shell: AppShellModel
    let place: ProjectPlace
    let done: () -> Void
    @State private var query = ""

    private enum Layout {
        static let width: CGFloat = 300
        static let listHeight: CGFloat = 320
        static let rowHeight: CGFloat = 44
    }

    var body: some View {
        let rows = ProjectContext.switcher(shell.projects?.projects.projects ?? [], sessions: shell.island?.cards ?? [],
                                           current: place.id, query: query)
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            SearchField(prompt: ProjectContext.switcherPrompt, text: $query)
            ScrollView {
                VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                    if rows.isEmpty {
                        Text("No project matches that.")
                            .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                            .foregroundStyle(Memnox.Console.muted)
                            .padding(Memnox.Spacing.small)
                    }
                    ForEach(rows) { row in
                        Button { pick(row.id) } label: { line(row) }
                            .buttonStyle(PressDip())
                            .pointingHand()
                            .accessibilityLabel(row.live ? "\(row.name), an agent is working there" : row.name)
                            .accessibilityHint(row.folder)
                            .accessibilityAddTraits(row.current ? .isSelected : [])
                    }
                }
            }
            .frame(maxHeight: Layout.listHeight)
            Divider()
            Button {
                done()
                shell.go(ProjectSidebar.list)
            } label: {
                Label(ProjectContext.allProjectsTitle, systemImage: "square.grid.2x2")
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
                    .foregroundStyle(Memnox.Console.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressDip())
            .pointingHand()
        }
        .padding(Memnox.Spacing.large)
        .frame(width: Layout.width)
    }

    private func line(_ row: SwitcherRow) -> some View {
        HStack(spacing: Memnox.Spacing.regular) {
            Circle()
                .fill(row.live ? Tone.good.dot : Color.clear)
                .frame(width: ShellMetrics.dot, height: ShellMetrics.dot)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                Text(row.name)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, row.current ? .semibold : .regular))
                    .foregroundStyle(Memnox.Console.foreground)
                    .lineLimit(1)
                Text(row.folder)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                    .foregroundStyle(Memnox.Console.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            if row.current {
                Image(systemName: "checkmark")
                    .font(.system(size: Memnox.TextSize.caption, weight: .semibold))
                    .foregroundStyle(Memnox.Console.primary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Memnox.Spacing.small)
        .frame(height: Layout.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(row.current ? Memnox.Console.hover : Color.clear,
                    in: RoundedRectangle(cornerRadius: AppSidebar.Layout.rowRadius, style: .continuous))
        .hoverLight(radius: AppSidebar.Layout.rowRadius, inset: 0)
        .contentShape(Rectangle())
    }

    private func pick(_ id: String) {
        done()
        shell.projectId = id
        shell.go(ProjectContext.switchRoute(to: id, from: place))
    }
}

/// The runtime's standing at the sidebar's foot, read off the home the window already keeps.
private struct RuntimeStanding: View {
    @ObservedObject var home: HomeModel
    let rail: Bool

    /// Opens Connection, where Check again installs or starts the service, so a runtime that stopped is one press away.
    let fix: () -> Void

    static let reaching = "Reaching the runtime"

    var body: some View {
        // The last read decides, since the home kept from an earlier read outlives a runtime that stopped since.
        if home.unavailable {
            Button(action: fix) { RuntimeWord(tone: .bad, words: "Runtime not answering", rail: rail) }
                .buttonStyle(.plain)
                .pointingHand()
                .help("Open Connection, where Check again starts the Memnox service")
        } else if home.home != nil {
            RuntimeWord(tone: .good, words: "Runtime running", rail: rail)
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
