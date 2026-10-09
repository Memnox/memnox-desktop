import Foundation

/// Whether a sentence says again what was already said in this reply. The brain often says what it
/// is about to do, calls the tool, then says it once more, like "I will tell you when Codex finishes."
/// twice around a watch; heard twice it sounds broken, so the second is let go. Nearly the same words
/// count too, since the second telling usually only adds a detail the first did not need.
public func repeats(_ sentence: String, saidAlready: [String]) -> Bool {
    let words = Set(wordsOf(sentence))
    guard !words.isEmpty else { return false }
    return saidAlready.contains { earlier in
        let before = Set(wordsOf(earlier))
        if before == words { return true }
        guard words.count >= Repeat.leastWords, before.count >= Repeat.leastWords else { return false }
        let shared = Double(words.intersection(before).count) / Double(words.union(before).count)
        return shared >= Repeat.sameShare
    }
}

private enum Repeat {
    /// Short lines share their few words by chance, so only an exact one repeats.
    static let leastWords = 4
    /// Four in five words the same is the same sentence told again.
    static let sameShare = 0.8
}

private func wordsOf(_ sentence: String) -> [String] {
    sentence.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
}
