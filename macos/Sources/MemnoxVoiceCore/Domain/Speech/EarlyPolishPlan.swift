import Foundation

/// The letters and digits of each word, lowercased and nothing else, so two hearings that differ only in
/// punctuation or case are the same words and one polish of them answers both.
public func dictationWordKey(_ text: String) -> String {
    text.lowercased().split(whereSeparator: { !($0.isLetter || $0.isNumber) }).joined(separator: " ")
}

/// How many words differ between two keys, past the part they share from the start.
public func dictationWordsChanged(from earlier: String, to later: String) -> Int {
    let before = earlier.split(separator: " ")
    let after = later.split(separator: " ")
    let shared = zip(before, after).prefix { $0 == $1 }.count
    return max(before.count, after.count) - shared
}

/// When a polish may start while the person is still talking: at a pause after enough words to be worth one, no more
/// than a couple of times a dictation, and again only once enough words have changed that the last one is stale.
public enum EarlyPolishPlan {
    /// A breath between phrases, long enough that the recognizer has settled the words before it.
    public static let pause: TimeInterval = 0.4
    public static let fewestWords = 3
    public static let mostRuns = 2
    public static let fewestChanged = 3

    /// Whether `words`, unchanged for `pausedFor`, start an early polish after the runs already started with `earlier` keys.
    public static func mayStart(_ words: String, pausedFor: TimeInterval, after earlier: [String]) -> Bool {
        let key = dictationWordKey(words)
        guard pausedFor >= pause, key.split(separator: " ").count >= fewestWords, earlier.count < mostRuns else { return false }
        guard let last = earlier.last else { return true }
        return dictationWordsChanged(from: last, to: key) >= fewestChanged
    }
}
