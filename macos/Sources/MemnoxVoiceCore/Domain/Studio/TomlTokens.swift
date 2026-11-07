import Foundation

/// What a run of TOML text is, so a code block colours it the way the console's does.
public enum TomlTokenKind: String, Equatable, Sendable {
    /// A `[table]` or `[[array]]` header, the whole line.
    case table
    /// The key of a `key = value` line.
    case key
    /// A double quoted string, its quotes included.
    case string
    /// The equals sign, brackets and commas between values.
    case punctuation
    case comment
    /// Whitespace and anything unquoted, such as a number or a boolean.
    case plain
}

public struct TomlToken: Equatable, Sendable {
    public let text: String
    public let kind: TomlTokenKind

    public init(_ text: String, _ kind: TomlTokenKind) {
        self.text = text
        self.kind = kind
    }
}

/// TOML cut into coloured runs one line at a time. Every character of the line lands in exactly one token, so joining
/// the tokens gives the line back.
public enum TomlTokens {
    private static let commentMark: Character = "#"
    private static let tableMark: Character = "["
    private static let assign: Character = "="
    private static let quote: Character = "\""
    private static let escape: Character = "\\"
    private static let separators: Set<Character> = ["[", "]", ",", "{", "}"]

    /// Every line of the text, tokenized on its own.
    public static func lines(_ text: String) -> [[TomlToken]] {
        text.components(separatedBy: "\n").map(line)
    }

    public static func line(_ line: String) -> [TomlToken] {
        let body = line.drop { $0 == " " || $0 == "\t" }
        let indent = String(line[..<body.startIndex])
        guard let first = body.first else { return line.isEmpty ? [] : [TomlToken(line, .plain)] }
        if first == commentMark { return [TomlToken(line, .comment)] }
        if first == tableMark { return [TomlToken(line, .table)] }
        guard let equals = body.firstIndex(of: assign) else { return [TomlToken(line, .plain)] }
        let key = body[..<equals]
        let name = key.trimmingCharacters(in: .whitespaces)
        let gap = String(key.dropFirst(name.count))
        let tokens = [TomlToken(indent, .plain), TomlToken(name, .key), TomlToken(gap, .plain), TomlToken(String(assign), .punctuation)]
            + value(String(body[body.index(after: equals)...]))
        return tokens.filter { !$0.text.isEmpty }
    }

    /// A value's strings, separators and the plain text between them.
    private static func value(_ text: String) -> [TomlToken] {
        var tokens: [TomlToken] = []
        var plain = ""
        var characters = text.makeIterator()
        func flush() {
            if !plain.isEmpty { tokens.append(TomlToken(plain, .plain)) }
            plain = ""
        }
        while let character = characters.next() {
            if character == quote {
                flush()
                var string = String(quote)
                var escaped = false
                while let next = characters.next() {
                    string.append(next)
                    if next == quote && !escaped { break }
                    escaped = next == escape && !escaped
                }
                tokens.append(TomlToken(string, .string))
            } else if character == commentMark {
                flush()
                var rest = String(character)
                while let next = characters.next() { rest.append(next) }
                tokens.append(TomlToken(rest, .comment))
            } else if separators.contains(character) {
                flush()
                tokens.append(TomlToken(String(character), .punctuation))
            } else {
                plain.append(character)
            }
        }
        flush()
        return tokens
    }
}
