import Foundation

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
        guard word.count >= fuzzyEchoLength, spoken.count >= fuzzyEchoLength else { return false }
        if spoken.contains(word) || word.contains(spoken) { return true }
        return editDistance(word, spoken) <= min(word.count, spoken.count) / misspellingShare
    }
}

/// Shorter words match only exactly, since "so" is a letter from "to" and "them" holds "the".
private let fuzzyEchoLength = 4
/// A spelling one edit in this many letters away is still its own word misheard.
private let misspellingShare = 3

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
    let opensWithEcho = wordsIn(heard).prefix(echoOpeningWords).allSatisfy { isEcho($0, of: said) }
    // "Stop" or "wait" is one word and has to cut in at once; its own voice never says them unprompted.
    if novel.contains(where: { stopWords.contains($0) }) { return true }
    let needed = speaking ? (opensWithEcho ? BargeIn.overEcho : BargeIn.overSpeech) : BargeIn.inSilence
    return novel.count >= needed && Double(novel.count) >= Double(recent.count) * BargeIn.novelShare
}

/// How many words of the person's own it takes to call what was heard them cutting in.
private enum BargeIn {
    /// Nothing is being said, so two words of theirs are enough.
    static let inSilence = 2
    /// The voice is talking, which is when its echo is loudest.
    static let overSpeech = 3
    /// The voice is talking and what was heard opens with its own words, the likeliest echo of all.
    static let overEcho = 4
    /// Most of the recent words have to be theirs, so a stray novel word inside an echo does not count.
    static let novelShare = 0.6
}

/// The first words heard, which open with its own when the echo is carrying on.
private let echoOpeningWords = 2

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
    func isRun(_ run: [String]) -> Bool { judged(run[...]) >= echoRunLength && followsInOrder(run.flatMap(wordsIn), in: said) }
    let leading = Array(parts.prefix(while: echoes))
    if isRun(leading) { parts.removeFirst(leading.count) }
    let trailing = Array(parts.reversed().prefix(while: echoes).reversed())
    if isRun(trailing) { parts.removeLast(trailing.count) }
    return parts.joined(separator: " ")
}

/// A run this long of its own words is echo; one alone could as well be theirs.
private let echoRunLength = 2

/// Whether the words follow one another in what it said, since its echo comes back in its own order,
/// while the person's "can you" is only scattered across its "what can I do for you".
private func followsInOrder(_ words: [String], in said: [String]) -> Bool {
    func from(_ index: Int, _ rest: ArraySlice<String>) -> Bool {
        guard let word = rest.first else { return true }
        guard index < said.count else { return false }
        return (index...min(index + echoGap, said.count - 1)).contains { isEcho(word, of: [said[$0]]) && from($0 + 1, rest.dropFirst()) }
    }
    guard let first = words.first else { return false }
    return said.indices.contains { isEcho(first, of: [said[$0]]) && from($0 + 1, words.dropFirst()) }
}

/// How many of its own words an echo may drop between two it kept, since the recognizer misses some.
private let echoGap = 1
