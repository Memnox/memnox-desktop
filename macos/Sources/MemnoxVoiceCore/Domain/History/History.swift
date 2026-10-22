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
    /// What was read back after each action this answer took, the evidence beside what it says.
    public private(set) var proofs: [Proof]
    /// What the turn did in the world, so the side panel lists what was done rather than what was said.
    public private(set) var actions: [TakenAction]

    public init(id: UUID = UUID(), question: String, answer: String = "", askedAt: Date, answeredAt: Date? = nil,
                failure: String? = nil, proofs: [Proof] = [], actions: [TakenAction] = []) {
        self.id = id
        self.question = question
        self.answer = answer
        self.askedAt = askedAt
        self.answeredAt = answeredAt
        self.failure = failure
        self.proofs = proofs
        self.actions = actions
    }

    private enum CodingKeys: String, CodingKey { case id, question, answer, askedAt, answeredAt, failure, proofs, actions }

    /// A history saved before proofs were kept reads with none, rather than failing to read at all.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        question = try container.decode(String.self, forKey: .question)
        answer = try container.decode(String.self, forKey: .answer)
        askedAt = try container.decode(Date.self, forKey: .askedAt)
        answeredAt = try container.decodeIfPresent(Date.self, forKey: .answeredAt)
        failure = try container.decodeIfPresent(String.self, forKey: .failure)
        proofs = try container.decodeIfPresent([Proof].self, forKey: .proofs) ?? []
        actions = try container.decodeIfPresent([TakenAction].self, forKey: .actions) ?? []
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

    mutating func prove(_ proof: Proof) {
        proofs.append(proof)
    }

    mutating func act(_ action: TakenAction) {
        actions.append(action)
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
            || actions.contains { $0.mentions(wanted) }
    }
}

/// One thing a turn did: an agent started or told, a page opened, a message sent in the person's name.
public struct TakenAction: Codable, Equatable, Sendable {
    /// The tool as `toolWord` reads it, such as start_session, or the toolkit's own slug, such as SLACK_SEND_MESSAGE.
    public let tool: String
    /// The toolkit it went out through in the person's name, nil for Memnox's own tools.
    public let toolkit: String?
    /// The drafted kind of a send, such as message or event, so the row says what went out.
    public let kind: String?
    /// Whom or what it was about, such as #launch or a subject line, for the row's second line.
    public let about: String?
    public let at: Date

    public init(tool: String, toolkit: String? = nil, kind: String? = nil, about: String? = nil, at: Date) {
        self.tool = tool
        self.toolkit = toolkit
        self.kind = kind
        self.about = about?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? about : nil
        self.at = at
    }

    /// Whether the words appear in what it was about or the tool it used, for the side panel's search.
    public func mentions(_ words: String) -> Bool {
        [tool, toolkit, about].compactMap { $0 }.contains { $0.localizedStandardContains(words) }
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

    /// What an action this turn left behind, kept on the newest exchange, which is the turn that acted.
    public mutating func prove(_ proof: Proof) {
        guard !exchanges.isEmpty else { return }
        exchanges[0].prove(proof)
    }

    /// Something the newest turn did, kept on it like its proofs, even once its words have ended.
    public mutating func act(_ action: TakenAction) {
        guard !exchanges.isEmpty else { return }
        exchanges[0].act(action)
    }

    /// The reply ended. A failure is kept with its reason, so the question can be asked again; an exchange
    /// that simply got no words and did nothing is dropped, since it is nothing to look back on.
    public mutating func end(at moment: Date, failure: String? = nil) {
        guard current != nil else { return }
        if failure == nil, exchanges[0].actions.isEmpty, exchanges[0].answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
