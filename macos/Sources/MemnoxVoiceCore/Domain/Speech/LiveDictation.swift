import Foundation

/// One change to the words already typed live: everything up to `kept` stays, `removed` is taken back from the end,
/// then `added` is typed. Only the part that differs is touched, so a word the recognizer revised is fixed in place
/// and the rest of the sentence never flickers.
public struct LiveRevision: Equatable, Sendable {
    public let kept: String
    public let removed: String
    public let added: String

    public var isEmpty: Bool { removed.isEmpty && added.isEmpty }
}

/// The smallest change from what is typed to what should be there, by whole characters, so an accent or an emoji
/// is never split.
public func liveRevision(from typed: String, to wanted: String) -> LiveRevision {
    var shared = typed.startIndex
    var other = wanted.startIndex
    while shared < typed.endIndex, other < wanted.endIndex, typed[shared] == wanted[other] {
        shared = typed.index(after: shared)
        other = wanted.index(after: other)
    }
    return LiveRevision(kept: String(typed[..<shared]), removed: String(typed[shared...]), added: String(wanted[other...]))
}

/// Words written around the cursor that the recognizer would not know: names, acronyms and words with digits, so a
/// reply about "Postgres" or "ORB-12" hears them as they are written there. Common words are left out, since
/// a hint only helps a word the recognizer would otherwise get wrong.
public func cursorHints(before: String?, after: String?, most: Int = cursorHintLimit) -> [String] {
    let text = [before, after].compactMap { $0 }.joined(separator: " ")
    var seen = Set<String>()
    var hints: [String] = []
    for raw in text.split(whereSeparator: { $0.isWhitespace }) {
        let word = raw.trimmingCharacters(in: .punctuationCharacters.subtracting(CharacterSet(charactersIn: "-_.")))
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard word.count >= shortestHint, isUnusual(word), seen.insert(word.lowercased()).inserted else { continue }
        hints.append(word)
        if hints.count == most { break }
    }
    return hints
}

/// Enough hints to cover a message's names, few enough to leave room for the person's own words.
public let cursorHintLimit = 20
/// Shorter than this is too easily a word heard by chance.
private let shortestHint = 3

/// A capital after the first letter, a digit, or a capitalised word that is not "I" or a sentence opener in common use.
private func isUnusual(_ word: String) -> Bool {
    guard word.contains(where: \.isLetter) else { return false }
    if word.contains(where: \.isNumber) { return true }
    if word.dropFirst().contains(where: \.isUppercase) { return true }
    guard word.first?.isUppercase == true else { return false }
    return !commonOpeners.contains(word.lowercased())
}

/// Words that start sentences everywhere, so their capital says nothing about being a name.
private let commonOpeners: Set<String> = [
    "the", "this", "that", "these", "those", "and", "but", "for", "can", "could", "would", "should", "will", "please",
    "thanks", "thank", "hello", "dear", "yes", "not", "what", "when", "where", "why", "how", "who", "which", "there",
    "here", "then", "also", "just", "let", "lets", "let's", "you", "your", "our", "its", "it's", "they", "we", "she",
    "his", "her", "him", "hey", "best", "regards", "cheers", "sure", "okay", "great", "good", "all", "any", "some",
]
