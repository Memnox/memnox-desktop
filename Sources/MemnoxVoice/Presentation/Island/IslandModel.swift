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
    /// The session that is waiting, so its logo beside the notch bounces until somebody answers.
    let sessionId: String?
    /// The machine it waits on, which the header groups waiting calls by.
    let machine: String

    /// `server` names the server that raised it, so the person sees where the call waits; nil for this Mac.
    init(_ event: DaemonEvent, server: String? = nil) {
        let place = CallPlace.raised(on: server)
        subject = event.subject
        sessionId = event.sessionId
        agent = event.agent
        who = CallLabel.label(event.agentName ?? event.agent, at: place)
        what = event.what ?? event.summary
        why = event.why
        summary = event.summary
        touchID = event.needsTouchID
        machine = place.machine
    }

    /// A teammate's call the workspace routed here: named with its machine and team, and every allow asks for Touch ID.
    init(team call: WorkspaceHeldCall) {
        subject = call.id
        sessionId = nil
        agent = call.agent
        who = call.who
        what = call.what
        why = call.whyHeld
        summary = call.what
        touchID = true
        machine = call.place.machine
    }

    /// What the Touch ID sheet says this answer is for, naming the call by its one label.
    func reason(for answer: HoldAnswer) -> String {
        CallLabel.touchIDReason(who, what: what, answer: answer)
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

/// Something going out in the person's name as the island shows it, with the subject a Send signs.
struct WorkCard: Equatable, Sendable {
    let subject: String
    let draft: WorkDraft
    /// The words the person rewrote on the card, nil while they are the ones proposed.
    var edited: String?

    var reason: String { draft.touchIDReason }

    /// The same card with the words as they stand in its box, which count as rewritten only where they differ.
    func with(words: String) -> WorkCard {
        var card = self
        card.edited = words == draft.body ? nil : words
        return card
    }
}

/// A finished sign in as the pill under the notch shows it, with the proposal "that's me" signs where there is one.
struct SignedInCard: Equatable, Sendable {
    let notice: SignedInNotice

    var tool: String { ToolkitName.of(notice.toolkit) }
    var who: String? { notice.account?.shown }
    /// Nothing ties the account to the person yet, so the pill offers Not me; their first send ties it.
    var unverified: Bool { notice.account?.accountCheck != .matched }
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
    /// Every held call waiting, the one on the card and the ones behind it.
    @Published var waiting = WaitingCalls<HeldCard>()
    /// Said on the card for a moment when its call was settled somewhere else, before the card goes.
    @Published var settledNote: String?
    /// The call whose button was pressed last, so its own settling is never mistaken for an answer elsewhere.
    var pressed: String?
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
    /// Sessions whose logo is jittering for a moment, after a failure, a pause or a collision.
    @Published var stumbling: Set<String> = []
    /// What the person is saying right now, word by word, while live words are on.
    @Published var heard = ""
    /// The person's choice to see their words in the notch as they say them.
    @Published var liveWords = true
    @Published var history = History()
    @Published var draft: DraftCard?
    /// Something about to go out in the person's name in one of their tools, drawn as that tool draws it.
    @Published var work: WorkCard?
    /// The tools the person asked for and has not signed in to, as icons under the notch until they sign in.
    @Published var signIns: [ToolSignIn] = []
    /// A sign in that just finished, shown under the notch for a moment, or until they say whether it is theirs.
    @Published var signedIn: SignedInCard?
    /// Where the pills that take a click sit under the island, top left origin, so the window lets those clicks in.
    var clickableBelow: CGRect = .zero
    /// Set while Touch ID is up for a draft's Send or a rule's Enforce, so a second press cannot raise a second sheet.
    @Published var sending = false
    @Published var rule: RuleCard?
    /// The place picked on the rule card, the suggested one until the person picks another.
    @Published var ruleScope: String?
    /// Set while Control and Option are held, so the island says it is taking down a rule.
    @Published var ruling = false
    /// What to say while dictating, nil otherwise, so dictating never looks like talking to Memnox.
    @Published var dictating: String?
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
    /// A phone driving this Mac, shown under the notch in every mode until its time comes or it stops.
    @Published var driving: DriveGrant?
    /// The phone that took the voice, shown under the notch in every mode until it gives the voice back.
    @Published var voiceOn: PhoneVoice?
    /// A phone's conversation mirrored here, shown under the notch without a sound until a moment after it ends.
    @Published var phone: PhoneExchange?
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
    var answerWork: (WorkCard, Bool) -> Void = { _, _ in }
    var openSignIn: (ToolSignIn) -> Void = { _ in }
    /// Not me on the signed in pill: sign in again with their own account.
    var notMine: (SignedInCard) -> Void = { _ in }
    var answerRule: (RuleCard, RuleScope?) -> Void = { _, _ in }
    var forgetHistory: () -> Void = {}
    var toggleSide: () -> Void = {}
    var showExchange: (UUID) -> Void = { _ in }
    var askAgain: (String) -> Void = { _ in }

    /// The held call on the card now.
    var held: HeldCard? { waiting.shown }

    /// One call older for a positive offset, newer for a negative one; nothing moves while one is being signed.
    func step(_ offset: Int) {
        guard !answering, settledNote == nil else { return }
        waiting.step(offset)
    }

    /// The exchange this conversation is on: the newest, and only once asked since talking began.
    var turn: Exchange? {
        guard let since = talkingSince, let newest = history.exchanges.first, newest.askedAt >= since else { return nil }
        return newest
    }

    /// The phone's turn, while the island shows it in place of a turn of the person's own.
    var phoneTurn: PhoneExchange? { active || mode != .conversation ? nil : phone }

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
        } else if draft != nil || work != nil {
            next = .draft
        } else if rule != nil {
            next = .rule
        } else if finished != nil {
            next = .finished
        } else if active {
            // What Memnox says is heard rather than read, so a turn keeps the orb up instead of printing the answer;
            // the answer stays in the history at the side. A rule is always shown as it is said, since the person signs it.
            next = ruling || dictating != nil || (liveWords && !heard.isEmpty) ? .hearing : .voice
        } else if phone != nil {
            // The person talking here comes first; a phone's turn is only watched, so it waits behind them.
            next = .conversation
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
