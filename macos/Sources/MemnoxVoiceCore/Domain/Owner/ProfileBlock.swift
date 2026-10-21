import Foundation

/// The lines the app adds to a shell profile so a terminal finds memnox, between its own two markers, as
/// `Support/runtime/unpack.sh` writes them: a blank line, the opening marker, the lines, the closing marker.
public enum ProfileBlock {
    public static let begin = "# >>> memnox app >>>"
    public static let end = "# <<< memnox app <<<"

    /// The profile with the app's block taken out and nothing else touched, the blank line written before it included;
    /// nil when there is no block, or no closing marker, since cutting to the end of a hand edited file could take the
    /// person's own lines with it.
    public static func without(_ text: String) -> String? {
        guard let opening = text.range(of: begin), let closing = text.range(of: end, range: opening.upperBound..<text.endIndex) else {
            return nil
        }
        var from = opening.lowerBound
        if from > text.startIndex, text[text.index(before: from)] == "\n" { from = text.index(before: from) }
        var to = closing.upperBound
        if to < text.endIndex, text[to] == "\n" { to = text.index(after: to) }
        let before = String(text[..<from]), after = String(text[to...])
        // Both newlines went with the block, so the line before it gets its own back where something follows.
        if !before.isEmpty, !before.hasSuffix("\n"), !after.isEmpty { return before + "\n" + after }
        if !before.isEmpty, !before.hasSuffix("\n") { return before + "\n" }
        return before + after
    }
}
