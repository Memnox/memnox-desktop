import Foundation

/// Whether the box Memnox typed into holds what it typed, read before Return, since a box that was empty all along also
/// reads empty after it, and taking that for the message going is how words typed into the wrong place were called sent.
public enum TypedCheck {
    /// The end of a long message is enough to find it, since an app may tidy or wrap the start as it goes in.
    static let tail = 40

    public static func holds(_ value: String, _ words: String) -> Bool {
        let have = normal(value), want = normal(words)
        guard !want.isEmpty else { return true }
        if have.contains(want) { return true }
        return want.count > tail && have.contains(String(want.suffix(tail)))
    }

    /// Case and spacing set aside, since a box may soft wrap, capitalise or turn two spaces into one.
    private static func normal(_ text: String) -> String {
        text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
