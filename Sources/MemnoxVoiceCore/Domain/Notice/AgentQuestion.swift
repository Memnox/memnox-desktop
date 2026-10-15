import Foundation

/// One question an agent put to its person in its own picker, as the runtime's `AgentQuestionItem` carries it.
public struct AgentQuestionItem: Decodable, Equatable, Sendable {
    public let question: String
    public let header: String?
    public let options: [AgentQuestionOption]
    public let multiSelect: Bool

    public init(question: String, header: String? = nil, options: [AgentQuestionOption], multiSelect: Bool = false) {
        self.question = question
        self.header = header
        self.options = options
        self.multiSelect = multiSelect
    }

    private enum CodingKeys: String, CodingKey { case question, header, options, multiSelect }

    /// Lenient past the question itself, so a daemon that leaves a field out still shows the choices it sent.
    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        question = try fields.decode(String.self, forKey: .question)
        header = try fields.decodeIfPresent(String.self, forKey: .header)
        options = try fields.decodeIfPresent([AgentQuestionOption].self, forKey: .options) ?? []
        multiSelect = try fields.decodeIfPresent(Bool.self, forKey: .multiSelect) ?? false
    }
}

public struct AgentQuestionOption: Decodable, Equatable, Sendable {
    public let label: String
    public let description: String?

    public init(label: String, description: String? = nil) {
        self.label = label
        self.description = description
    }
}

/// An agent's question as the island asks it: which of its questions is next, and what a pick sends.
public struct AgentQuestionCard: Equatable, Sendable {
    public let subject: String
    public let agent: String
    public let who: String
    public let questions: [AgentQuestionItem]
    /// What is picked so far by question text, from the daemon and from taps here, so nothing is asked twice.
    public private(set) var answers: [String: String]

    /// How the runtime's picker joins several picks into one answer.
    public static let pickSeparator = ", "

    /// Nil for any event that is not an agent's question with something to pick, which stays spoken only.
    public init?(_ event: DaemonEvent) {
        guard event.noticeKind == .question, let questions = event.questions, !questions.isEmpty else { return nil }
        subject = event.subject
        agent = event.agent
        who = event.agentName ?? event.agent
        self.questions = questions
        answers = event.answers ?? [:]
    }

    /// The first question nothing has answered yet, numbered from one as the daemon counts them.
    public var next: (number: Int, item: AgentQuestionItem)? {
        guard let index = questions.firstIndex(where: { answers[$0.question] == nil }) else { return nil }
        return (index + 1, questions[index])
    }

    /// How far along, such as "2 of 3", only when there is more than one question.
    public var position: String? {
        guard questions.count > 1, let next else { return nil }
        return "\(next.number) of \(questions.count)"
    }

    /// The one answer several picks make, in the order the agent listed them.
    public static func joined(_ picked: Set<String>, from item: AgentQuestionItem) -> String {
        item.options.map(\.label).filter(picked.contains).joined(separator: pickSeparator)
    }

    /// The same card with one more answer taken, which moves it on to the next question.
    public func answering(_ number: Int, with answer: String) -> AgentQuestionCard {
        guard questions.indices.contains(number - 1) else { return self }
        var card = self
        card.answers[questions[number - 1].question] = answer
        return card
    }
}
