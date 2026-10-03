import Foundation

/// Streamed text cut into whole sentences, the unit the voice speaks, so speech starts on the
/// first sentence rather than after the whole answer. A full stop inside "3.5" is not an end,
/// because a sentence only ends where punctuation meets a space.
public struct SentenceSplitter {
    private var pending = ""
    /// A short sentence held to be said with the next, since "Proposed." alone sounds clipped.
    private var carried = ""
    /// Shorter than this and a sentence rides with the one after it.
    private static let joinBelow = 16
    /// The first piece of a reply may end at a comma once it has this many words, since the voice
    /// is silent until something is said and the rest streams in while it speaks.
    private static let firstClauseWords = 4
    /// Marks that end a sentence when a space follows them.
    private static let sentenceEnds = ".!?"
    /// Marks the first piece of a reply may end at, so the voice starts sooner.
    private static let clauseBreaks = ",;:"
    private var spoke = false

    public init() {}

    public mutating func push(_ text: String) -> [String] {
        pending += text
        var sentences: [String] = []
        var start = pending.startIndex
        var index = pending.startIndex
        while index < pending.endIndex {
            let next = pending.index(after: index)
            let spaced = next < pending.endIndex && pending[next].isWhitespace
            let ends = spaced && Self.sentenceEnds.contains(pending[index])
            let pauses = spaced && !spoke && Self.clauseBreaks.contains(pending[index])
            if ends || pauses {
                let sentence = pending[start...index].trimmingCharacters(in: .whitespacesAndNewlines)
                let joined = carried.isEmpty ? sentence : "\(carried) \(sentence)"
                if pauses, !ends, words(in: joined) < Self.firstClauseWords {
                    index = next
                    continue
                }
                if !sentence.isEmpty {
                    if joined.count < Self.joinBelow {
                        carried = joined
                    } else {
                        sentences.append(joined)
                        carried = ""
                        spoke = true
                    }
                }
                start = next
            }
            index = next
        }
        pending = String(pending[start...])
        return sentences
    }

    /// Whatever is left once the turn ends, said even without a full stop.
    public mutating func flush() -> String? {
        let rest = [carried, pending.trimmingCharacters(in: .whitespacesAndNewlines)]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        pending = ""
        carried = ""
        spoke = false
        return rest.isEmpty ? nil : rest
    }

    private func words(in text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}
