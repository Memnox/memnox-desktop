import MemnoxVoiceCore
import SwiftUI

/// The window's frame: the sidebar on the ground, and beside it the page in one bordered panel with rounded corners,
/// its top bar holding Back, Forward and where you are. No rule divides the two; the panel's edge does. The window's width decides the layout, at the same
/// breakpoints Windows and Linux use.
struct AppShellView: View {
    @ObservedObject var shell: AppShellModel
    @ObservedObject var models: SettingsModels
    /// Closes the window, for Escape when nothing else is open.
    let close: () -> Void
    /// Blurs and dims the page behind any dialog a page opens, as the console does.
    @StateObject private var backdrop = ModalBackdrop()

    private enum Layout {
        /// Room for the window's buttons when there is no sidebar under them.
        static let trafficLights: CGFloat = 76
        static let sheetScrim = 0.4
        static let iconButton: CGFloat = 36
        static let goToPadding: CGFloat = 12
        static let keyPadding: CGFloat = 6
        static let barPadding: CGFloat = 20
        static let compactBarPadding: CGFloat = 12
        static let disabledOpacity = 0.35
        /// The panel stands this far from the window's edges and the sidebar, so its border reads all the way round.
        static let panelInset: CGFloat = 8
        static let panelRadius: CGFloat = Memnox.Console.cardRadius
    }

    var body: some View {
        GeometryReader { geometry in
            frame(WidthClass(width: Double(geometry.size.width)))
        }
        .ignoresSafeArea()
        .background(Memnox.Console.background.ignoresSafeArea())
        .consoleLook()
        .task(id: models.setup.map(ObjectIdentifier.init)) { await models.setup?.check() }
    }

    private func frame(_ width: WidthClass) -> some View {
        let route = shell.route
        let rail = width == .narrow || (shell.collapsed && width != .compact)
        return ZStack {
            HStack(spacing: 0) {
                if width != .compact {
                    AppSidebar(shell: shell, route: route, rail: rail, canFold: width == .wide || width == .medium, home: models.home)
                }
                main(route, width)
            }
            .blur(radius: backdrop.showing ? ModalMetrics.blur : 0)
            .overlay {
                if backdrop.showing {
                    Color.black.opacity(ModalMetrics.scrim).allowsHitTesting(false).transition(.opacity)
                }
            }
            .animation(.easeOut(duration: Memnox.Motion.quick), value: backdrop.showing)
            if width == .compact, shell.sheet { sheet(route) }
            if shell.palette {
                CommandPalette(supports: shell.supports, go: shell.go) { shell.palette = false }
            }
        }
        .background(keys)
        .environment(\.modalBackdrop, backdrop)
        .animation(.snappy(duration: Memnox.Motion.quick), value: shell.inspecting)
    }

    private func main(_ route: WindowRoute, _ width: WidthClass) -> some View {
        let shape = RoundedRectangle(cornerRadius: Layout.panelRadius, style: .continuous)
        return VStack(spacing: 0) {
            topBar(route, width)
            strip(route, width)
            AppPage(shell: shell, models: models, route: route, width: width)
                .id(route)
                .environment(\.paneHeading, heading(route))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Memnox.Console.card, in: shape)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
        .padding(.vertical, Layout.panelInset)
        .padding(.trailing, Layout.panelInset)
        // On the narrowest windows there is no sidebar, so the panel keeps its distance from the left edge too.
        .padding(.leading, width == .compact ? Layout.panelInset : 0)
    }

