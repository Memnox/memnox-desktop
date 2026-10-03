import AppKit
import MemnoxVoiceCore
import SwiftUI

/// What the island is showing. The small ones sit beside the notch; the rest open 640 wide below it.
enum IslandMode: Equatable {
    /// Nothing going on: the orb rests beside the notch, breathing, and a click starts listening.
    case peek
    /// Sessions working: the orb left of the notch, one dot per working session right of it.
    case compact
    /// Talking: the orb grown large below the notch, with what was heard or said under it.
    case voice
    /// Opened by the pointer: the session in focus, what it is doing, and every other session as a pill.
    case overview
    /// One session up close: what it did and the code it is writing.
    case session
    /// Opened by the pointer with nothing running.
    case empty
    /// An agent is waiting on the person, with the buttons to answer it.
    case held
    /// A session just finished, shown for a few seconds and then put away.
    case finished

    var isOpen: Bool { self != .peek && self != .compact }
}

/// A held call as the island shows it, taken from the daemon's event.
struct HeldCard: Equatable, Sendable {
    let subject: String
    let agent: String
    let who: String
    let what: String
    let why: String?
    let summary: String

    init(_ event: DaemonEvent) {
        subject = event.subject
        agent = event.agent
        who = event.agentName ?? event.agent
        what = event.what ?? event.summary
        why = event.why
        summary = event.summary
    }
}

/// A session that just finished, from the daemon's notice.
struct FinishedCard: Equatable, Sendable {
    let agent: String
    let who: String
    let summary: String
    let sessionId: String?
    let host: DisplayHost?

    init(_ event: DaemonEvent) {
        agent = event.agent
        who = event.agentName ?? event.agent
        summary = event.summary
        sessionId = event.sessionId
        host = event.host
    }
}

/// Where the notch is on this screen, or a small bar standing in for one on a Mac without it.
struct NotchGeometry: Equatable {
    let width: CGFloat
    let height: CGFloat
    let hasNotch: Bool

    /// A typical notch, assumed until the island is placed on a real screen.
    fileprivate static let beforePlacement = NotchGeometry(width: 185, height: 32, hasNotch: true)
    /// The bar that stands in for a notch on a Mac without one: this wide, and no taller than this.
    private static let standInWidth: CGFloat = 80
    private static let standInMaxHeight: CGFloat = 24

    static func of(_ screen: NSScreen) -> NotchGeometry {
        let top = screen.safeAreaInsets.top
        if top > 0, let left = screen.auxiliaryTopLeftArea?.width, let right = screen.auxiliaryTopRightArea?.width {
            return NotchGeometry(width: screen.frame.width - left - right, height: top, hasNotch: true)
        }
        let bar = screen.frame.maxY - screen.visibleFrame.maxY
        return NotchGeometry(
            width: standInWidth, height: min(bar > 0 ? bar : NSStatusBar.system.thickness, standInMaxHeight), hasNotch: false
        )
    }
}

/// Everything the island draws, kept apart from the window so the view only reads it.
@MainActor
final class IslandModel: ObservableObject {
    @Published private(set) var mode: IslandMode = .peek
    @Published var state: VoiceState = .idle
    @Published var caption = ""
    @Published var held: HeldCard?
    @Published var finished: FinishedCard?
    /// Set while Touch ID is up for a button, so a second press cannot raise a second sheet.
    @Published var answering = false
    @Published var notch = NotchGeometry.beforePlacement
    @Published var hovering = false
    /// Every recent session, working ones first, and the one the open island is about.
    @Published var cards: [SessionCard] = []
    @Published var focusId: String?
    @Published var focused: SessionView?
    /// Whether the open island shows one session up close rather than all of them.
    @Published var detail = false
    /// Flipped on just after the island opens, so the pills arrive one after another.
    @Published var revealed = false
    /// From one down to nothing over the last ten seconds before the open island puts itself away.
    @Published var countdown: CGFloat?
    @Published var hops = 0
    @Published var shakes = 0

    var active = false
    var opened = false
    var answer: (String, HoldAnswer, String) -> Void = { _, _, _ in }
    var tapped: () -> Void = {}
    var openWindow: (String, DisplayHost?) -> Void = { _, _ in }
    var focus: (String) -> Void = { _ in }

    var working: [SessionCard] { cards.filter { $0.status.isActive } }

    var focusCard: SessionCard? { cards.first { $0.sessionId == focusId } ?? cards.first }

    /// The one place the mode is decided, so no two callers disagree about what is on screen.
    func settle() {
        let next: IslandMode
        if held != nil {
            next = .held
        } else if finished != nil {
            next = .finished
        } else if active {
            next = .voice
        } else if opened {
            next = cards.isEmpty ? .empty : detail && focused != nil ? .session : .overview
        } else {
            next = working.isEmpty ? .peek : .compact
        }
        guard next != mode else { return }
        let growing = Island.area(next, notch) > Island.area(mode, notch)
        withAnimation(Island.motion(growing: growing)) { mode = next }
        if next == .overview {
            revealed = false
            DispatchQueue.main.async { [weak self] in self?.revealed = true }
        }
    }

    func size(of mode: IslandMode) -> CGSize { Island.size(mode, notch) }
}
