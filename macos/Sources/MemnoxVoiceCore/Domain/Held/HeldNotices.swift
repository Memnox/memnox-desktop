import Foundation

/// One held call as a notification needs it: which call, who waits, and on what.
public struct NoticeCall: Equatable, Sendable {
    public let subject: String
    /// Who waits, such as "Claude Code" or "Claude Code on build-box".
    public let label: String
    /// The exact command or call, as its card shows it.
    public let what: String

    public init(subject: String, label: String, what: String) {
        self.subject = subject
        self.label = label
        self.what = what
    }
}

public struct HeldNotice: Equatable, Sendable {
    /// The call it is for, so a later one can be told apart.
    public let subject: String
    public let title: String
    public let body: String

    public init(_ call: NoticeCall) {
        subject = call.subject
        title = "\(call.label) is waiting on you"
        body = call.what
    }
}

/// The system notification for a held call, mirrored from `held-notices.ts`: one per call, identical holds folded into
/// the first, none for the call the island is already showing, and a click opens Governance on Approvals. It says what
/// waits and never answers it, since a yes is signed on the card and nowhere else.
public struct HeldNotices: Sendable {
    /// Whether the person wants them, kept with the app's other switches; on unless turned off.
    public static let key = "memnox.notices.held"
    /// Set once the system was asked, so it is asked once, from Settings or the first held call, and never at launch.
    public static let askedKey = "memnox.notices.asked"
    public static let title = "Tell me when a call waits"
    public static let detail = "A system notification for each call held for you that the island is not already showing. Pressing it opens Approvals."
    public static let denied = "Notifications are turned off for Memnox in the system settings, so none can be shown."
    /// Where a click on one lands.
    public static let opens = WindowRoute(.governance, tab: "approvals")

    private var met: Set<String> = []
    /// The holds a notification or the island has already put in front of the person, while any call of them waits.
    private var said: Set<String> = []

    public init() {}

    /// The notifications to post for the calls waiting now, oldest first, given the one the island shows, if it is showing one.
    public mutating func next(_ waiting: [NoticeCall], onIsland: String?) -> [HeldNotice] {
        let waitingNow = Set(waiting.map(\.subject))
        met = met.filter { waitingNow.contains($0) }
        let holdsNow = Set(waiting.map(Self.sameHold))
        said = said.filter { holdsNow.contains($0) }
        var posted: [HeldNotice] = []
        for call in waiting {
            guard met.insert(call.subject).inserted else { continue }
            guard said.insert(Self.sameHold(call)).inserted else { continue }
            if call.subject != onIsland { posted.append(HeldNotice(call)) }
        }
        return posted
    }

    /// Two calls are the same hold when the same agent waits on the same thing.
    private static func sameHold(_ call: NoticeCall) -> String {
        "\(call.label)\u{0}\(call.what)"
    }
}
