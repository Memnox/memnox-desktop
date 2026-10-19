import AppKit
import SwiftUI

/// The one ordinary window Memnox opens: setup on the first run and Settings after it, as pages of one window rather
/// than two. The menu bar hands it the menu's model and setup hands it its own, so every page reads live state.
@MainActor
final class SettingsWindow {
    static let shared = SettingsWindow()

    /// The menu's switches, voice and phones, set once the menu bar is built.
    var menu: MenuModel? {
        didSet { models.menu = menu }
    }

    /// Signing in as the person, set once at launch by the app.
    var account: AccountModel? {
        didSet { models.account = account }
    }

    /// Setup's checks, set each time setup is shown, since that is where the checks are run.
    var setup: SetupModel? {
        didSet { models.setup = setup }
    }

    /// Makes setup's model when the window opens without one, since every page waits on it and would spin for good.
    var prepareSetup: (() -> Void)?

    /// The person's dictionary and latest dictations, set once at launch by the app.
    var dictations: DictationStore? {
        didSet { models.dictations = dictations }
    }

    /// The home the overview opens on, set once at launch by the app.
    var home: HomeModel? {
        didSet { models.home = home }
    }

    /// Whether the window is on screen, so the home is read on stream events only while somebody can see it.
    var isShowing: Bool { window?.isVisible == true }

    let navigation = SettingsNavigation()
    private let models = SettingsModels()
    private var window: NSWindow?

    private enum Layout {
        static let width: CGFloat = 940
        static let height: CGFloat = 720
    }

    private init() {}

    /// Opens on the page given, or stays on the one last shown when none is.
    func show(_ page: SettingsPage? = nil) {
        if setup == nil { prepareSetup?() }
        if let page { navigation.go(page) }
        // The numbers, the phones and the voice are read fresh each time the window comes forward.
        menu?.kokoroVoice = KokoroVoice.chosen().voice
        menu?.loadDevices()
        menu?.loadOverview()
        menu?.tools.refresh()
        home?.refresh()
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height),
            // A set size, as Vorssaint's window is, so every page is laid out once for the size it is seen at.
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Memnox"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // An empty toolbar gives the title bar its taller height, so the window's buttons sit level with Back and Forward.
        window.toolbar = NSToolbar()
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        // Clear, so the sidebar's and the page's glass show the desktop through them.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = FirstClickHosting(rootView: SettingsView(models: models, navigation: navigation) { [weak self] in self?.close() })
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
        window = nil
    }
}

/// Which page the window shows, kept outside the view so the menu and setup can open it on a page.
@MainActor
final class SettingsNavigation: ObservableObject {
    @Published private(set) var page: SettingsPage = .overview
    /// The pages left behind and the ones gone back from, so Back and Forward retrace them as a browser does.
    @Published private var behind: [SettingsPage] = []
    @Published private var ahead: [SettingsPage] = []

    var canGoBack: Bool { !behind.isEmpty }
    var canGoForward: Bool { !ahead.isEmpty }

    func go(_ next: SettingsPage) {
        guard next != page else { return }
        behind.append(page)
        ahead.removeAll()
        page = next
    }

    func goBack() {
        guard let last = behind.popLast() else { return }
        ahead.append(page)
        page = last
    }

    func goForward() {
        guard let next = ahead.popLast() else { return }
        behind.append(page)
        page = next
    }
}

/// The two models the pages read, published so a page fills in once setup hands its model over.
@MainActor
final class SettingsModels: ObservableObject {
    @Published var menu: MenuModel?
    @Published var setup: SetupModel?
    @Published var account: AccountModel?
    @Published var home: HomeModel?
    @Published var dictations: DictationStore?
}
