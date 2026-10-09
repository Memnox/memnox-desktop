import Foundation

/// How the recognizer spells "Memnox" before it has learned the word, run together.
private let wakeSpellings: Set<String> = [
    "memnox", "memnocks", "memknox", "memknocks", "mennox", "memnoks", "memnux", "menknocks", "mennocks",
    "maamknox", "mamknox", "manknox", "menknox", "maamnox", "mamnox", "mamnocks", "manknocks", "memnoxs",
    // Heard on a real Mac: "Emma Knox", "MM Nox", "M Knox", "Minnox".
    "emmaknox", "mmnox", "mmknox", "mknox", "minnox", "emnox", "emknox",
]

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
        } else if position + 2 < tokens.count,
                  wakeSpellings.contains(token.text + tokens[position + 1].text + tokens[position + 2].text) {
            // "Ma'am Knox": the apostrophe splits the first half in two.
            end = tokens[position + 2].end
        }
        guard let end else { continue }
        let rest = words[end...].drop { !$0.isLetter && !$0.isNumber }
        return String(rest).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return nil
}

/// What they said with "Memnox" taken off the front, since calling it by name mid conversation
/// is a greeting and not part of the question.
/// Only its name, or "hey" and its name: somebody getting its attention. Said at the end of a
/// question, as in "start a session in Memnox", the name is part of what they asked.
public func nameAlone(_ words: String) -> Bool {
    guard let rest = afterWakeWord(words), rest.isEmpty else { return false }
    return words.split(whereSeparator: \.isWhitespace).count <= nameAloneWords
}

/// "Hey Memnox" heard as up to three words, since the recognizer may split the name in two.
private let nameAloneWords = 3
/// One word before the name, like "hey", still makes it a greeting.
private let greetingWordsBeforeName = 2

public func withoutLeadingName(_ words: String) -> String {
    guard let rest = afterWakeWord(words) else { return words }
    let before = words.prefix(words.count - rest.count)
    // Only the name first, or after one word like "hey", is a greeting; later on it is part of what they asked.
    return before.split(whereSeparator: \.isWhitespace).count <= greetingWordsBeforeName && !rest.isEmpty ? rest : words
}

/// The words after its name, once its own recent sentences are taken off, so a greeting it says
/// with "Memnox" in it never wakes it. Nil when the name was only ever in its own voice.
public func afterWakeWord(_ words: String, spoken: String) -> String? {
    afterWakeWord(withoutEchoRuns(words, spoken: spoken))
}
