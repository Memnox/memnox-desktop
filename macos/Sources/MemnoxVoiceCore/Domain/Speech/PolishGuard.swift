import Foundation

/// Whether a polished dictation still says what was said: no longer than the speech allows, no negation put in or
/// taken out, most of the words still there, and nothing new that was neither heard, a number, one of the person's
/// own words nor a spelling of a heard one. False means the Mac's own cleanup is typed instead, since a model that
/// answered the speech or rewrote it would otherwise land in the field as if the person had said it. It compares
/// words as text and never acts on one.
public func polishKeepsWhatWasSaid(_ polished: String, said: String, vocabulary: [String] = []) -> Bool {
    let source = comparedWords(said)
    let output = comparedWords(polished)
    let heard = source.count
    guard heard > 0 else { return true }
    guard !output.isEmpty else { return false }
    // A cut has no room for new words, since a polish that shortened the speech has nothing to add back.
    let room = output.count < heard ? 0 : heard / PolishLimits.roomShare
    if output.count > heard + room { return false }
    if negations(in: source) != negations(in: output) { return false }
    let kept = keptCount(of: source, in: output)
    if kept * PolishLimits.keptShare < heard { return false }
    if heard - kept > max(PolishLimits.fewestVanished, heard / PolishLimits.vanishedShare) { return false }
    let familiar = Set(source + vocabulary.flatMap(comparedWords))
    let strange = newWords(in: output, besides: source).filter { !isFamiliar($0, among: familiar) }
    return strange.count <= room + heard / PolishLimits.strangeShare
}

/// How far a polish may stray from the speech, each as a share of the words heard.
private enum PolishLimits {
    /// One extra word in eight, for the articles and joins a typed sentence has and speech drops.
    static let roomShare = 8
    /// At least a third of what was said is still there, or it was summarized rather than cleaned.
    static let keptShare = 3
    /// Fillers, stutters and false starts go, so a few words may always vanish, more in a long dictation.
    static let fewestVanished = 8
    static let vanishedShare = 6
    /// A respelled name or a joined word is new in a long dictation now and then.
    static let strangeShare = 12
    /// A new word this close in spelling to one heard or one of their own is that word written right.
    static let familiarSimilarity = 0.65
}

/// Lowercased words with contractions spelled out, so "do not" and "don't" compare as the same words.
private func comparedWords(_ text: String) -> [String] {
    let normalized = text.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
    let words = normalized.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "'") })
        .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
        .filter { !$0.isEmpty }
    return words.flatMap(spelledOut)
}

/// One word as the words it stands for: "can't" as "can not", "I'm" as "i am", and the forms typed without an apostrophe.
private func spelledOut(_ word: String) -> [String] {
    if let whole = wholeContractions[word] { return whole }
    if word.hasSuffix("n't") { return [String(word.dropLast(3)), "not"] }
    for (ending, meaning) in contractionEndings where word.hasSuffix(ending) && word.count > ending.count {
        return [String(word.dropLast(ending.count)), meaning]
    }
    return [word]
}

/// Contractions whose first half is not the word it stands for, and negations typed without their apostrophe.
private let wholeContractions: [String: [String]] = [
    "won't": ["will", "not"], "can't": ["can", "not"], "shan't": ["shall", "not"], "ain't": ["is", "not"],
    "cannot": ["can", "not"], "dont": ["do", "not"], "doesnt": ["does", "not"], "didnt": ["did", "not"],
    "isnt": ["is", "not"], "arent": ["are", "not"], "wasnt": ["was", "not"], "werent": ["were", "not"],
    "wouldnt": ["would", "not"], "shouldnt": ["should", "not"], "couldnt": ["could", "not"], "havent": ["have", "not"],
    "hasnt": ["has", "not"], "hadnt": ["had", "not"], "mustnt": ["must", "not"], "neednt": ["need", "not"],
]

private let contractionEndings: [(String, String)] = [
    ("'m", "am"), ("'re", "are"), ("'ve", "have"), ("'ll", "will"), ("'d", "would"), ("'s", "is"),
]

/// Words that turn a sentence into its opposite, counted so one put in or taken out is caught.
private let negatingWords: Set<String> = ["not", "no", "never", "nor", "neither", "none", "nobody", "nothing", "nowhere"]

private func negations(in words: [String]) -> Int {
    words.filter { negatingWords.contains($0) }.count
}

/// How many of the words heard are still in the polish, each counted as often as it was said.
private func keptCount(of source: [String], in output: [String]) -> Int {
    var left = tally(output)
    var kept = 0
    for word in source where (left[word] ?? 0) > 0 {
        left[word, default: 0] -= 1
        kept += 1
    }
    return kept
}

/// The polish's words beyond those heard, each as often as it is extra.
private func newWords(in output: [String], besides source: [String]) -> [String] {
    var left = tally(source)
    var extra: [String] = []
    for word in output {
        if (left[word] ?? 0) > 0 {
            left[word, default: 0] -= 1
        } else {
            extra.append(word)
        }
    }
    return extra
}

private func tally(_ words: [String]) -> [String: Int] {
    words.reduce(into: [:]) { $0[$1, default: 0] += 1 }
}

/// Heard, a number, one of their own words, or a spelling close enough to one of those to be it written right.
private func isFamiliar(_ word: String, among familiar: Set<String>) -> Bool {
    if familiar.contains(word) || word.contains(where: \.isNumber) { return true }
    return familiar.contains { spellingSimilarity(word, $0) >= PolishLimits.familiarSimilarity }
}

/// One for the same spelling, falling with each letter changed, as a share of the longer word.
private func spellingSimilarity(_ a: String, _ b: String) -> Double {
    let longest = max(a.count, b.count)
    guard longest > 0 else { return 1 }
    return 1 - Double(editDistance(a, b)) / Double(longest)
}
