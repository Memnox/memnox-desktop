import MemnoxVoiceCore
import SwiftUI

/// The window's frame: the sidebar, a light top bar with Back, Forward and Go to, the destination's tabs, and the page.
/// The window's width decides the layout, at the same breakpoints Windows and Linux use.
struct AppShellView: View {
    @ObservedObject var shell: AppShellModel
    @ObservedObject var models: SettingsModels
    /// Closes the window, for Escape when nothing else is open.
    let close: () -> Void

    private enum Layout {
        static let inset: CGFloat = 8
        static let radius: CGFloat = 16
        /// Room for the window's buttons when there is no sidebar under them.
        static let trafficLights: CGFloat = 76
        static let sheetScrim = 0.4
    }

    var body: some View {
        GeometryReader { geometry in
            frame(WidthClass(width: Double(geometry.size.width)))
        }
        .ignoresSafeArea()
        .background(WindowGlass(material: .sidebar).ignoresSafeArea())
        .tint(Memnox.Palette.primary)
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
                    .modifier(PagePanel(on: width != .compact))
                    .padding(width == .compact ? [] : [.top, .trailing, .bottom], Layout.inset)
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
        let info = Destinations.info(route.destination)
        let tabs = Destinations.visibleTabs(route.destination, supports: shell.supports)
        return VStack(spacing: 0) {
            topBar(route, width)
            if tabs.count > 1 {
                ShellTabBar(tabs: tabs, chosen: route.tab) { shell.go(WindowRoute(route.destination, tab: $0)) }
            }
            if route.destination != .home, route.destination != .settings, tabs.count < 2 {
                Text(info.subtitle)
                    .font(Memnox.sans(Memnox.TextSize.footnote))
                    .foregroundStyle(Memnox.Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, ShellMetrics.pagePadding)
                    .padding(.top, Memnox.Spacing.large)
            }
            AppPage(shell: shell, models: models, route: route, width: width)
                .id(route)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func topBar(_ route: WindowRoute, _ width: WidthClass) -> some View {
        HStack(spacing: Memnox.Spacing.medium) {
            if width == .compact {
                Button { shell.sheet = true } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: Memnox.TextSize.callout, weight: .medium))
                        .foregroundStyle(Memnox.Palette.foreground)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverLight(radius: Memnox.radius, inset: 0)
                .help("Open the menu")
                .accessibilityLabel("Open the menu")
            }
            NavigationCapsule(canGoBack: shell.canGoBack, canGoForward: shell.canGoForward, back: shell.back, forward: shell.forward)
            Text(title(route))
                .font(Memnox.sans(Memnox.TextSize.headline, .semibold))
                .foregroundStyle(Memnox.Palette.foreground)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Memnox.Spacing.medium)
            Button { shell.palette = true } label: {
                HStack(spacing: Memnox.Spacing.small) {
                    Image(systemName: "magnifyingglass").font(.system(size: Memnox.TextSize.caption, weight: .medium))
                    if width != .compact { Text("Go to") }
                    Keycap(label: "\u{2318}K")
                }
                .font(Memnox.sans(Memnox.TextSize.footnote))
                .foregroundStyle(Memnox.Palette.muted)
                .padding(.horizontal, Memnox.Spacing.regular)
                .frame(height: 30)
                .background(Memnox.Palette.card, in: RoundedRectangle(cornerRadius: Memnox.Spacing.medium, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Memnox.Spacing.medium, style: .continuous)
                    .strokeBorder(Memnox.Palette.panelEdge, lineWidth: Memnox.Stroke.hairline))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHand()
            .help("Go to anything")
            .accessibilityLabel("Go to anything")
        }
        .padding(.leading, width == .compact ? Layout.trafficLights : ShellMetrics.pagePadding - Memnox.Spacing.xSmall)
        .padding(.trailing, Memnox.Spacing.large)
        .frame(height: ShellMetrics.barHeight)
        .overlay(alignment: .bottom) { ShellDivider() }
    }

    private func title(_ route: WindowRoute) -> String {
        if route.destination == .settings, let tab = route.tab, let page = SettingsPage(rawValue: tab) { return page.title }
        return Destinations.info(route.destination).title
    }

    /// The sidebar over the page on the narrowest windows, closed by a click beside it or by Escape.
    private func sheet(_ route: WindowRoute) -> some View {
        HStack(spacing: 0) {
            AppSidebar(shell: shell, route: route, rail: false, canFold: false, home: models.home)
                .background(Memnox.Palette.surface)
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

/// The page as Vorssaint sets its panels: solid, inset on the window's glass with rounded corners and one even edge.
private struct PagePanel: ViewModifier {
    let on: Bool

    private static let radius: CGFloat = 16

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: on ? Self.radius : 0, style: .continuous)
        content
            .background(Memnox.Palette.background, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Memnox.Palette.panelEdge, lineWidth: on ? Memnox.Stroke.hairline : 0))
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
                } else {
                    SessionsDestination(shell: shell, island: island, width: width)
                }
            case .workspaces:
                WorkspacesDestination(shell: shell, island: island, width: width)
            case .mcp:
                // Servers, Clients and Secrets read `mcp-hub`; until this Mac's runtime answers it only Your apps shows.
                if route.tab == "apps" || route.tab == nil {
                    SettingsPageColumn { YourAppsPage(tools: menu.tools) }
                }
            case .governance:
                // Policies, Activity and Learn arrive with the runtime methods they read; until then Approvals stands alone.
                if route.tab == "approvals" || route.tab == nil {
                    ApprovalsDestination(island: island, width: width)
                }
            case .settings:
                SettingsDestination(models: models, menu: menu, setup: setup, tab: route.tab)
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
