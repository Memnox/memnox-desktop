import AppKit
import Combine
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
        didSet {
            shell.island = island
            // A held call the island is not showing is said through the system, once the person allows it.
            HeldNotifier.shared.watch(island)
        }
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

    /// Whether paired phones reach this Mac over the local network, read by Local network and Phones under Settings.
    var network: LocalNetwork? {
        didSet { shell.network = network.map(NetworkScreen.init) }
    }

    /// The person's own setup carried between their machines, read by Personal sync under Settings.
    var sync: PersonalSync? {
        didSet { shell.sync = sync.map(SyncScreen.init) }
    }

    /// Skills and rule packs from the community index, read by Discover under Workspaces and the packs under Policies.
    var index: CommunityIndex? {
        didSet { shell.index = index.map(IndexScreen.init) }
    }

    /// Named bundles of skills, servers and a rule pack, read by Profiles under Workspaces and Launch on an agent's card.
    var profiles: Profiles? {
        didSet { shell.profiles = profiles.map(ProfilesScreen.init) }
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
    /// The project the switcher picked, by id; empty for every project.
    @Published var projectId = UserDefaults.standard.string(forKey: ShellLines.currentProjectKey) ?? "" {
        didSet { UserDefaults.standard.set(projectId, forKey: ShellLines.currentProjectKey) }
    }
    /// The scope the selector picked, remembered while there is an organization to show.
    @Published var scopeChoice = AppShellModel.rememberedScope() {
        didSet { UserDefaults.standard.set(scopeChoice, forKey: ShellLines.scopeKey) }
    }
    @Published var island: IslandModel?

    /// The scope remembered, moving a choice the two choice selector kept to the three choice key once.
    private static func rememberedScope() -> String {
        let defaults = UserDefaults.standard
        if let legacy = defaults.string(forKey: ShellLines.legacyScopeKey) {
            if defaults.string(forKey: ShellLines.scopeKey) == nil, let migrated = ShellLines.migratedScope(legacy) {
                defaults.set(migrated.rawValue, forKey: ShellLines.scopeKey)
            }
            defaults.removeObject(forKey: ShellLines.legacyScopeKey)
        }
        return defaults.string(forKey: ShellLines.scopeKey) ?? ShownScope.all.rawValue
    }
    /// The MCP Hub for its tabs; nil until the app wires it, which keeps those tabs empty rather than broken.
    @Published var hub: McpHubScreen? {
        didSet { follow() }
    }
    /// Policies, Activity and the agents list, each nil until the app wires it, which keeps its tab empty rather than broken.
    @Published var studio: StudioScreen? {
        didSet { follow() }
    }
    @Published var activity: ActivityScreen?
    @Published var agents: AgentsScreen?
    /// The Skills Hub for My Skills and Assigned, nil until the app wires it, which keeps those tabs empty rather than broken.
    @Published var skills: SkillsScreen? {
        didSet { follow() }
    }
    /// The projects for the Workspaces tab, nil until the app wires it, which keeps the repositories the sessions met.
    @Published var projects: ProjectsScreen? {
        didSet { follow() }
    }
    /// Memory for its tab, Learn and Home, nil until the app wires it, which keeps those empty rather than broken.
    @Published var memory: MemoryScreen?
    /// The Backup page's use case, nil until the app wires it, which leaves that page empty rather than broken.
    @Published var backup: Backup?
    /// The local network, nil until the app wires it, which leaves its page empty and Phones without its line.
    @Published var network: NetworkScreen?
    /// Personal sync, nil until the app wires it, which leaves its page empty rather than broken.
    @Published var sync: SyncScreen?
    /// The community index for Discover and the Policies packs, nil until the app wires it, which keeps both empty.
    @Published var index: IndexScreen?
    /// Profiles for their tab and Launch, nil until the app wires it, which keeps the tab empty and Launch without a choice.
    @Published var profiles: ProfilesScreen?
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

    /// The top bar's pickers read the hub, the skills, the rules and the projects, so the shell redraws when any of them changes.
    private var following: Set<AnyCancellable> = []

    private func follow() {
        following = []
        let screens: [ObservableObjectPublisher?] = [hub?.objectWillChange, skills?.objectWillChange, studio?.objectWillChange,
                                                     projects?.objectWillChange]
        for screen in screens.compactMap({ $0 }) {
            screen.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &following)
        }
    }

    /// The project the switcher picked, nil for every project or one that is gone.
    var currentProject: ProjectView? {
        ShellLines.currentProject(projects?.projects.projects, saved: projectId)
    }

    /// Whether the runtime handed down anything of an organization's, which shows the scope selector.
    var hasOrganization: Bool {
        ShellLines.hasOrganization(servers: hub?.hub.hub?.servers ?? [], skills: skills?.skills.hub?.skills ?? [],
                                   rules: studio?.studio.rules?.rules ?? [])
    }

    /// The scope the hub, the skills and the policies show; personal whenever there is no organization.
    var scope: ShownScope { ShellLines.shownScope(saved: scopeChoice, connected: hasOrganization) }

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
