import Foundation

// Finding a node on the brain by what it says, on the canvas alone: the label, the detail and the path of every layer
// are matched here as the person types, so the canvas dims all but the matches without asking the daemon. The page's own
// search still asks the daemon for the facts it lists.

public enum BrainSearch {
    /// The words a query is matched by, folded for case and accents, nil when it holds none.
    public static func words(_ query: String) -> [String]? {
        let words = fold(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return words.isEmpty ? nil : words
    }

    /// The text a node is found by: its label, what it is, and where it lives, folded once when the brain is built.
    public static func haystack(_ parts: [String?]) -> String {
        fold(parts.compactMap { $0 }.joined(separator: " "))
    }

    /// The nodes every word of the query is found in, those whose label starts with the first word before the rest,
    /// then the heaviest, then in the order given, so Enter opens the likeliest one.
    public static func matches(_ query: String, haystacks: [String], labels: [String], weights: [Double]) -> [Int] {
        guard let words = words(query) else { return [] }
        let found = haystacks.indices.filter { index in words.allSatisfy { haystacks[index].contains($0) } }
        let leading = Set(found.filter { fold(labels[$0]).hasPrefix(words[0]) })
        return found.sorted { left, right in
            let a = leading.contains(left)
            let b = leading.contains(right)
            if a != b { return a }
            if weights[left] != weights[right] { return weights[left] > weights[right] }
            return left < right
        }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    }
}
