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
    /// The three grants and Memnox under the agents it found, on one page.
    case setup
    /// Two keys to try, the iPhone and the team if wanted, and the button that starts Memnox.
    case ready

    var id: Int { rawValue }
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
    @Published var team: TeamModel?
    /// Told when the opening hands over to the window, so the controller swaps one window for the other.
    var opened: (() -> Void)?

    func next() {
        guard let following = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        step = following
    }

    func back() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    /// The opening is done, by a name given or by skipping it, and the steps take over.
    func openSteps() {
        stage = .steps
        opened?()
    }
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
        flow.team = SettingsWindow.shared.team
        if flow.stage == .steps { showSteps() } else { showVeil() }
    }

    func close() {
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
