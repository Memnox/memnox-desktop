import AppKit
import MemnoxVoiceCore
import SwiftUI

/// The models of the one ordinary window Memnox opens, and the old way into it: setup on the first run and Settings
/// after it now open the Memnox window. The menu bar hands it the menu's model and setup hands it its own, so every
/// page reads live state.
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
    var isShowing: Bool { AppWindow.shared.isShowing }

    let navigation = SettingsNavigation()
    /// The models every page reads, which the Memnox window shares.
    let models = SettingsModels()

    private init() {}

    /// Opens the Memnox window on the page given, or where it was left when none is. A page that moved out of Settings
    /// lands on the destination that took its place, so every old way in still works.
    func show(_ page: SettingsPage? = nil) {
        if setup == nil { prepareSetup?() }
        // The numbers, the phones and the voice are read fresh each time the window comes forward.
        menu?.kokoroVoice = KokoroVoice.chosen().voice
        menu?.loadDevices()
        menu?.loadOverview()
        menu?.tools.refresh()
        home?.refresh()
        let route = page.map { Destinations.route(forPage: $0.rawValue) ?? WindowRoute(.settings, tab: $0.rawValue) }
        AppWindow.shared.show(route, models: models)
    }

    func close() {
        AppWindow.shared.close()
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
