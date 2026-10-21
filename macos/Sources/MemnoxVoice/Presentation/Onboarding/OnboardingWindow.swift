import AppKit
import SwiftUI

/// Where the first run stands: the opening over the whole screen, the name asked there, then the window that walks
/// through each thing Memnox does and turns it on.
enum OnboardingStage: Equatable {
    case intro
    case name
    case steps
}

/// The steps of the window in order, kept to three so setting up never feels like a chore; the notch plays beside all of them.
enum OnboardingStep: Int, CaseIterable, Identifiable {
    /// What Memnox does, each part played on the real notch.
    case welcome
    /// The four grants and Memnox under the agents it found, on one page.
    case setup
    /// Two keys to try, the iPhone and the sign in if wanted, and the button that starts Memnox.
    case ready

    var id: Int { rawValue }

    /// The step's name under the progress bar, so a new person always knows where they are and what is left.
    var title: String {
        switch self {
        case .welcome: return "What Memnox does"
        case .setup: return "Set up this Mac"
        case .ready: return "Try it"
        }
    }
}

/// The first run's state, shared by the opening and the window so the name typed in one is the name in the other.
@MainActor
final class OnboardingFlow: ObservableObject {
    @Published var stage: OnboardingStage = .intro
    @Published var step: OnboardingStep = .welcome
    /// The part of Memnox the notch beside the steps is playing, lit on the welcome step.
    @Published var highlight: Highlight?
    @Published var setup: SetupModel?
    @Published var menu: MenuModel?
    @Published var account: AccountModel?
    /// Told when the opening hands over to the window, so the controller swaps one window for the other.
    var opened: (() -> Void)?
    /// A part of the welcome the person clicked, which the notch jumps to and plays from.
    @Published private(set) var jump: HighlightJump?
    /// The parts the guide has already spoken, so the notch going round again stays quiet.
    var narrated: Set<Highlight> = []

    /// The step the window was on, kept so a reopen for Screen Recording comes back to the same page.
    private static let stepKey = "onboardingStep"

    func next() {
        guard let following = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        step = following
        remember()
    }

    func back() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
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
        stage = .steps
    }

    /// Forgets the step, once the first run is over.
    func forget() {
        UserDefaults.standard.removeObject(forKey: Self.stepKey)
        UserDefaults.standard.removeObject(forKey: Self.guidedKey)
    }

    /// Plays one part of the welcome on the notch now, and says what it is.
    func pick(_ part: Highlight) {
        narrated.insert(part)
        jump = HighlightJump(part: part)
        setup?.guide(part.spoken)
    }

    /// True the first time a step opens in this first run, so a restart for Screen Recording does not hear it again.
    func firstVisit(_ step: OnboardingStep) -> Bool {
        var guided = Set(UserDefaults.standard.array(forKey: Self.guidedKey) as? [Int] ?? [])
        guard guided.insert(step.rawValue).inserted else { return false }
        UserDefaults.standard.set(Array(guided), forKey: Self.guidedKey)
        return true
    }

    /// The steps the guide has introduced, kept across the restart Screen Recording needs.
    private static let guidedKey = "onboardingGuided"

    private func remember() {
        UserDefaults.standard.set(step.rawValue, forKey: Self.stepKey)
    }
}

/// A click on one part of the welcome, new each time so clicking the same part twice still plays it again.
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
        if flow.stage == .steps { showSteps() } else { showVeil() }
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
