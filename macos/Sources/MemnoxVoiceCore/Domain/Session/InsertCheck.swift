import Foundation

/// Whether words put into a box in one step, by an accessibility write or a paste, went in, read from the box before and
/// after, so a box that did nothing is typed into a key at a time and one that took something else is never typed into twice.
public enum InsertCheck {
    public enum Landing: Equatable, Sendable {
        /// The box holds the words now and did not before, or its caret moved by exactly their length.
        case landed
        /// Nothing about the box moved, so the words can be put in another way.
        case unchanged
        /// The box moved without showing the words, so a second try would risk the words going in twice.
        case changed
    }

    /// The value and caret are each nil when the box would not say; the caret alone counts only when the value cannot be read.
    public static func landing(
        _ words: String, valueBefore: String?, valueNow: String?, caretBefore: Int?, caretNow: Int?
    ) -> Landing {
        if let now = valueNow, now != valueBefore, TypedCheck.holds(now, words) { return .landed }
        if valueNow == nil, let before = caretBefore, let now = caretNow,
           now - before == words.utf16.count || now - before == words.count {
            return .landed
        }
        return valueNow == valueBefore && caretNow == caretBefore ? .unchanged : .changed
    }
}
