import Foundation

/// Whether an app took a message once Return was pressed, read from what changed: its box letting the words go, the
/// words showing as a new line in its window, or its window changing, since chat apps differ in which of those they do.
public enum SendCheck {
    /// The start of a long message that is enough to know it again among the window's text.
    public static let shownLength = 60

    public enum Sign: Equatable, Sendable {
        case boxEmptied
        case shownInWindow
        case boxMovedOn
        case windowChanged

        /// What was checked, said to the person as the proof that the message went.
        public var checked: String {
            switch self {
            case .boxEmptied: "its message box holding the words, then taking them and emptying"
            case .shownInWindow: "its message box holding the words, then the words showing in its window as sent"
            case .boxMovedOn: "its message box holding the words, then letting them go after Return"
            case .windowChanged: "its message box holding the words, then its window changing after Return"
            }
        }
    }

    /// The first sign the message went, or nil while none shows; `boxNow` is nil when the box cannot be read, and
    /// the texts are the window's static text before Return and now, empty when they were not read.
    public static func sign(
        sent words: String, boxNow: String?, textBefore: [String], textNow: [String], windowChanged: Bool
    ) -> Sign? {
        if let box = boxNow {
            if TypedCheck.normal(box).isEmpty { return .boxEmptied }
        }
        if shownCount(of: words, in: textNow) > shownCount(of: words, in: textBefore) { return .shownInWindow }
        if let box = boxNow, !TypedCheck.holds(box, words) { return .boxMovedOn }
        return windowChanged ? .windowChanged : nil
    }

    /// How many lines show the message: a short one only as a whole line, since a few words can turn up anywhere,
    /// and a long one by its start, since a run that long is the message itself.
    static func shownCount(of words: String, in lines: [String]) -> Int {
        let want = TypedCheck.normal(words)
        guard !want.isEmpty else { return 0 }
        if want.count <= shownLength { return lines.filter { TypedCheck.normal($0) == want }.count }
        let start = String(want.prefix(shownLength))
        return lines.filter { TypedCheck.normal($0).contains(start) }.count
    }
}
