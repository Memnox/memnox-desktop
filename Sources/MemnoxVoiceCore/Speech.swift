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
            let ends = spaced && ".!?".contains(pending[index])
            let pauses = spaced && !spoke && ",;:".contains(pending[index])
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
private let trailingWords: Set<String> = [
    "uh", "um", "er", "erm", "hmm", "so", "and", "but", "or", "like", "the", "a", "an", "to", "of", "with", "because",
    "i", "my", "your", "our", "was", "is", "are", "that", "if", "when", "about", "for", "in", "on", "at", "then", "which", "we", "it's", "its",
]

/// How long a pause ends what somebody is saying. A short reply like "Yes." is answered almost at
/// once, a finished question a second after it, and somebody who has been talking for a while gets
/// longer, because between two sentences of one thought people pause for more than a second, and
/// answering the first half means cancelling it and starting again, which is what feels broken.
/// "uh", "so" or a trailing "..." is somebody still thinking, so that waits longest.
public func endOfSpeechPause(after words: String) -> TimeInterval {
    let trimmed = words.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let spoken = trimmed.split(whereSeparator: { !$0.isLetter && $0 != "'" })
    let last = spoken.last.map(String.init) ?? ""
    let trailing = trimmed.hasSuffix(",") || trimmed.hasSuffix("...") || trimmed.hasSuffix("\u{2026}")
    if trailing || trailingWords.contains(last) { return 3.0 }
    let long = spoken.count > longThought
    // The recognizer only puts a full stop or a question mark on a sentence it thinks is done.
    if trimmed.hasSuffix("?") || trimmed.hasSuffix(".") || trimmed.hasSuffix("!") {
        if spoken.count <= shortReply { return 0.6 }
        // A finished question is answered sooner; a long one keeps more room, since people pause between its sentences.
        return long ? 1.5 : 0.9
    }
    // The older recognizer rarely punctuates as it goes, so an unmarked pause gets the benefit of the doubt.
    return long ? 2.0 : 1.7
}

/// How long a pause is before the words so far are sent as a guess, well short of any end of speech.
public let guessAfterPause: TimeInterval = 0.35

/// Whether a pause this long is worth starting the answer on: never while they trail off on a word
/// like "and", and only while the pause has not yet ended what they are saying.
public func mayGuess(_ words: String, pausedFor pause: TimeInterval) -> Bool {
    let ending = endOfSpeechPause(after: words)
    return words.contains(where: \.isLetter) && ending < 3.0 && pause >= guessAfterPause && pause < ending
}

/// "Yes.", "Go ahead." or "Open it.": an answer, not the start of a thought.
private let shortReply = 3
/// Past this many words somebody is explaining, and pauses between their sentences, so the
/// recognizer's full stop after the first sentence is not the end of what they mean.
private let longThought = 8

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

/// The words in a line, lowercased, for comparing what was heard with what was said.
private func wordsIn(_ text: String) -> [String] {
    text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count > 1 }
}

/// Whether a heard word is the voice's own, misheard: the same word, one inside the other, or a
/// spelling a third away, since "the session's" comes back as "possession". A short word counts
/// only when it is the very word, because "so" is a letter from "to" and "them" holds "the", and
/// fuzzy matching on those took the person's own words for its echo and talked on over them.
private func isEcho(_ word: String, of said: [String]) -> Bool {
    said.contains { spoken in
        if spoken == word { return true }
        guard word.count >= 4, spoken.count >= 4 else { return false }
        if spoken.contains(word) || word.contains(spoken) { return true }
        return editDistance(word, spoken) <= min(word.count, spoken.count) / 3
    }
}

private func editDistance(_ a: String, _ b: String) -> Int {
    let a = Array(a), b = Array(b)
    var row = Array(0...b.count)
    for i in 1...max(a.count, 1) where !a.isEmpty {
        var previous = row[0]
        row[0] = i
        for j in stride(from: 1, through: b.count, by: 1) {
            let current = row[j]
            row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (a[i - 1] == b[j - 1] ? 0 : 1))
            previous = current
        }
    }
    return a.isEmpty ? b.count : row[b.count]
}

/// Whether what the microphone heard while the voice was talking is the person rather than the
/// voice's own echo: enough words it did not just say, and most of what was heard. While it is
/// still speaking the bar is higher, since that is when its echo is loudest.
public func isBargeIn(heard: String, spoken: String, speaking: Bool = false) -> Bool {
    let said = wordsIn(spoken)
    // Only the newest words: the start of what was heard is mostly its own voice, and judging the
    // whole of it let the echo outvote the person for as long as the reply went on.
    let recent = Array(wordsIn(heard).suffix(bargeWindow))
    let novel = recent.filter { !isEcho($0, of: said) }
    // Heard opening on its own words is its echo carrying on misheard; a person cutting in opens with theirs.
    let opensWithEcho = wordsIn(heard).prefix(2).allSatisfy { isEcho($0, of: said) }
    // "Stop" or "wait" is one word and has to cut in at once; its own voice never says them unprompted.
    if novel.contains(where: { stopWords.contains($0) }) { return true }
    let needed = speaking ? (opensWithEcho ? 4 : 3) : 2
    return novel.count >= needed && Double(novel.count) >= Double(recent.count) * 0.6
}

