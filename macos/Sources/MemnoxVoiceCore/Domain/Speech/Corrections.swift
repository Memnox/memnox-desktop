import Foundation

/// A word Memnox typed from what it heard, and what the person changed it to before sending.
public struct WordCorrection: Equatable, Sendable {
    public let heard: String
    public let meant: String

    public init(heard: String, meant: String) {
        self.heard = heard
        self.meant = meant
    }
}

/// The words the person fixed in a message Memnox typed for them, found by lining the two up word
/// by word: "show the surgeons" sent as "show the sessions" is surgeons for sessions. A message they
/// rewrote, a word they added or dropped, a fix of case or punctuation, and a swap for a word that
/// sounds nothing alike all teach nothing, since none of them is the recognizer mishearing a word.
public func correctedWords(typed: String, sent: String) -> [WordCorrection] {
    let before = words(in: typed)
    let after = words(in: sent)
    guard !before.isEmpty, !after.isEmpty else { return [] }
    let kept = commonRun(before.map(\.key), after.map(\.key))
    // Most of it changed, so they rewrote the message rather than fixing a word in it.
    guard Double(before.count - kept.count) / Double(before.count) <= Corrections.mostChanged else { return [] }
    var found: [WordCorrection] = []
    var (b, a) = (0, 0)
    for (keptBefore, keptAfter) in kept + [(before.count, after.count)] {
        let heard = before[b..<keptBefore]
        let meant = after[a..<keptAfter]
        if let correction = correction(heard, meant) { found.append(correction) }
        (b, a) = (keptBefore + 1, keptAfter + 1)
    }
    return Array(found.prefix(Corrections.mostAtOnce))
}

private enum Corrections {
    /// More than half the words changed is a rewrite.
    static let mostChanged = 0.5
    /// A misheard name is a word or a few, never a clause.
    static let mostWords = 3
    /// Shorter than this is a sound, not a word worth learning.
    static let leastLetters = 3
    /// Spellings further apart than this share of their letters do not sound alike. Looser than a
    /// typo's, since "closed" and "Claude" sound the same and share only two letters in place.
    static let mostDifferent = 0.7
    /// One edit fixes a few words at most; past this it is a rewrite.
    static let mostAtOnce = 5
}

/// One word as written, and as compared: lowercased, letters and digits only.
private struct Word {
    let written: String
    let key: String
}

private func words(in text: String) -> [Word] {
    text.split(whereSeparator: \.isWhitespace).compactMap { token in
        let written = token.trimmingCharacters(in: .punctuationCharacters)
        let key = written.lowercased().filter { $0.isLetter || $0.isNumber }
        return key.isEmpty ? nil : Word(written: written, key: key)
    }
}

/// The words kept in order in both, as index pairs, by the longest common run of words.
private func commonRun(_ a: [String], _ b: [String]) -> [(Int, Int)] {
    var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
    for i in stride(from: a.count - 1, through: 0, by: -1) {
        for j in stride(from: b.count - 1, through: 0, by: -1) {
            table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
        }
    }
    var pairs: [(Int, Int)] = []
    var (i, j) = (0, 0)
    while i < a.count, j < b.count {
        if a[i] == b[j] {
            pairs.append((i, j))
            (i, j) = (i + 1, j + 1)
        } else if table[i + 1][j] >= table[i][j + 1] {
            i += 1
        } else {
            j += 1
        }
    }
    return pairs
}

/// A changed stretch as a correction, when it is a word or a few swapped for ones that sound alike.
private func correction(_ heard: ArraySlice<Word>, _ meant: ArraySlice<Word>) -> WordCorrection? {
    guard !heard.isEmpty, !meant.isEmpty, heard.count <= Corrections.mostWords, meant.count <= Corrections.mostWords else { return nil }
    let heardKey = heard.map(\.key).joined()
    let meantKey = meant.map(\.key).joined()
    guard heardKey.count >= Corrections.leastLetters, meantKey.count >= Corrections.leastLetters, heardKey != meantKey else { return nil }
    let apart = Double(letterDistance(heardKey, meantKey)) / Double(max(heardKey.count, meantKey.count))
    guard apart <= Corrections.mostDifferent else { return nil }
    return WordCorrection(heard: heard.map(\.written).joined(separator: " "), meant: meant.map(\.written).joined(separator: " "))
}

private func letterDistance(_ a: String, _ b: String) -> Int {
    let a = Array(a), b = Array(b)
    var row = Array(0...b.count)
    for i in 1...a.count {
        var previous = row[0]
        row[0] = i
        for j in stride(from: 1, through: b.count, by: 1) {
            let current = row[j]
            row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (a[i - 1] == b[j - 1] ? 0 : 1))
            previous = current
        }
    }
    return row[b.count]
}
