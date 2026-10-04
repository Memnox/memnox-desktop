import Foundation

/// One thing the person asked and what came back, kept as written so the notch can lay out its markdown.
public struct Exchange: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let question: String
    public private(set) var answer: String
    public let askedAt: Date
    /// When the reply ended; nil while it is still arriving.
    public private(set) var answeredAt: Date?
    /// Why no answer came, in words a person can act on; nil when one did.
    public private(set) var failure: String?

    public init(id: UUID = UUID(), question: String, answer: String = "", askedAt: Date, answeredAt: Date? = nil, failure: String? = nil) {
        self.id = id
        self.question = question
        self.answer = answer
        self.askedAt = askedAt
        self.answeredAt = answeredAt
        self.failure = failure
    }

    public var isAnswering: Bool { answeredAt == nil }
    public var failed: Bool { failure != nil }

    /// How long the reply took, or has taken so far when it is still arriving.
    public func elapsed(now: Date) -> TimeInterval {
        (answeredAt ?? now).timeIntervalSince(askedAt)
    }

    mutating func add(_ text: String) {
        answer += text
    }

    mutating func end(at moment: Date, failure reason: String? = nil) {
        guard answeredAt == nil else { return }
        answeredAt = moment
        failure = reason
    }

    /// Whether the words appear in the question or the answer, ignoring case and accents, for a search box.
    public func mentions(_ words: String) -> Bool {
        let wanted = words.trimmingCharacters(in: .whitespacesAndNewlines)
        return wanted.isEmpty || question.localizedStandardContains(wanted) || answer.localizedStandardContains(wanted)
    }
}

/// The exchanges lately, newest first, so the notch can show what was asked and answered after the voice has moved on.
public struct History: Codable, Equatable, Sendable {
    /// Enough to scroll back through a day of questions, and small enough to read from disk at once.
    public static let kept = 60
    public private(set) var exchanges: [Exchange]

    public init(exchanges: [Exchange] = []) {
        self.exchanges = Array(exchanges.prefix(Self.kept))
    }

    /// The exchange still arriving, which is always the newest when there is one.
    public var current: Exchange? { exchanges.first.flatMap { $0.isAnswering ? $0 : nil } }

    /// A new question: any reply left open ends now, since only one turn runs at a time.
    public mutating func ask(_ question: String, at moment: Date) {
        let words = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        end(at: moment)
        exchanges.insert(Exchange(question: words, askedAt: moment), at: 0)
        if exchanges.count > Self.kept { exchanges.removeLast(exchanges.count - Self.kept) }
    }

    /// More of the reply, added to the exchange still arriving and dropped when none is.
    public mutating func reply(_ text: String) {
        guard current != nil, !text.isEmpty else { return }
        exchanges[0].add(text)
    }

    /// The reply ended. A failure is kept with its reason, so the question can be asked again; an exchange
    /// that simply got no words is dropped, since an empty answer is nothing to look back on.
    public mutating func end(at moment: Date, failure: String? = nil) {
        guard current != nil else { return }
        if failure == nil, exchanges[0].answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            exchanges.removeFirst()
            return
        }
        exchanges[0].end(at: moment, failure: failure)
    }

    /// The exchanges that mention the words, newest first; all of them when nothing is typed.
    public func matching(_ words: String) -> [Exchange] {
        exchanges.filter { $0.mentions(words) }
    }

    public mutating func forget() {
        exchanges.removeAll()
    }
}