    /// The tabs of the sidebar row the page sits under, as the console sets a page's tabs under its top bar, drawn only
    /// once the row holds two pages the runtime answers.
    @ViewBuilder private func strip(_ route: WindowRoute, _ width: WidthClass) -> some View {
        let tabs = Sidebar.strip(for: route, supports: shell.supports)
        if let chosen = tabs.firstIndex(where: { $0.route == route }) {
            InspectorTabs(tabs: tabs.indices.map { (id: String($0), title: tabs[$0].title) }, chosen: String(chosen)) { id in
                if let at = Int(id), tabs.indices.contains(at) { shell.go(tabs[at].route) }
            }
            .padding(.horizontal, ShellScroll<EmptyView>.side(width))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Destinations.info(route.destination).title)
        }
    }

    /// Settings keeps its tree beside the page; every other page is reached from the sidebar, so it shows only its own
    /// title and line, and Home neither, since its greeting says where things stand.
    private func heading(_ route: WindowRoute) -> PaneHeading? {
        // A project's Overview heads itself with the project's name; its other pages say their own title and line.
        if let place = ProjectSidebar.place(of: route) {
            return place.page == .overview ? nil : .page(title: place.page.title, subtitle: place.page.summary)
        }
        let info = Destinations.info(route.destination)
        if route.destination == .home { return nil }
        guard let shown = Destinations.tab(of: route) else { return .page(title: info.title, subtitle: info.subtitle) }
        if route.destination == .settings, let group = shown.group {
            let context = SubNavContext(title: info.title, groups: Destinations.tabGroups(.settings, supports: shell.supports),
                                        chosen: route.tab) { shell.go(WindowRoute(.settings, tab: $0)) }
            return .subNav(context, tab: shown, group: group.title)
        }
        return .page(title: shown.title, subtitle: shown.summary)
    }

    private func topBar(_ route: WindowRoute, _ width: WidthClass) -> some View {
        HStack(spacing: Memnox.Spacing.xSmall) {
            if width == .compact {
                iconButton("line.3.horizontal", "Open the menu", enabled: true) { shell.sheet = true }
            }
            iconButton("chevron.left", "Back", enabled: shell.canGoBack, action: shell.back)
            iconButton("chevron.right", "Forward", enabled: shell.canGoForward, action: shell.forward)
            breadcrumb(route)
                .padding(.leading, Memnox.Spacing.medium)
            Spacer(minLength: Memnox.Spacing.medium)
            if shell.demo { DemoBadge() }
            if width != .compact {
                TopBarPickers(shell: shell)
            } else {
                // The sidebar holds the search; with no sidebar, Go to stays in the bar.
                goTo(width).padding(.leading, Memnox.Spacing.xSmall)
            }
        }
        .padding(.leading, width == .compact ? Layout.trafficLights : Layout.compactBarPadding)
        .padding(.trailing, width == .compact ? Layout.compactBarPadding : Layout.barPadding)
        .frame(height: ShellMetrics.barHeight - Layout.panelInset)
    }

    /// Where the window is, as the console's top bar says it: the sidebar row, then its tab once the row has a strip.
    private func breadcrumb(_ route: WindowRoute) -> some View {
        let parts = crumbs(route)
        return HStack(spacing: Memnox.Spacing.small) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                let last = index == parts.count - 1
                if index > 0 { Text("/").foregroundStyle(Memnox.Console.faint).accessibilityHidden(true) }
                Text(part)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, last ? .medium : .regular))
                    .foregroundStyle(last ? Memnox.Console.foreground : Memnox.Console.muted)
            }
        }
        .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// The sidebar row and its tab once the row has a strip, or inside a project, Projects, its name and the page.
    private func crumbs(_ route: WindowRoute) -> [String] {
        if let place = ProjectSidebar.place(of: route) {
            return ProjectSidebar.breadcrumb(place, name: shell.projects?.projects.projects?.first { $0.id == place.id }?.name)
        }
        let row = Destinations.info(route.destination).title
        let tab = Sidebar.strip(for: route, supports: shell.supports).first { $0.route == route }
        return [row] + (tab.map { [$0.title] } ?? [])
    }

    /// Back, Forward and the menu, each a 36 square that lights at radius 6 under the pointer.
    private func iconButton(_ symbol: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: Memnox.TextSize.body, weight: .medium))
                .foregroundStyle(Memnox.Console.muted)
                .frame(width: Layout.iconButton, height: Layout.iconButton)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverLight(radius: Memnox.Console.controlRadius, inset: 0)
        .disabled(!enabled)
        .opacity(enabled ? 1 : Layout.disabledOpacity)
        .help(label)
        .accessibilityLabel(label)
    }

    /// Go to, as the console's: a bordered button with its shortcut printed on a key beside the words.
    private func goTo(_ width: WidthClass) -> some View {
        let shape = RoundedRectangle(cornerRadius: Memnox.Console.controlRadius, style: .continuous)
        return Button { shell.palette = true } label: {
            HStack(spacing: Memnox.Spacing.medium) {
                Image(systemName: "magnifyingglass").font(.system(size: Memnox.TextSize.callout))
                if width != .compact { Text("Go to") }
                Text("\u{2318}K")
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.label, .medium))
                    .foregroundStyle(Memnox.Console.muted)
                    .padding(.horizontal, Layout.keyPadding)
                    .background(Memnox.Console.hover, in: shape)
                    .overlay(shape.strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
            }
            .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
            .foregroundStyle(Memnox.Console.muted)
            .padding(.horizontal, Layout.goToPadding)
            .frame(height: Memnox.Console.fieldHeight)
            .background(Memnox.Console.card, in: shape)
            .overlay(shape.strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .hoverLight(radius: Memnox.Console.controlRadius, inset: 0)
        .help("Go to anything")
        .accessibilityLabel("Go to anything")
    }

    /// The sidebar over the page on the narrowest windows, closed by a click beside it or by Escape.
    private func sheet(_ route: WindowRoute) -> some View {
        HStack(spacing: 0) {
            AppSidebar(shell: shell, route: route, rail: false, canFold: false, home: models.home)
                .background(Memnox.Console.background)
                .accessibilityAddTraits(.isModal)
            Color.black.opacity(Layout.sheetScrim)
                .contentShape(Rectangle())
                .onTapGesture { shell.sheet = false }
                .accessibilityLabel("Close the menu")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { shell.sheet = false }
        }
        .transition(.move(edge: .leading))
    }

    /// Command K opens the palette, Command and a digit a destination, Command [ and ] go back and forward, and Escape
    /// takes away what is open, through buttons no one sees.
    private var keys: some View {
        ZStack {
            Button("Go to") { shell.palette = true }.keyboardShortcut("k", modifiers: .command)
            ForEach(Destinations.all, id: \.id) { each in
                if let key = Destinations.key(each.id) {
                    Button(each.title) { shell.go(WindowRoute(each.id)) }
                        .keyboardShortcut(KeyEquivalent(Character(key)), modifiers: .command)
                }
            }
            Button("Back", action: shell.back).keyboardShortcut("[", modifiers: .command)
            Button("Forward", action: shell.forward).keyboardShortcut("]", modifiers: .command)
            // The palette's own field takes Escape while it is open, so this one stands aside until it closes.
            if !shell.palette {
                Button("Close") { if !shell.dismissTopmost() { close() } }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .opacity(0)
        .accessibilityHidden(true)
    }
}

/// The destination's page, once the models every page reads have been handed over.
private struct AppPage: View {
    @ObservedObject var shell: AppShellModel
    @ObservedObject var models: SettingsModels
    let route: WindowRoute
    let width: WidthClass

    var body: some View {
        if let menu = models.menu, let setup = models.setup, let island = shell.island {
            switch route.destination {
            case .home:
                HomeDestination(shell: shell, menu: menu, setup: setup, island: island, models: models, width: width)
            case .needsYou:
                NeedsYouDestination(shell: shell, island: island, width: width)
            case .sessions:
                SessionsDestination(shell: shell, island: island, width: width)
            case .agents:
                if route.tab == "this-computer" {
                    SettingsPageColumn { ToolsPage(tools: menu.tools) }
                } else if route.tab == "jobs", let profiles = shell.profiles {
                    ProfilesDestination(shell: shell, screen: profiles, width: width)
                } else if let agents = shell.agents {
                    AgentListDestination(screen: agents, island: island, home: models.home,
                                         profiles: shell.supports("profiles") == true ? shell.profiles : nil,
                                         current: shell.currentProject,
                                         work: shell.supports("agent-work") == true ? shell.work : nil,
                                         workspace: shell.workspaceAgents,
                                         giveJob: { profile in
                                             shell.jobFor = profile.id
                                             shell.go(WindowRoute(.agents, tab: "jobs"))
                                         }, width: width)
                }
            case .projects:
                WorkspacesDestination(shell: shell, island: island, account: models.account, width: width)
            case .work:
                if let work = shell.work { WorkDestination(screen: work, profiles: shell.profiles, width: width) }
            case .rules:
                if let studio = shell.studio {
                    PoliciesDestination(shell: shell, screen: studio, island: island, home: models.home, width: width)
                }
            case .handOver:
                if let home = models.home { HandOverDestination(home: home, width: width) }
            case .activity:
                if let activity = shell.activity { ActivityDestination(shell: shell, screen: activity, width: width) }
            case .memory:
                if route.tab == "skills" {
                    if let skills = shell.skills {
                        SkillsDestination(screen: skills, island: island, current: shell.currentProject, scope: shell.scope, width: width)
                    }
                } else if let memory = shell.memory {
                    MemoryDestination(screen: memory, shell: shell, island: island, width: width, shown: MemoryView(tab: route.tab))
                }
            case .connectors:
                if route.tab == "files" {
                    if let memory = shell.memory { ShellScroll(width: width) { MemorySourcesPage(screen: memory, shell: shell) } }
                } else if route.tab == "mcp" {
                    if let hub = shell.hub { McpHubDestination(shell: shell, screen: hub, island: island, width: width) }
                } else {
                    SettingsPageColumn(wide: true) { YourAppsPage(tools: menu.tools) }
                }
            case .machines:
                SettingsPageColumn { SetupMacCard(model: setup) }
            case .settings:
                SettingsDestination(models: models, menu: menu, setup: setup, tab: route.tab, network: shell.network)
            }
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// An existing Settings page in its own column, styled as the Settings window styled it.
struct SettingsPageColumn<Content: View>: View {
    var title: String?
    var subtitle: String?
    var wide = false
    @ViewBuilder let content: Content

    var body: some View {
        SettingsColumn(title: title, subtitle: subtitle, wide: wide) { content }
            .environment(\.rimlessCards, true)
            // Any button a page leaves unstyled is the grey capsule, so no system button shows here.
            .buttonStyle(QuietButton())
    }
}

/// The workspace switcher and, once Memnox Cloud hands anything down, the scope selector. Neither decides anything:
/// the switcher narrows the window to one project, and the selector shows the organization's read only items.
private struct TopBarPickers: View {
    @ObservedObject var shell: AppShellModel

    var body: some View {
        HStack(spacing: Memnox.Spacing.small) {
            // Inside a project its own sidebar holds the switcher, so the top bar shows no second one.
            if shell.supports("projects") == true, ProjectSidebar.place(of: shell.route) == nil,
               let projects = shell.projects?.projects.projects, !projects.isEmpty {
                let current = shell.currentProject
                Menu {
                    Button(ShellLines.allProjects) { shell.projectId = "" }
                    Divider()
                    ForEach(projects) { project in
                        Button(project.name) { shell.projectId = project.id }
                    }
                } label: {
                    picker(symbol: "folder", text: current?.name ?? ShellLines.allProjects)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(ShellLines.switcherLabel)
                .accessibilityLabel("\(ShellLines.switcherLabel): \(current?.name ?? ShellLines.allProjects)")
            }
            // Shown only once the runtime hands down an organization's items; nothing here asks for Cloud.
            if shell.hasOrganization {
                Picker(ShellLines.scopeLabel, selection: Binding(get: { shell.scope }, set: { shell.scopeChoice = $0.rawValue })) {
                    ForEach(ShownScope.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel(ShellLines.scopeLabel)
            }
        }
    }

    private func picker(symbol: String, text: String) -> some View {
        HStack(spacing: Memnox.Spacing.small) {
            Image(systemName: symbol).font(.system(size: Memnox.TextSize.caption, weight: .medium))
            Text(text).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: Memnox.TextSize.micro, weight: .semibold))
        }
        .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
        .foregroundStyle(Memnox.Console.foreground)
        .padding(.horizontal, Memnox.Spacing.large)
        .frame(height: Memnox.Console.controlHeight)
        .background(Memnox.Console.field, in: RoundedRectangle(cornerRadius: Memnox.Console.controlRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Memnox.Console.controlRadius, style: .continuous)
            .strokeBorder(Memnox.Console.controlEdge, lineWidth: Memnox.Stroke.hairline))
    }
}

/// Says the window shows made up data, so a demo is never taken for the person's own.
private struct DemoBadge: View {
    private enum Layout {
        static let horizontal: CGFloat = 8
        static let vertical: CGFloat = 3
        static let fill = 0.14
    }

    var body: some View {
        Text("Demo data")
            .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
            .foregroundStyle(Memnox.Console.warm)
            .padding(.horizontal, Layout.horizontal)
            .padding(.vertical, Layout.vertical)
            .background(Memnox.Console.warm.opacity(Layout.fill), in: Capsule())
            .overlay(Capsule().strokeBorder(Memnox.Console.warm, lineWidth: Memnox.Stroke.hairline))
            .help("Everything in this window comes from the demo fixture, and nothing reaches Memnox or your accounts.")
            .accessibilityLabel("Demo data: nothing here is real")
    }
}
