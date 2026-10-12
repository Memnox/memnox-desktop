import Foundation

/// How the recognizer spells "Memnox" before it has learned the word, run together.
private let wakeSpellings: Set<String> = [
    "memnox", "memnocks", "memknox", "memknocks", "mennox", "memnoks", "memnux", "menknocks", "mennocks",
    "maamknox", "mamknox", "manknox", "menknox", "maamnox", "mamnox", "mamnocks", "manknocks", "memnoxs",
    // Heard on a real Mac: "Emma Knox", "MM Nox", "M Knox", "Minnox".
    "emmaknox", "mmnox", "mmknox", "mknox", "minnox", "emnox", "emknox",
    // Heard on a real Mac: "Memnox Manox", "Mnox".
    "manox", "mannox", "mnox", "menox",
]

/// The name cut to its end, which is only the name at either end of what was said or beside the name itself:
/// "OK Knox, can you" and "Can you? Knox?" call it, while in the middle of a sentence Knox is Fort Knox.
private let edgeSpellings: Set<String> = ["knox", "nox"]

/// The two halves of the name as a recognizer hears them from somebody who says it their own way: any first half
/// run into any second half is the name, so a person need not say it the one way the list above happened to hear.
/// Only halves that are no common word of their own, so "the memo knocks" or "a man nicks it" never wakes it.
private let firstHalves: Set<String> = [
    "mem", "men", "mam", "mim", "min", "maam", "emm", "em", "mm", "emma", "mehm", "mehn", "mimm",
]
private let secondHalves: Set<String> = [
    "nox", "nocks", "nocs", "noks", "nux", "nucks", "nuks", "nix", "nicks", "nics", "nex", "necks", "nax", "naks",
    "knox", "knocks", "knocs", "knicks", "knux", "nock", "noc",
]

/// Whether a run of letters is the name, by the list or by its halves. Four letters is the shortest run that can
/// still be the name ("mnox"), and anything shorter is a word of its own.
private let shortestName = 4

private func isWakeSpelling(_ run: String) -> Bool {
    if wakeSpellings.contains(run) { return true }
    guard run.count >= shortestName else { return false }
    for cut in run.indices.dropFirst() {
        if firstHalves.contains(String(run[..<cut])), secondHalves.contains(String(run[cut...])) { return true }
    }
    return false
}

/// One run of letters in what was heard, lowercased, with where it sits in the words.
private struct HeardToken {
    let text: String
    let start: String.Index
    let end: String.Index
}

private func heardTokens(_ words: String) -> [HeardToken] {
    var tokens: [HeardToken] = []
    var start: String.Index?
    for index in words.indices {
        if words[index].isLetter {
            if start == nil { start = index }
        } else if let begun = start {
            tokens.append(HeardToken(text: words[begun..<index].lowercased(), start: begun, end: index))
            start = nil
        }
    }
    if let begun = start { tokens.append(HeardToken(text: words[begun...].lowercased(), start: begun, end: words.endIndex)) }
    return tokens
}

/// The recognizer splits the name into at most three runs, as in "ma'am knox".
private let mostNameTokens = 3

/// How many tokens from `position` on spell the name, nil when they do not; `edge` lets the name cut to its end count.
private func nameLength(_ tokens: [HeardToken], at position: Int, edge: Bool) -> Int? {
    if edge, edgeSpellings.contains(tokens[position].text) { return 1 }
    var joined = ""
    for length in 1...mostNameTokens where position + length <= tokens.count {
        joined += tokens[position + length - 1].text
        if isWakeSpelling(joined) { return length }
    }
    return nil
}

/// Only the first word, or the one after a word like "OK", is the start of what was said.
private let leadingEdgeTokens = 2

/// Where the first time it was called sits, its repeats included so "Memnox Manox" is one call: the token it starts
/// at and the one after it ends. The name cut to its end counts only at either end, or beside the name itself.
private func firstCall(_ tokens: [HeardToken], in words: String) -> (first: Int, after: Int)? {
    for position in tokens.indices {
        let atEnd = position == tokens.count - 1 && (position == 0 || setApart(tokens[position - 1], tokens[position], in: words))
        guard let length = nameLength(tokens, at: position, edge: position < leadingEdgeTokens || atEnd) else { continue }
        var after = position + length
        while after < tokens.count, let again = nameLength(tokens, at: after, edge: true) { after += again }
        return (position, after)
    }
    return nil
}

