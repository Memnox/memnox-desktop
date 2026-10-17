import Foundation

/// The answer that settled a held call or a proposal before this one reached the daemon. The first
/// answer is what happened, so a second press reports it rather than sounding like it took.
public struct EarlierAnswer: Equatable, Sendable {
    /// The daemon's word for the first answer, nil when it no longer says which.
    public let word: String?

    public init(word: String?) {
        self.word = word
    }

    /// Read from a confirm's reply: `already answered deny` for a held call, `already declined` for a
    /// proposal, or a held call its agent has already taken away. Nil when this answer was the one that counted.
    public init?(ok: Bool, outcome: String?, error: String?) {
        if ok, let outcome, outcome.hasPrefix(Self.alreadyPrefix) {
            var rest = outcome.dropFirst(Self.alreadyPrefix.count).trimmingCharacters(in: .whitespaces)
            if rest.hasPrefix(Self.answeredWord) {
                rest = rest.dropFirst(Self.answeredWord.count).trimmingCharacters(in: .whitespaces)
            }
            self.word = rest.isEmpty ? nil : rest
            return
        }
        // Answered and released already, so the daemon no longer knows which answer it was.
        if !ok, let error, error.hasSuffix(Self.noLongerHeld) {
            self.word = nil
            return
        }
        return nil
    }

    /// Whether the first answer was the same as the one just given, so nothing needs saying.
    public func matches(_ chosen: String) -> Bool {
        word == chosen
    }

    /// What the person hears instead of the outcome of their own press.
    public var line: String {
        // Without the word it may have timed out rather than been answered, so it claims neither.
        guard let word, let phrase = Self.phrases[word] else { return "That was settled before your answer arrived, so nothing changed." }
        return "That was already answered elsewhere: it was \(phrase)."
    }

    /// How the daemon begins an outcome for a call or proposal answered before.
    private static let alreadyPrefix = "already "
    /// The word a held call's outcome puts before the answer, which a proposal's leaves out.
    private static let answeredWord = "answered"
    /// How the daemon ends the refusal for a held call whose record is gone.
    private static let noLongerHeld = " is no longer held"
    /// Each answer word the daemon sends, as it is said aloud.
    private static let phrases: [String: String] = [
        HoldAnswer.deny.rawValue: "denied",
        HoldAnswer.once.rawValue: "allowed once",
        HoldAnswer.session.rawValue: "allowed for the session",
        ProposalAnswer.confirmed.rawValue: "confirmed",
        ProposalAnswer.declined.rawValue: "declined",
    ]
}

extension EarlierAnswer {
    /// Read from a whole reply, nil when there was none.
    public init?(_ response: DaemonResponse?) {
        guard let response else { return nil }
        self.init(ok: response.ok, outcome: response.outcome, error: response.error)
    }
}
