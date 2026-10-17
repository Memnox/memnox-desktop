import Foundation

/// Every held call waiting on the person, so a second one joins the first rather than taking its place unseen.
/// The newest comes on screen unless the person stepped to another, and the header says how many wait and where.
public struct WaitingCalls<Card: Equatable & Sendable>: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public let subject: String
        /// The machine it waits on, as `CallPlace.machine` names it.
        public let machine: String
        public let card: Card
    }

    /// Oldest first, in the order they arrived.
    public private(set) var entries: [Entry] = []
    public private(set) var shownSubject: String?
    /// Set once the person stepped to a call, so one arriving never moves the card from under their hand.
    private var steppedTo = false

    public init() {}

    public var count: Int { entries.count }
    public var isEmpty: Bool { entries.isEmpty }
    public var shown: Card? { entries.first { $0.subject == shownSubject }?.card }

    /// Newest first, the order the person steps through them in.
    public var newestFirst: [Entry] { entries.reversed() }

    /// A call that started waiting. `keepShown` holds the card on screen still, for one being answered right now.
    public mutating func add(_ card: Card, subject: String, machine: String, keepShown: Bool = false) {
        let entry = Entry(subject: subject, machine: machine, card: card)
        // Told again, such as on a reconnect: it stays where it was in the queue.
        if let at = entries.firstIndex(where: { $0.subject == subject }) {
            entries[at] = entry
            return
        }
        entries.append(entry)
        if shownSubject == nil || !(steppedTo || keepShown) { shownSubject = subject }
    }

    /// A call that stopped waiting; the newest left comes up when it was the one shown. False when it was not here.
    @discardableResult
    public mutating func remove(_ subject: String) -> Bool {
        guard let at = entries.firstIndex(where: { $0.subject == subject }) else { return false }
        entries.remove(at: at)
        if shownSubject == subject {
            shownSubject = entries.last?.subject
            steppedTo = false
        }
        return true
    }

    /// Where the shown call stands, counted from the newest as one.
    public var position: Int? {
        newestFirst.firstIndex { $0.subject == shownSubject }.map { $0 + 1 }
    }

    public var canStepOlder: Bool { (position ?? count) < count }
    public var canStepNewer: Bool { (position ?? 1) > 1 }

    /// One call older for a positive offset, newer for a negative one, stopping at either end.
    public mutating func step(_ offset: Int) {
        let order = newestFirst
        guard let at = position.map({ $0 - 1 }), !order.isEmpty else { return }
        let next = min(max(at + offset, 0), order.count - 1)
        guard next != at else { return }
        shownSubject = order[next].subject
        steppedTo = true
    }

    /// "2 of 3", nil while only one waits.
    public var positionText: String? {
        guard count > 1, let position else { return nil }
        return "\(position) of \(count)"
    }

    /// "3 waiting: 2 on build-box, 1 on your Mac", nil while only one waits. The machine with the most comes first,
    /// and between two with as many, the one whose call came last.
    public var header: String? {
        guard count > 1 else { return nil }
        var groups: [(machine: String, count: Int, newest: Int)] = []
        for (order, entry) in entries.enumerated() {
            if let at = groups.firstIndex(where: { $0.machine == entry.machine }) {
                groups[at].count += 1
                groups[at].newest = order
            } else {
                groups.append((entry.machine, 1, order))
            }
        }
        if groups.count == 1, let only = groups.first { return "\(count) waiting on \(only.machine)" }
        let sorted = groups.sorted { ($0.count, $0.newest) > ($1.count, $1.newest) }
        return "\(count) waiting: " + sorted.map { "\($0.count) on \($0.machine)" }.joined(separator: ", ")
    }
}
