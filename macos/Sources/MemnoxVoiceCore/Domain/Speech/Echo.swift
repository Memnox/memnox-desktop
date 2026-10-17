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
        // Its "asks" comes back as "ask", and a plural ending is never how "the" turns into "them".
        if spoken == word + "s" || word == spoken + "s" { return true }
        guard word.count >= fuzzyEchoLength, spoken.count >= fuzzyEchoLength else { return false }
        if spoken.contains(word) || word.contains(spoken) { return true }
        // Its "write" comes back as "right" and "there" as "their": spelled apart, said alike.
        if soundKey(word) == soundKey(spoken) { return true }
        return editDistance(word, spoken) <= min(word.count, spoken.count) / misspellingShare
    }
}

/// How a word sounds rather than how it is spelled: silent letters off, alike sounds as one letter,
/// and every run of vowels as one, so homophones the recognizer swaps share a key.
private func soundKey(_ word: String) -> String {
    var text = word
    for (from, to) in soundsAlike where text.hasPrefix(from) {
        text = to + text.dropFirst(from.count)
        break
    }
    for (from, to) in spelledAlike { text = text.replacingOccurrences(of: from, with: to) }
    if text.count > 2, text.hasSuffix("e") { text.removeLast() }
    var key = ""
    for letter in text {
        let sound: Character = "aeiouy".contains(letter) ? "a" : letter
        if key.last != sound { key.append(sound) }
    }
    return key
}

/// Letters at the start of a word that are not said.
private let soundsAlike: [(String, String)] = [("wr", "r"), ("kn", "n"), ("wh", "w"), ("ps", "s")]
/// Spellings anywhere in a word that say the same sound.
private let spelledAlike: [(String, String)] = [("gh", ""), ("ph", "f"), ("ck", "k"), ("ei", "e"), ("ea", "e")]

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

/// Whether the newest words heard over the voice are not ones it said, the first sign of the person
/// starting to talk. Two in a row, since one stray word is how its own voice comes back misheard,
/// "want" for its "one" and "pool" for its "pull", and pausing on each cut every sentence it said.
/// "Stop" or "wait" alone is enough, since its own voice never says them unprompted.
public func mayBeCuttingIn(heard: String, spoken: String) -> Bool {
    let said = wordsIn(spoken)
    let words = wordsIn(heard)
    guard let newest = words.last else { return false }
    // Only when it did not just say it: its own name is in half its sentences, and pausing on it cut each one.
    if stopWords.contains(newest), !isEcho(newest, of: said) { return true }
    let recent = words.suffix(firstWordsOfTheirs)
    return recent.count == firstWordsOfTheirs && recent.allSatisfy { !isEcho($0, of: said) && !isEchoStarting($0, of: said) }
}

/// How many words in a row not its own it takes to pause the voice.
private let firstWordsOfTheirs = 2

/// Whether a word is the start of one it said, which the recognizer writes before it has the rest:
/// "cur" on its way to Cursor, "me" to Memnox, "run" to runtime.
private func isEchoStarting(_ word: String, of said: [String]) -> Bool {
    said.contains { $0.count > word.count && $0.hasPrefix(word) }
}

/// What was heard from the words it paused on, since everything before them was its own voice and
/// only what comes once it is quiet can be the person. The words it paused on are kept, as their first.
public func sincePause(_ heard: String, pausedOn: String) -> String {
    let before = pausedOn.split(whereSeparator: \.isWhitespace).count
    return heard.split(whereSeparator: \.isWhitespace).dropFirst(max(before - firstWordsOfTheirs, 0)).joined(separator: " ")
}

