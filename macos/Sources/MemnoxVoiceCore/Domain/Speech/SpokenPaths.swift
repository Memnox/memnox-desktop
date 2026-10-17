import Foundation

/// A sentence with every file path cut to its last part, since "/private/tmp/claude-501/-Users-…/src"
/// read out takes twenty seconds, means nothing heard, and comes back through the microphone as words
/// the recognizer cannot match to its own. The card on screen still shows the whole path.
public func withShortPaths(_ sentence: String) -> String {
    sentence.split(separator: " ", omittingEmptySubsequences: false).map { token in
        let word = String(token)
        let body = word.trimmingCharacters(in: trailingMarks)
        guard isPath(body), let last = body.split(separator: "/").last else { return word }
        return String(last) + word.dropFirst(body.count)
    }.joined(separator: " ")
}

/// A path starts at the root or the home folder and has a folder in it, so "and/or" is no path.
private func isPath(_ word: String) -> Bool {
    (word.hasPrefix("/") || word.hasPrefix("~/")) && word.split(separator: "/").count >= leastPathParts
}

/// Two parts at least, since "/src" alone is already as short as it gets.
private let leastPathParts = 2
/// Punctuation that ends the sentence around a path rather than belonging to it.
private let trailingMarks = CharacterSet(charactersIn: ".,;:?!)")
