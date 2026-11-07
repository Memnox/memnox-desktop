import Foundation

/// Starts the polish at a pause while the dictation key is still held, so a dictation that ends where that pause was
/// already has its answer, or has it on the way, when the key comes up. Words said after the pause make it stale,
/// and then the finished words are asked for afresh, so nothing typed ever comes from words the person did not end on.
public final class EarlyDictationPolish: @unchecked Sendable {
    private let polish: DictationPolish
    private let family: DictationFamily
    private let vocabulary: [String]
    private let textBefore: String?
    private let lock = NSLock()
    private var latest = ""
    private var changedAt = Date()
    private var runs: [(key: String, answer: Task<String?, Never>)] = []

    public init(polish: DictationPolish, family: DictationFamily, vocabulary: [String], textBefore: String?) {
        self.polish = polish
        self.family = family
        self.vocabulary = vocabulary
        self.textBefore = textBefore
    }

    /// The words so far, from the recognizer's thread each time they change.
    public func hear(_ words: String, at now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        guard words != latest else { return }
        latest = words
        changedAt = now
    }

    /// Looked at while the key is held: starts a polish of the words so far when they have paused long enough.
    public func look(at now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        let words = latest
        guard EarlyPolishPlan.mayStart(words, pausedFor: now.timeIntervalSince(changedAt), after: runs.map(\.key)) else { return }
        let polish = self.polish, family = self.family, vocabulary = self.vocabulary, textBefore = self.textBefore
        let answer = Task { await polish.polish(words, family: family, vocabulary: vocabulary, textBefore: textBefore) }
        runs.append((dictationWordKey(words), answer))
    }

    /// The polish of exactly what was said: the early one when the words are the same, waited on only then, since
    /// it is the very request a fresh one would be and further along; otherwise asked for now, as without any.
    public func answer(for said: String) async -> String? {
        let key = dictationWordKey(said)
        let started = lock.withLock {
            defer { runs = [] }
            return runs
        }
        let same = started.last { $0.key == key }
        // Stale runs are let go, so none of them is ever waited on.
        for run in started where run.key != key { run.answer.cancel() }
        if let same { return await same.answer.value }
        return await polish.polish(said, family: family, vocabulary: vocabulary, textBefore: textBefore)
    }
}