/// Whether the words heard since it went quiet are the person: two of theirs after the ones it paused
/// on, since the recognizer still finishes a word or two of its own echo once the voice has stopped,
/// and one alone is enough when it is "stop" or "wait".
public func isPersonAfterPause(_ sincePaused: String, spoken: String) -> Bool {
    let said = wordsIn(spoken)
    let heard = wordsIn(sincePaused).filter { !isEcho($0, of: said) }
    // "Stop" is theirs even as the word it paused on, since its own voice never says it unprompted.
    if heard.contains(where: { stopWords.contains($0) }) { return true }
    return wordsIn(sincePaused).dropFirst(firstWordsOfTheirs).filter { !isEcho($0, of: said) }.count >= BargeIn.inSilence
}

/// What the recognizer puts between the words it heard.
private let cutInSeparator: Character = " "

/// What the person said over the voice, with its own words taken off the front. When they were
/// already talking while it was quiet, everything from their first word of their own is kept, since
/// the pause came only once the voice spoke over them and the start of their sentence was before it.
public func cutInWords(_ heard: String, pausedOn: String, spoken: String, spokeInQuiet: Bool) -> String {
    guard spokeInQuiet else { return withoutEcho(sincePause(heard, pausedOn: pausedOn), spoken: spoken) }
    let said = wordsIn(spoken)
    let parts = withoutEchoRuns(heard, spoken: spoken).split(separator: cutInSeparator).map(String.init)
    guard let first = parts.firstIndex(where: { part in wordsIn(part).contains { !isEcho($0, of: said) } }) else { return "" }
    // "I" in "I think" is too short to judge, so it stays with the word of theirs it opens.
    var start = first
    while start > 0, wordsIn(parts[start - 1]).isEmpty { start -= 1 }
    return parts[start...].joined(separator: String(cutInSeparator))
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
    var parts = rejoined(heard.split(separator: " ").map(String.init), said: said)
    // "I'm" or "a" has no word long enough to judge, so it carries a run on without counting toward it.
    func echoes(_ part: String) -> Bool { pieceWords(part).allSatisfy { isEcho($0, of: said) } }
    func judged(_ run: ArraySlice<String>) -> Int { run.filter { !pieceWords($0).isEmpty }.count }
    func isRun(_ run: [String]) -> Bool { judged(run[...]) >= echoRunLength && followsInOrder(run.flatMap(pieceWords), in: said) }
    let leading = Array(parts.prefix(while: echoes))
    let removedLeading = isRun(leading)
    if removedLeading { parts.removeFirst(leading.count) }
    let trailing = Array(parts.reversed().prefix(while: echoes).reversed())
    let removedTrailing = isRun(trailing)
    if removedTrailing { parts.removeLast(trailing.count) }
    // What is left beside an echo, split where its sentence was not, like "me AI" from "HireMe.AI",
    // is the end of the same echo when its letters run on inside what it said.
    let left = letters(parts.joined())
    if removedLeading || removedTrailing, judged(parts[...]) <= echoLeftoverWords,
       left.count >= echoLeftoverLetters, letters(spoken).contains(left) {
        return ""
    }
    return parts.joined(separator: " ")
}

/// Heard words put back together where the recognizer split one it said, "hire me" for its "HireMe",
/// kept as one piece with its space so the person's own words still come back as they were heard.
private func rejoined(_ parts: [String], said: [String]) -> [String] {
    var pieces: [String] = []
    for part in parts {
        if let last = pieces.last, !said.contains(letters(last)), said.contains(letters(last + part)),
           letters(last + part).count >= fuzzyEchoLength {
            pieces[pieces.count - 1] = "\(last) \(part)"
        } else {
            pieces.append(part)
        }
    }
    return pieces
}

/// The words in a piece: a rejoined one is the single word it was split from.
private func pieceWords(_ piece: String) -> [String] {
    piece.contains(" ") ? [letters(piece)] : wordsIn(piece)
}

/// A few words at most beside an echo; more is the person carrying on.
private let echoLeftoverWords = 3
/// Shorter than this a leftover matches anywhere in a sentence by chance.
private let echoLeftoverLetters = 3

private func letters(_ text: String) -> String {
    text.lowercased().filter(\.isLetter)
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