/// Words a person says to stop the voice mid sentence, and its own name, which mean "listen to me".
private let stopWords: Set<String> = [
    "stop", "wait", "hold", "quiet", "enough", "shut", "pause", "memnox", "jarvis",
]

/// The last few words heard, which is where a person cutting in shows up.
private let bargeWindow = 6

/// What the person said once the voice's own words are taken off the front, since the
/// recognizer heard both and only the person's half is the question.
public func withoutEcho(_ heard: String, spoken: String) -> String {
    let said = wordsIn(spoken)
    var parts = heard.split(separator: " ").map(String.init)
    while let first = parts.first, let word = wordsIn(first).first, isEcho(word, of: said) {
        parts.removeFirst()
    }
    return parts.joined(separator: " ")
}

/// What was heard with its own recent words taken off either end, which is where they land when a
/// sentence it was still saying runs into the microphone before or after the person. A run of two
/// or more is echo; one word alone at an end could as well be theirs, so it stays.
public func withoutEchoRuns(_ heard: String, spoken: String) -> String {
    let said = wordsIn(spoken)
    var parts = heard.split(separator: " ").map(String.init)
    // "I'm" or "a" has no word long enough to judge, so it carries a run on without counting toward it.
    func echoes(_ part: String) -> Bool { wordsIn(part).allSatisfy { isEcho($0, of: said) } }
    func judged(_ run: ArraySlice<String>) -> Int { run.filter { !wordsIn($0).isEmpty }.count }
    let leading = parts.prefix(while: echoes)
    if judged(leading) >= 2 { parts.removeFirst(leading.count) }
    let trailing = Array(parts.reversed().prefix(while: echoes))
    if judged(trailing[...]) >= 2 { parts.removeLast(trailing.count) }
    return parts.joined(separator: " ")
}

/// What they said with "Memnox" taken off the front, since calling it by name mid conversation
/// is a greeting and not part of the question.
/// Only its name, or "hey" and its name: somebody getting its attention. Said at the end of a
/// question, as in "start a session in Memnox", the name is part of what they asked.
public func nameAlone(_ words: String) -> Bool {
    guard let rest = afterWakeWord(words), rest.isEmpty else { return false }
    return words.split(whereSeparator: \.isWhitespace).count <= 3
}

public func withoutLeadingName(_ words: String) -> String {
    guard let rest = afterWakeWord(words) else { return words }
    let before = words.prefix(words.count - rest.count)
    // Only the name first, or after one word like "hey", is a greeting; later on it is part of what they asked.
    return before.split(whereSeparator: \.isWhitespace).count <= 2 && !rest.isEmpty ? rest : words
}

/// What it says when called, the way J.A.R.V.I.S. looks up from his work: brief, composed, and
/// using the address they chose, never one guessed. The first call in a while is greeted for the
/// hour; any other is a word or two, and never the same line twice running.
public struct WakeLines {
    /// Long enough apart that being called again is a fresh start, and earns a greeting.
    public static let freshAfter: TimeInterval = 3 * 60 * 60
    private var last: String?

    public init() {}

    public mutating func line(
        address: String?,
        hour: Int,
        sinceLastCall: TimeInterval?,
        pick: ([String]) -> String? = { $0.randomElement() }
    ) -> String {
        let to = address.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
        let fresh = sinceLastCall.map { $0 >= Self.freshAfter } ?? true
        let lines = fresh ? Self.greetings(to: to, hour: hour) : Self.replies(to: to)
        let choices = lines.count > 1 ? lines.filter { $0 != last } : lines
        let chosen = pick(choices) ?? lines[0]
        last = chosen
        return chosen
    }

    private static func greetings(to: String?, hour: Int) -> [String] {
        let part = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        let named = to.map { "\(part), \($0)." } ?? "\(part)."
        return ["\(named) How shall we proceed?", "\(named) What can I do for you?", "\(named) At your service."]
    }

    private static func replies(to: String?) -> [String] {
        guard let to else {
            return ["Yes?", "At your service.", "How may I assist?", "Standing by.", "Ready for your next command."]
        }
        return [
            "Yes, \(to)?", "\(capitalizedFirst(to))?", "At your service, \(to).", "How may I assist, \(to)?",
            "Standing by, \(to).", "Ready when you are, \(to).",
        ]
    }

    private static func capitalizedFirst(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}

/// How the person asked to be addressed, kept by the runtime in `~/.memnox/voice/owner.json`; nil when
/// they chose none, which means no honorific at all.
public func chosenAddress(home: String = NSHomeDirectory()) -> String? {
    let path = (home as NSString).appendingPathComponent(".memnox/voice/owner.json")
    guard let data = FileManager.default.contents(atPath: path),
          let owner = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let address = owner["address"] as? String
    else { return nil }
    let trimmed = address.trimmingCharacters(in: .whitespaces)
    return trimmed.isEmpty ? nil : trimmed
}
