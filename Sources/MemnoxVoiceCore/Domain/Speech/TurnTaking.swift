import Foundation

/// Words people trail off on, which mean they have not finished even when they pause.
private let trailingWords: Set<String> = [
    "uh", "um", "er", "erm", "hmm", "so", "and", "but", "or", "like", "the", "a", "an", "to", "of", "with", "because",
    "i", "my", "your", "our", "was", "is", "are", "that", "if", "when", "about", "for", "in", "on", "at", "then", "which", "we", "it's", "its",
]

/// The openings of a request, which said alone are somebody gathering the rest of it even when the
/// recognizer writes "Can you?" as a finished question.
private let requestOpenings: Set<String> = [
    "can you", "could you", "would you", "will you", "can i", "could i", "can we", "could we", "do you",
    "is there", "are there", "what about", "show me", "tell me", "i want", "i need", "i want you to", "please",
    "okay so", "ok so", "so can you", "and can you", "hey", "hey can you",
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
    let trailing = trailingMarks.contains(where: { trimmed.hasSuffix($0) })
    if trailing || trailingWords.contains(last) { return SpeechPause.stillThinking }
    if requestOpenings.contains(spoken.joined(separator: " ")) { return SpeechPause.stillThinking }
    let long = spoken.count > longThought
    // The recognizer only puts a full stop or a question mark on a sentence it thinks is done.
    if finishingMarks.contains(where: { trimmed.hasSuffix($0) }) {
        if spoken.count <= shortReply { return SpeechPause.shortReply }
        // A finished question is answered sooner; a long one keeps more room, since people pause between its sentences.
        return long ? SpeechPause.finishedLong : SpeechPause.finished
    }
    // The older recognizer rarely punctuates as it goes, so an unmarked pause gets the benefit of the doubt.
    return long ? SpeechPause.unmarkedLong : SpeechPause.unmarked
}

/// The pauses that end what somebody is saying, from a one word answer to somebody still thinking.
private enum SpeechPause {
    /// A trailing "uh", "so" or "..." is somebody still thinking, so that waits longest.
    static let stillThinking: TimeInterval = 3.0
    /// "Yes." is an answer, and answered almost at once.
    static let shortReply: TimeInterval = 0.6
    /// A finished question, answered a beat after it.
    static let finished: TimeInterval = 0.9
    /// A finished long thought, since people pause between its sentences.
    static let finishedLong: TimeInterval = 1.5
    /// No mark to go on, so the pause gets the benefit of the doubt.
    static let unmarked: TimeInterval = 1.7
    static let unmarkedLong: TimeInterval = 2.0
}

/// Endings that mean somebody trailed off mid thought: a comma or an ellipsis, typed or as one character.
private let trailingMarks = [",", "...", "\u{2026}"]
/// Endings the recognizer only writes on a sentence it thinks is done.
private let finishingMarks = ["?", ".", "!"]

/// How long a pause is before the words so far are sent as a guess, well short of any end of speech.
public let guessAfterPause: TimeInterval = 0.35

/// Whether a pause this long is worth starting the answer on: never while they trail off on a word
/// like "and", and only while the pause has not yet ended what they are saying.
public func mayGuess(_ words: String, pausedFor pause: TimeInterval) -> Bool {
    let ending = endOfSpeechPause(after: words)
    return words.contains(where: \.isLetter) && ending < SpeechPause.stillThinking && pause >= guessAfterPause && pause < ending
}

/// "Yes.", "Go ahead." or "Open it.": an answer, not the start of a thought.
private let shortReply = 3
/// Past this many words somebody is explaining, and pauses between their sentences, so the
/// recognizer's full stop after the first sentence is not the end of what they mean.
private let longThought = 8

/// How long they have been quiet: since the last new word, or since the microphone last heard their
/// voice when that is later, because the recognizer lags behind a slow or unclear sentence and a
/// pause in the words alone cut people off mid thought. A voice with no new words holds it open only
/// so long, so a noisy room never keeps it listening for ever.
public func quietFor(now: Date, lastWord: Date, lastVoice: Date?) -> TimeInterval {
    guard let lastVoice else { return now.timeIntervalSince(lastWord) }
    let held = min(lastVoice, lastWord.addingTimeInterval(voiceHoldsFor))
    return now.timeIntervalSince(max(lastWord, held))
}

/// Longest a voice still talking keeps the turn open after the words stopped changing.
public let voiceHoldsFor: TimeInterval = 3.0

/// Two stretches of what was heard as one sentence, with the space between them the recognizer leaves out
/// when it finishes one segment and starts the next, so "so." and "Is there" never read as "so.Is there".
public func joinedSpeech(_ first: String, _ second: String) -> String {
    [first, second].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
}

/// Whether a listen was loud enough at its loudest to hold somebody speaking, on the zero to one
/// decibel scale the microphone reports. A recognizer taught Memnox's own requests turns a quiet
/// room into one of them, like "show me all my sessions", so words from a listen this quiet are noise.
public func soundedLikeSpeech(loudest: Float) -> Bool {
    loudest >= quietestSpeech
}

/// About 46 decibels below full scale, under the quietest speech a laptop microphone picks up.
public let quietestSpeech: Float = 0.2
