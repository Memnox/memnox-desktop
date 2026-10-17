import Foundation

/// One turn of a phone's conversation as the island shows it: which phone, what was said, and the answer so far.
public struct PhoneExchange: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let deviceId: String
    public let name: String
    /// Nil when the turn's start was missed, such as when this app opened halfway through it.
    public let said: String?
    public private(set) var answer: String
    public let startedAt: Date
    /// When ended arrived; nil while the answer is still coming.
    public private(set) var endedAt: Date?

    public init(id: UUID = UUID(), deviceId: String, name: String, said: String?, answer: String = "", startedAt: Date, endedAt: Date? = nil) {
        self.id = id
        self.deviceId = deviceId
        self.name = name
        self.said = said
        self.answer = answer
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    public var isAnswering: Bool { endedAt == nil }

    /// Who is talking, with a plain word when the phone gave no name.
    public var label: String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return "From \(name.isEmpty ? "your phone" : name)"
    }

    /// The same turn as the island's answer card reads one, so a phone's turn looks like the person's own.
    public var exchange: Exchange {
        Exchange(id: id, question: said ?? "", answer: answer, askedAt: startedAt, answeredAt: endedAt)
    }

    mutating func add(_ text: String) {
        answer += text
    }

    mutating func end(at moment: Date) {
        guard endedAt == nil else { return }
        endedAt = moment
    }
}

/// Puts a phone's turn together from the notices the daemon mirrors: said starts one, answer chunks add to it,
/// and ended closes it. Only the newest turn is kept, since the island shows one at a time.
public struct PhoneConversation: Equatable, Sendable {
    public private(set) var current: PhoneExchange?

    public init() {}

    /// The turn as it stands after this notice, or nil when the notice changed nothing worth showing.
    public mutating func take(_ turn: PhoneTurn, at moment: Date) -> PhoneExchange? {
        let said = Self.words(turn.said)
        let chunk = turn.answer.flatMap { $0.isEmpty ? nil : $0 }
        let open = current.flatMap { $0.deviceId == turn.deviceId && $0.isAnswering ? $0 : nil }
        var next: PhoneExchange
        if let said {
            next = PhoneExchange(deviceId: turn.deviceId, name: turn.name, said: said, startedAt: moment)
        } else if let open {
            next = open
        } else if chunk != nil {
            // The start was missed, so the answer is still shown, under no question.
            next = PhoneExchange(deviceId: turn.deviceId, name: turn.name, said: nil, startedAt: moment)
        } else {
            return nil
        }
        if let chunk { next.add(chunk) }
        if turn.ended == true { next.end(at: moment) }
        guard next != current else { return nil }
        current = next
        return next
    }

    /// Absence is nil, and words that are only spaces are no words.
    private static func words(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}
