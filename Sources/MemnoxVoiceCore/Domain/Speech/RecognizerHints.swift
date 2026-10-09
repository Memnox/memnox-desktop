import Foundation

/// Hints only help the recognizer while they are few, so a long list waters down the names it most needs.
public let mostRecognizerHints = 100

/// The hints to give the recognizer, in order of need: the names said most, then this machine's own,
/// then the rest. Each once, whatever its case, and never more than the recognizer weighs well.
public func chosenHints(_ lists: [String]..., most: Int = mostRecognizerHints) -> [String] {
    var seen = Set<String>()
    var chosen: [String] = []
    for hint in lists.joined() {
        let word = hint.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty, seen.insert(word.lowercased()).inserted else { continue }
        chosen.append(word)
        if chosen.count == most { break }
    }
    return chosen
}
