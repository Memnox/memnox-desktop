import MemnoxVoiceCore
import SwiftUI

/// The window's frame, as the console frames its own: the sidebar, a flat ground with a 56 high top bar holding Back,
/// Forward, where you are and Go to, and the page under it. The window's width decides the layout, at the same
/// breakpoints Windows and Linux use.
struct AppShellView: View {
    @ObservedObject var shell: AppShellModel
    @ObservedObject var models: SettingsModels
    /// Closes the window, for Escape when nothing else is open.
    let close: () -> Void

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
            if width == .compact, shell.sheet { sheet(route) }
            if shell.palette {
                CommandPalette(supports: shell.supports, go: shell.go) { shell.palette = false }
            }
        }
        .background(keys)
        .animation(.snappy(duration: Memnox.Motion.quick), value: shell.inspecting)
    }

    private func main(_ route: WindowRoute, _ width: WidthClass) -> some View {
        VStack(spacing: 0) {
            topBar(route, width)
            AppPage(shell: shell, models: models, route: route, width: width)
                .id(route)
                .environment(\.paneHeading, heading(route))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Memnox.Console.background)
    }

    /// The console's sub navigation where a destination shows two tabs or more, its title and line where it shows one,
    /// and nothing over Home.
    private func heading(_ route: WindowRoute) -> PaneHeading? {
        let info = Destinations.info(route.destination)
        let tabs = Destinations.visibleTabs(route.destination, supports: shell.supports)
        if tabs.count > 1, let shown = Destinations.tab(of: route) {
            let context = SubNavContext(title: info.title, groups: Destinations.tabGroups(route.destination, supports: shell.supports),
                                        chosen: route.tab) { shell.go(WindowRoute(route.destination, tab: $0)) }
            return .subNav(context, tab: shown.tab, group: shown.group)
        }
        return route.destination == .home ? nil : .page(title: info.title, subtitle: info.subtitle)
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
            if width != .compact {
                TopBarPickers(shell: shell)
            }
            goTo(width).padding(.leading, Memnox.Spacing.xSmall)
        }
        .padding(.leading, width == .compact ? Layout.trafficLights : Layout.compactBarPadding)
        .padding(.trailing, width == .compact ? Layout.compactBarPadding : Layout.barPadding)
        .frame(height: ShellMetrics.barHeight)
        .overlay(alignment: .bottom) { ShellDivider() }
    }

    /// Where the window is, as the console's top bar says it: the destination, then its tab once there are tabs.
    private func breadcrumb(_ route: WindowRoute) -> some View {
        let info = Destinations.info(route.destination)
        let tabs = Destinations.visibleTabs(route.destination, supports: shell.supports)
        let tab = tabs.count < 2 ? nil : tabs.first { $0.id == route.tab }
        return HStack(spacing: Memnox.Spacing.small) {
            Text(info.title)
                .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, tab == nil ? .medium : .regular))
                .foregroundStyle(tab == nil ? Memnox.Console.foreground : Memnox.Console.muted)
            if let tab {
                Text("/").foregroundStyle(Memnox.Console.faint).accessibilityHidden(true)
                Text(tab.title)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
                    .foregroundStyle(Memnox.Console.foreground)
            }
        }
        .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
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
                .background(Memnox.Console.surface)
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
            ForEach(Destinations.all.filter { $0.key != nil }, id: \.id) { each in
                if let key = each.key {
                    Button(each.title) { shell.go(WindowRoute(each.id)) }
                        .keyboardShortcut(KeyEquivalent(key), modifiers: .command)
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
            case .agents:
                if route.tab == "computer" {
                    SettingsPageColumn { ToolsPage(tools: menu.tools) }
                } else if route.tab == "list", let agents = shell.agents {
                    AgentListDestination(screen: agents, island: island, home: models.home,
                                         profiles: shell.supports("profiles") == true ? shell.profiles : nil,
                                         current: shell.currentProject, width: width)
                } else {
                    SessionsDestination(shell: shell, island: island, width: width)
                }
            case .workspaces:
                // Memory reads `memory-facts`, My Skills and Assigned `skills-hub`, Discover `index-list` and Profiles `profiles`; until this Mac's runtime answers them only the projects show.
                if route.tab == "skills" || route.tab == "assigned" {
                    if let skills = shell.skills {
                        SkillsDestination(screen: skills, island: island, tab: route.tab, current: shell.currentProject,
                                          scope: shell.scope, width: width)
                    }
                } else if route.tab == "memory" {
                    if let memory = shell.memory { MemoryDestination(screen: memory, shell: shell, island: island, width: width) }
                } else if route.tab == "discover" {
                    if let index = shell.index { DiscoverDestination(screen: index, width: width) }
                } else if route.tab == "profiles" {
                    if let profiles = shell.profiles { ProfilesDestination(shell: shell, screen: profiles, width: width) }
                } else {
                    WorkspacesDestination(shell: shell, island: island, width: width)
                }
            case .mcp:
                // Servers, Clients and Secrets read `mcp-hub`; until this Mac's runtime answers it only Your apps shows.
                if route.tab == "apps" || route.tab == nil {
                    SettingsPageColumn { YourAppsPage(tools: menu.tools) }
                } else if let hub = shell.hub {
                    McpHubDestination(shell: shell, screen: hub, island: island, tab: route.tab, width: width)
                }
            case .governance:
                // Each tab past Approvals shows once this Mac's runtime answers the method it reads.
                if route.tab == "policies", let studio = shell.studio {
                    PoliciesDestination(shell: shell, screen: studio, island: island, home: models.home, width: width)
                } else if route.tab == "activity", let activity = shell.activity {
                    ActivityDestination(shell: shell, screen: activity, width: width)
                } else if route.tab == "learn", let memory = shell.memory {
                    LearnDestination(screen: memory, island: island, width: width)
                } else if route.tab == "approvals" || route.tab == nil {
                    ApprovalsDestination(island: island, width: width)
                }
            case .settings:
                SettingsDestination(models: models, menu: menu, setup: setup, tab: route.tab, backup: shell.backup,
                                    network: shell.network, sync: shell.sync)
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
    @ViewBuilder let content: Content

    var body: some View {
        SettingsColumn(title: title, subtitle: subtitle) { content }
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
            if shell.supports("projects") == true, let projects = shell.projects?.projects.projects, !projects.isEmpty {
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
