import Foundation

/// Streamed text cut into whole sentences, the unit the voice speaks, so speech starts on the
/// first sentence rather than after the whole answer. A full stop inside "3.5" is not an end,
/// because a sentence only ends where punctuation meets a space.
public struct SentenceSplitter {
    private var pending = ""

    public init() {}

    public mutating func push(_ text: String) -> [String] {
        pending += text
        var sentences: [String] = []
        var start = pending.startIndex
        var index = pending.startIndex
        while index < pending.endIndex {
            let next = pending.index(after: index)
            if ".!?".contains(pending[index]), next < pending.endIndex, pending[next].isWhitespace {
                let sentence = pending[start...index].trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty { sentences.append(sentence) }
                start = next
            }
            index = next
        }
        pending = String(pending[start...])
        return sentences
    }

    /// Whatever is left once the turn ends, said even without a full stop.
    public mutating func flush() -> String? {
        let rest = pending.trimmingCharacters(in: .whitespacesAndNewlines)
        pending = ""
        return rest.isEmpty ? nil : rest
    }
}

/// The pill's one line: short enough to read at a glance, cut at a word.
public func caption(_ text: String, limit: Int = 40) -> String {
    let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
    guard flat.count > limit else { return flat }
    let cut = flat.prefix(limit)
    let word = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
    return "\(word)…"
}

/// `mcp__memnox-operator__sessions` as a person would read it.
public func toolWord(_ tool: String?) -> String {
    guard let tool else { return "the machine" }
    return tool.components(separatedBy: "__").last ?? tool
}

/// Words people trail off on, which mean they have not finished even when they pause.
private let trailingWords: Set<String> = ["uh", "um", "er", "erm", "so", "and", "but", "or", "like", "the", "a", "to", "of", "with", "because"]

/// How long a pause ends what somebody is saying: short after a finished question, so the reply
/// comes about a second after they stop, and longer after "uh", "so" or a trailing "...", where
/// a person is still thinking, so the question is not cut off halfway.
public func endOfSpeechPause(after words: String) -> TimeInterval {
    let trimmed = words.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let last = trimmed.split(whereSeparator: { !$0.isLetter }).last.map(String.init) ?? ""
    let trailing = trimmed.hasSuffix(",") || trimmed.hasSuffix("...") || trimmed.hasSuffix("\u{2026}")
    if trailing || trailingWords.contains(last) { return 2.6 }
    // The recognizer only puts a full stop or a question mark on a sentence it thinks is done.
    if trimmed.hasSuffix("?") || trimmed.hasSuffix(".") || trimmed.hasSuffix("!") { return 0.8 }
    return 1.2
}

/// How the recognizer spells "Memnox" before it has learned the word, run together.
private let wakeSpellings: Set<String> = ["memnox", "memnocks", "memknox", "memknocks", "mennox", "memnoks", "memnux", "menknocks", "mennocks"]

/// What followed "Memnox" when the person called it by name, empty when the name was said alone,
/// and nil when it was not said. The name only opens the orb: what follows goes whole to the brain.
public func afterWakeWord(_ words: String) -> String? {
    var tokens: [(text: String, end: String.Index)] = []
    var start: String.Index?
    for index in words.indices {
        if words[index].isLetter {
            if start == nil { start = index }
        } else if let begun = start {
            tokens.append((words[begun..<index].lowercased(), index))
            start = nil
        }
    }
    if let begun = start { tokens.append((words[begun...].lowercased(), words.endIndex)) }
    for (position, token) in tokens.enumerated() {
        var end: String.Index?
        if wakeSpellings.contains(token.text) {
            end = token.end
        } else if position + 1 < tokens.count, wakeSpellings.contains(token.text + tokens[position + 1].text) {
            // "Mem nox" and "Men knocks": the name heard as two words.
            end = tokens[position + 1].end
        }
        guard let end else { continue }
        let rest = words[end...].drop { !$0.isLetter && !$0.isNumber }
        return String(rest).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return nil
}
