import AppKit
import MemnoxVoiceCore
import SwiftUI

/// Where the first run stands: the opening over the whole screen, the name asked there, the three short steps every
/// Mac needs, then the end with one next action and what is optional.
enum OnboardingStage: Equatable {
    case intro
    case name
    case steps
    /// The end: one next action, and the voice, the keys, the workspace and the phone as links to Settings.
    case ready
}

/// The three short steps a fresh Mac needs with no account, safe defaults already chosen in each; the notch plays beside
/// all of them.
enum OnboardingStep: Int, CaseIterable, Identifiable {
    /// The service, Touch ID, and the agents found here, on one card.
    case connect
    /// The servers and skills the agents already keep, every one ticked and brought in with one press.
    case workspace
    /// The recommended pack of rules, already chosen, proposed on Finish and signed on the island one by one.
    case boundaries

    var id: Int { rawValue }

    /// The step's name under the progress bar, so a new person always knows where they are and what is left.
    var title: String { FirstRunLines.steps[rawValue] }
}

/// The first run's state, shared by the opening and the window so the name typed in one is the name in the other.
@MainActor
final class OnboardingFlow: ObservableObject {
    @Published var stage: OnboardingStage = .intro
    @Published var step: OnboardingStep = .connect
    /// The part of Memnox the notch beside the steps is playing, said on the first step.
    @Published var highlight: Highlight?
    @Published var setup: SetupModel?
    @Published var menu: MenuModel?
    @Published var account: AccountModel?
    /// Told when the opening hands over to the window, so the controller swaps one window for the other.
    var opened: (() -> Void)?
    /// A part the notch is asked to jump to and play from.
    @Published private(set) var jump: HighlightJump?
    /// The parts the guide has already spoken, so the notch going round again stays quiet.
    var narrated: Set<Highlight> = []
    /// The lines a step said once what it waited on answered, such as what the second step found, so a return is quiet.
    var answered: Set<String> = []

    /// Says a step's line after the page's own, once in this first run.
    func sayOnce(_ line: String, key: String) {
        guard answered.insert(key).inserted else { return }
        setup?.guide(line, interrupting: false)
    }

    /// The step the window was on, kept so a reopen for Screen Recording comes back to the same page.
    private static let stepKey = "onboardingStep"
    /// Whether the window was on the end, so a reopen comes back to it.
    private static let optionalKey = "onboardingOptional"

    var ready: Bool { stage == .ready }

    /// The next step, or the end once the three are done.
    func next() {
        if let following = OnboardingStep(rawValue: step.rawValue + 1) {
            step = following
        } else {
            stage = .ready
        }
        remember()
    }

    func back() {
        if stage == .ready {
            stage = .steps
        } else if let previous = OnboardingStep(rawValue: step.rawValue - 1) {
            step = previous
        }
        remember()
    }

    /// The opening is done, by a name given or by skipping it, and the steps take over.
    func openSteps() {
        stage = .steps
        remember()
        opened?()
    }

    /// Picks up the step a reopen left off at, if there was one.
    func recall() {
        guard stage == .intro, UserDefaults.standard.object(forKey: Self.stepKey) != nil,
              let kept = OnboardingStep(rawValue: UserDefaults.standard.integer(forKey: Self.stepKey)) else { return }
        step = kept
        stage = UserDefaults.standard.bool(forKey: Self.optionalKey) ? .ready : .steps
    }

    /// Forgets the step, once the first run is over.
    func forget() {
        UserDefaults.standard.removeObject(forKey: Self.stepKey)
        UserDefaults.standard.removeObject(forKey: Self.optionalKey)
        UserDefaults.standard.removeObject(forKey: Self.guidedKey)
    }

    /// The page on screen, a step or the end, so each is introduced once.
    var page: Int { guidePage.rawValue }

    /// The page as the spoken guide knows it.
    var guidePage: FirstRunPage {
        switch stage {
        case .ready: return .ready
        case .intro, .name, .steps:
            switch step {
            case .connect: return .connect
            case .workspace: return .workspace
            case .boundaries: return .boundaries
            }
        }
    }

    /// True the first time a page opens in this first run, so a restart for Screen Recording does not hear it again.
    func firstVisit(_ page: Int) -> Bool {
        var guided = Set(UserDefaults.standard.array(forKey: Self.guidedKey) as? [Int] ?? [])
        guard guided.insert(page).inserted else { return false }
        UserDefaults.standard.set(Array(guided), forKey: Self.guidedKey)
        return true
    }

    /// The steps the guide has introduced, kept across the restart Screen Recording needs.
    private static let guidedKey = "onboardingGuided"

    private func remember() {
        UserDefaults.standard.set(step.rawValue, forKey: Self.stepKey)
        UserDefaults.standard.set(ready, forKey: Self.optionalKey)
    }
}

/// A jump to one part of the notch's tour, new each time so the same part twice still plays it again.
struct HighlightJump: Equatable {
    let part: Highlight
    let id = UUID()
}

/// Shows the first run: a dark veil over the whole screen for the opening and the name, then one window for the
/// steps, sized like a sheet so the desktop and System Settings stay reachable while permissions are granted.
@MainActor
final class OnboardingWindow {
    static let shared = OnboardingWindow()

    let flow = OnboardingFlow()
    private var veil: NSWindow?
    private var window: NSWindow?

    private enum Layout {
        static let width: CGFloat = 1000
        static let height: CGFloat = 660
        /// Narrow enough to sit beside System Settings while a permission is granted, wide enough for both columns.
        static let minWidth: CGFloat = 860
        static let minHeight: CGFloat = 560
    }

    private init() {
        flow.opened = { [weak self] in self?.showSteps() }
    }

    func show(_ model: SetupModel) {
        flow.setup = model
        flow.menu = SettingsWindow.shared.menu
        flow.account = SettingsWindow.shared.account
        flow.recall()
        if flow.stage == .steps || flow.ready { showSteps() } else { showVeil() }
        SetupAmbience.shared.start()
    }

    func close() {
        SetupAmbience.shared.stop()
        flow.forget()
        veil?.close()
        veil = nil
        window?.close()
        window = nil
    }

    private func showVeil() {
        if let veil {
            veil.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let screen = NSScreen.main else { return showSteps() }
        // A keyable panel, so the name field takes typing; it is dark, as an opening over the desktop should be.
        let veil = KeyablePanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        // Pinned, since a panel of this kind otherwise follows the chosen look and the opening is a dark veil in every one.
        veil.appearance = NSAppearance(named: .darkAqua)
        veil.isOpaque = false
        veil.backgroundColor = .clear
        veil.hasShadow = false
        veil.hidesOnDeactivate = false
        veil.level = .floating
        veil.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
        veil.isReleasedWhenClosed = false
        veil.contentView = NSHostingView(rootView: OnboardingIntro(flow: flow))
        veil.setFrame(screen.frame, display: true)
        self.veil = veil
        veil.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showSteps() {
        veil?.close()
        veil = nil
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Memnox"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // No traffic lights, as a first run is finished rather than dismissed; Back and the steps are the way around.
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: Layout.minWidth, height: Layout.minHeight)
        window.contentView = NSHostingView(rootView: OnboardingCard(flow: flow))
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