/// Whether a full stop, a question mark or a comma sits between two tokens, the way somebody sets a name apart.
private func setApart(_ before: HeardToken, _ token: HeardToken, in words: String) -> Bool {
    words[before.end..<token.start].contains { nameSetApartBy.contains($0) }
}

private let nameSetApartBy: Set<Character> = [".", "?", "!", ","]

/// What followed "Memnox" when the person called it by name, empty when the name was said alone,
/// and nil when it was not said. The name only opens the orb: what follows goes whole to the brain.
public func afterWakeWord(_ words: String) -> String? {
    let tokens = heardTokens(words)
    guard let call = firstCall(tokens, in: words) else { return nil }
    guard call.after < tokens.count else { return "" }
    let rest = words[tokens[call.after - 1].end...].drop { !$0.isLetter && !$0.isNumber }
    return String(rest).trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Only its name, or "hey" and its name: somebody getting its attention. Said at the end of a
/// question, as in "start a session in Memnox", the name is part of what they asked.
public func nameAlone(_ words: String) -> Bool {
    guard let rest = afterWakeWord(words), rest.isEmpty else { return false }
    let tokens = heardTokens(words)
    guard let call = firstCall(tokens, in: words) else { return false }
    // "Hey" before it still makes it a greeting, and a name said twice is still only the name.
    return words[..<tokens[call.first].start].split(whereSeparator: \.isWhitespace).count < greetingWordsBeforeName
}

/// One word before the name, like "hey" or "OK", still makes it a greeting.
private let greetingWordsBeforeName = 2

/// What they said with "Memnox" taken off the front, since calling it by name mid conversation
/// is a greeting and not part of the question.
public func withoutLeadingName(_ words: String) -> String {
    let tokens = heardTokens(words)
    guard let call = firstCall(tokens, in: words), call.after < tokens.count else { return words }
    // Only the name first, or after one word like "hey", is a greeting; later on it is part of what they asked.
    guard words[..<tokens[call.first].start].split(whereSeparator: \.isWhitespace).count < greetingWordsBeforeName else { return words }
    let rest = words[tokens[call.after - 1].end...].drop { !$0.isLetter && !$0.isNumber }
    return String(rest).trimmingCharacters(in: .whitespacesAndNewlines)
}

/// What they said less its name called at the end, set apart by a mark or said twice, as in "why so slow? Memnox Memnox";
/// "start a session in Memnox" names a place so it stays, and the name alone stays since it is answered as a call.
public func withoutTrailingName(_ words: String) -> String {
    let tokens = heardTokens(words)
    var cut = tokens.count
    var names = 0
    var kept: Int?
    while cut > 0 {
        // The longest spelling first, so "ma'am Knox" goes whole rather than as a bare "Knox".
        let found = (1...min(mostNameTokens, cut)).reversed().first { length in
            nameLength(tokens, at: cut - length, edge: true) == length
        }
        guard let found else { break }
        cut -= found
        names += 1
        guard cut > 0 else { break }
        // A mark sets the name apart; with none anywhere, the name twice in a row is still somebody calling.
        if setApart(tokens[cut - 1], tokens[cut], in: words) || (names > 1 && kept == nil) { kept = cut }
    }
    guard let kept else { return words }
    let before = words[..<tokens[kept].start].trimmingCharacters(in: .whitespacesAndNewlines)
    return before.hasSuffix(",") ? String(before.dropLast()) : before
}

/// The words after its name, once its own recent sentences are taken off, so a greeting it says
/// with "Memnox" in it never wakes it. Nil when the name was only ever in its own voice.
public func afterWakeWord(_ words: String, spoken: String) -> String? {
    afterWakeWord(withoutEchoRuns(words, spoken: spoken))
}
