import AppKit
import MemnoxVoiceCore
import SwiftUI

/// What the island is showing. The small ones sit beside the notch; the rest open 640 wide below it.
enum IslandMode: Equatable {
    /// Nothing going on: the orb rests beside the notch, breathing, and a click starts listening.
    case peek
    /// Sessions working: the orb left of the notch, one dot per working session right of it.
    case compact
    /// Talking: the orb grown large below the notch, before any words are heard.
    case voice
    /// Talking with live words on: the orb above what the person is saying, word by word as it is heard.
    case hearing
    /// A turn under way: the question above, and the answer arriving in a card below it.
    case conversation
    /// A drafted message from the person's connected mail, read whole before a signed Send.
    case draft
    /// One answer opened up tall, for a long reply or one picked from the history at the side.
    case answer
    /// A rule the person said, with where it could hold, waiting for them to pick a place and sign.
    case rule
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
    /// False only where the daemon placed the call inside its repository, so a tap allows it.
    let touchID: Bool

    init(_ event: DaemonEvent) {
        subject = event.subject
        agent = event.agent
        who = event.agentName ?? event.agent
        what = event.what ?? event.summary
        why = event.why
        summary = event.summary
        touchID = event.needsTouchID
    }
}

/// A drafted message as the island shows it, with the subject a Send signs and the words Touch ID shows.
struct DraftCard: Equatable, Sendable {
    let subject: String
    let draft: MailDraft

    var isReply: Bool { draft.draftMode == .reply }
    /// What the Touch ID sheet says it is for, so the sensor is never touched for something unnamed.
    var reason: String {
        let to = draft.to.joined(separator: ", ")
        return isReply ? "send the reply to \(to)" : "send the email to \(to)"
    }
}

/// A proposed rule as the island shows it, with the subject a confirm signs.
struct RuleCard: Equatable, Sendable {
    let subject: String
    let draft: RuleDraft
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
    /// What the person is saying right now, word by word, while live words are on.
    @Published var heard = ""
    /// The person's choice to see their words in the notch as they say them.
    @Published var liveWords = true
    @Published var history = History()
    @Published var draft: DraftCard?
    /// Set while Touch ID is up for a draft's Send or a rule's Enforce, so a second press cannot raise a second sheet.
    @Published var sending = false
    @Published var rule: RuleCard?
    /// The place picked on the rule card, the suggested one until the person picks another.
    @Published var ruleScope: String?
    /// Set while Control and Option are held, so the island says it is taking down a rule.
    @Published var ruling = false
    /// The answer opened up tall rather than in its card under the question.
    @Published var expanded = false
    /// The exchange opened from the history at the side, shown tall under the notch.
    @Published var picked: UUID?
    /// The history at the left of the screen: whether it is up, kept up, and what is typed in its search.
    @Published var sideOpen = false
    @Published var sidePinned = false
    /// The pointer touching the folded tab at the left edge, which swells it before it opens.
    @Published var sideHovering = false
    @Published var query = ""
    /// When this time talking began, so the notch shows this conversation's exchanges and not the last one's.
    var talkingSince: Date?

    var active = false
    var opened = false
    var answer: (HeldCard, HoldAnswer) -> Void = { _, _ in }
    var tapped: () -> Void = {}
    var openWindow: (String, DisplayHost?) -> Void = { _, _ in }
    var focus: (String) -> Void = { _ in }
    var openAnswer: (Exchange) -> Void = { _ in }
    var answerDraft: (DraftCard, Bool) -> Void = { _, _ in }
    var answerRule: (RuleCard, RuleScope?) -> Void = { _, _ in }
    var forgetHistory: () -> Void = {}
    var toggleSide: () -> Void = {}
    var showExchange: (UUID) -> Void = { _ in }
    var askAgain: (String) -> Void = { _ in }

    /// The exchange this conversation is on: the newest, and only once asked since talking began.
    var turn: Exchange? {
        guard let since = talkingSince, let newest = history.exchanges.first, newest.askedAt >= since else { return nil }
        return newest
    }

    /// The exchange opened from the history, which the tall answer shows when nobody is talking.
    var pickedExchange: Exchange? { history.exchanges.first { $0.id == picked } }

    /// The header holds the tabs, except while talking, when the orb sits in its row above the words.
    var showsHeader: Bool {
        switch mode {
        case .hearing, .conversation, .draft, .rule: return false
        case .answer: return !active
        case .peek, .compact: return false
        case .voice, .overview, .session, .empty, .held, .finished: return true
        }
    }

    var working: [SessionCard] { cards.filter { $0.status.isActive } }

    var focusCard: SessionCard? { cards.first { $0.sessionId == focusId } ?? cards.first }

    /// The one place the mode is decided, so no two callers disagree about what is on screen.
    func settle() {
        let next: IslandMode
        if held != nil {
            next = .held
        } else if draft != nil {
            next = .draft
        } else if rule != nil {
            next = .rule
        } else if finished != nil {
            next = .finished
        } else if active {
            // What Memnox says is heard rather than read, so a turn keeps the orb up instead of printing the answer;
            // the answer stays in the history at the side. A rule is always shown as it is said, since the person signs it.
            next = ruling || (liveWords && !heard.isEmpty) ? .hearing : .voice
        } else if opened, pickedExchange != nil {
            next = .answer
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
