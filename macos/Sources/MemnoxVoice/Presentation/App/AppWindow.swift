import AppKit
import MemnoxVoiceCore
import SwiftUI

/// The Memnox window: five destinations, Settings and the runtime in a sidebar, and the page beside it. It is one
/// window at every size, folding the sidebar to icons when narrow and to a sheet on the narrowest, so nothing is lost
/// when it is made small. Every old way into Settings opens it on the page that took that one's place.
@MainActor
final class AppWindow {
    static let shared = AppWindow()

    /// The island's model, which keeps the sessions fresh and holds every waiting call with the signed way to answer it.
    var island: IslandModel? {
        didSet { shell.island = island }
    }

    /// Which daemon methods this Mac's runtime answers, so a tab that needs one shows only once it does.
    var support: DaemonSupport? {
        didSet { shell.use(support) }
    }

    /// The MCP Hub as this Mac's runtime keeps it, read by the hub's Servers, Clients and Secrets tabs.
    var hub: McpHub? {
        didSet { shell.hub = hub.map(McpHubScreen.init) }
    }

    /// The rules in force and how far the agents have been let go, read by Policies and by Home's week.
    var studio: Studio? {
        didSet { shell.studio = studio.map(StudioScreen.init) }
    }

    /// What the agents did and why, read by Activity.
    var activity: Activity? {
        didSet { shell.activity = activity.map(ActivityScreen.init) }
    }

    /// Every agent found on this Mac with its standing, read by the Agents tab.
    var agents: Agents? {
        didSet { shell.agents = agents.map(AgentsScreen.init) }
    }

    /// The Skills Hub as this Mac's runtime keeps it, read by My Skills and Assigned under Workspaces.
    var skills: SkillsHub? {
        didSet { shell.skills = skills.map(SkillsScreen.init) }
    }

    /// The projects as this Mac's runtime keeps them, read by the Workspaces tab once the runtime answers `projects`.
    var projects: Projects? {
        didSet { shell.projects = projects.map(ProjectsScreen.init) }
    }

    /// Memory as this Mac's runtime keeps it, read by Memory under Workspaces, Learn under Governance and Home's count.
    var memory: Memory? {
        didSet { shell.memory = memory.map(MemoryScreen.init) }
    }

    /// Making a backup and putting one back, read by the Backup page under Settings.
    var backup: Backup? {
        didSet { shell.backup = backup }
    }

    let shell = AppShellModel()
    private var window: NSWindow?

    /// Whether the window is on screen, so the home is read on stream events only while somebody can see it.
    var isShowing: Bool { window?.isVisible == true }

    private enum Layout {
        static let width: CGFloat = 1240
        static let height: CGFloat = 780
        /// Small enough to sit beside an editor, large enough that a page still reads.
        static let minWidth: CGFloat = 420
        static let minHeight: CGFloat = 520
        static let frameName = "MemnoxWindow"
    }

    private init() {}

    /// Opens on the route given, or stays where it was when none is.
    func show(_ route: WindowRoute?, models: SettingsModels) {
        if let route { shell.go(route) }
        // An updated or restarted runtime may answer more than it did, so each opening asks again.
        support?.forget()
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Memnox"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: Layout.minWidth, height: Layout.minHeight)
        // Clear, so the sidebar's glass shows the desktop through it while the page stays solid.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = FirstClickHosting(rootView: AppShellView(shell: shell, models: models) { [weak self] in self?.close() })
        window.center()
        // Opens where and as large as it was last left, once it has been left anywhere.
        window.setFrameAutosaveName(Layout.frameName)
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
        window = nil
    }
}

/// Where the window is and what is open over it, kept outside the views so the menu, the island and setup can open it
/// on a route.
@MainActor
final class AppShellModel: ObservableObject {
    @Published private(set) var history = RouteHistory(WindowRoute(.home))
    @Published var palette = false
    /// The sidebar as a sheet over the page, on the narrowest windows.
    @Published var sheet = false
    /// The item whose details are open beside the page, by its id; nil when none is.
    @Published var inspecting: String?
    @Published var collapsed = UserDefaults.standard.bool(forKey: Keys.collapsed) {
        didSet { UserDefaults.standard.set(collapsed, forKey: Keys.collapsed) }
    }
    @Published var island: IslandModel?
    /// The MCP Hub for its tabs; nil until the app wires it, which keeps those tabs empty rather than broken.
    @Published var hub: McpHubScreen?
    /// Policies, Activity and the agents list, each nil until the app wires it, which keeps its tab empty rather than broken.
    @Published var studio: StudioScreen?
    @Published var activity: ActivityScreen?
    @Published var agents: AgentsScreen?
    /// The Skills Hub for My Skills and Assigned, nil until the app wires it, which keeps those tabs empty rather than broken.
    @Published var skills: SkillsScreen?
    /// The projects for the Workspaces tab, nil until the app wires it, which keeps the repositories the sessions met.
    @Published var projects: ProjectsScreen?
    /// Memory for its tab, Learn and Home, nil until the app wires it, which keeps those empty rather than broken.
    @Published var memory: MemoryScreen?
    /// The Backup page's use case, nil until the app wires it, which leaves that page empty rather than broken.
    @Published var backup: Backup?
    /// Bumped when the daemon answers a method, so the tabs are drawn again.
    @Published private(set) var answers = 0
    private var support: DaemonSupport?

    enum Keys {
        static let collapsed = "memnox.sidebar.collapsed"
    }

    func use(_ support: DaemonSupport?) {
        self.support = support
        support?.changed = { [weak self] in
            Task { @MainActor [weak self] in self?.answers += 1 }
        }
    }

    /// Nothing wired reads as not supported, so no tab shows that could not be filled.
    func supports(_ method: String) -> Bool? {
        guard let support else { return false }
        return support.supports(method)
    }

    /// The route as drawn, with a hidden tab settled on the first one shown.
    var route: WindowRoute { Destinations.settled(history.current, supports: supports) }

    var canGoBack: Bool { history.canGoBack }
    var canGoForward: Bool { history.canGoForward }

    func go(_ route: WindowRoute) {
        history.visit(route)
        settle()
    }

    /// A legacy Settings page, as the island and the old pages still name them.
    func go(page: SettingsPage) {
        go(Destinations.route(forPage: page.rawValue) ?? WindowRoute(.settings, tab: page.rawValue))
    }

    func back() {
        history.back()
        settle()
    }

    func forward() {
        history.forward()
        settle()
    }

    /// Escape takes away the topmost thing open, and says whether there was one.
    func dismissTopmost() -> Bool {
        if palette {
            palette = false
        } else if sheet {
            sheet = false
        } else if inspecting != nil {
            inspecting = nil
        } else {
            return false
        }
        return true
    }

    private func settle() {
        palette = false
        sheet = false
        inspecting = nil
    }
}
