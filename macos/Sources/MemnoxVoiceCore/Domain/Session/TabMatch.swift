import Foundation

/// Which of a terminal app's tabs holds a session, told by the lines on screen when the app cannot say:
/// the one tab showing the most of the session's own lines, and none when two show as many.
public enum TabMatch {
    /// A tab must show at least this many of the session's lines to count at all.
    static let fewestShown = 1
    /// And be the only one showing that many, or which is the session's cannot be told.
    static let onlyOne = 1

    /// The index of the text that holds the session, or nil when none does or two do equally.
    public static func best(_ texts: [String], marks: [String]) -> Int? {
        let wanted = marks.map(squeezed).filter { !$0.isEmpty }
        guard !wanted.isEmpty else { return nil }
        let scores = texts.map { text -> Int in
            let screen = squeezed(text)
            return wanted.filter { screen.contains($0) }.count
        }
        guard let top = scores.max(), top >= fewestShown, scores.filter({ $0 == top }).count == onlyOne else { return nil }
        return scores.firstIndex(of: top)
    }

    /// Whether this one text shows every one of the session's lines, which settles it without reading the rest.
    public static func isCertain(_ text: String, marks: [String]) -> Bool {
        let wanted = marks.map(squeezed).filter { !$0.isEmpty }
        let screen = squeezed(text)
        return !wanted.isEmpty && wanted.allSatisfy { screen.contains($0) }
    }

    /// Lowercase with every space and line break gone, since a terminal wraps a line wherever its width ends.
    static func squeezed(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) })
    }
}
