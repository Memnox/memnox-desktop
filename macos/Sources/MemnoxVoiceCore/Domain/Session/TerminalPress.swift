import Foundation

/// A key named in the runtime's press display, as TERMINAL_KEY names it there.
public enum TerminalKey: String, Sendable, CaseIterable {
    case up, down, left, right, enter, escape, tab, space

    /// The virtual key code, written out so Carbon need not be imported for eight keys.
    public var code: UInt16 {
        switch self {
        case .up: 126
        case .down: 125
        case .left: 123
        case .right: 124
        case .enter: 36
        case .escape: 53
        case .tab: 48
        case .space: 49
        }
    }

    /// What a terminal reads for the key, for an app handed text rather than key presses, such as iTerm2.
    public var sequence: String {
        switch self {
        case .up: "\u{1B}[A"
        case .down: "\u{1B}[B"
        case .right: "\u{1B}[C"
        case .left: "\u{1B}[D"
        case .enter: "\r"
        case .escape: "\u{1B}"
        case .tab: "\t"
        case .space: " "
        }
    }
}

/// One key pressed to answer what an agent asks in its terminal: a named key, or one letter or digit.
public enum TerminalPress: Equatable, Sendable {
    case key(TerminalKey)
    case character(Character)

    /// As many as the runtime sends, enough to move down a list and pick, never a sentence a key at a time.
    public static let mostKeys = 8

    /// The keys the words name, in order, or nil when any word is not a key, so nothing else is ever pressed.
    public static func parse(_ words: String) -> [TerminalPress]? {
        let names = words.lowercased().split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init)
        guard !names.isEmpty, names.count <= mostKeys else { return nil }
        var keys: [TerminalPress] = []
        for name in names {
            if let key = TerminalKey(rawValue: name) {
                keys.append(.key(key))
            } else if name.count == 1, let character = name.first, character.isASCII, character.isLetter || character.isNumber {
                keys.append(.character(character))
            } else {
                return nil
            }
        }
        return keys
    }

    /// What a terminal reads for this press.
    public var sequence: String {
        switch self {
        case .key(let key): key.sequence
        case .character(let character): String(character)
        }
    }
}
