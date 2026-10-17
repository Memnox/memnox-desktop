import Foundation

/// Text from a session made fit to read: a prompt pasted from a terminal carries icon glyphs only its own
/// font can draw, which every other font shows as a box with a question mark.
public enum SessionReading {
    /// The Unicode private use areas, where terminal themes keep their icons.
    private static let privateUse: [ClosedRange<UInt32>] = [0xE000...0xF8FF, 0xF0000...0xFFFFD, 0x100000...0x10FFFD]
    /// The mark a font draws for a character it lost.
    private static let replacement: UInt32 = 0xFFFD

    /// The words with icon glyphs and control characters gone and their runs of space made one, or nil when nothing is left.
    public static func readable(_ text: String?) -> String? {
        guard let text else { return nil }
        let kept = text.unicodeScalars.map { scalar -> String in
            if scalar.value == replacement || privateUse.contains(where: { $0.contains(scalar.value) }) { return " " }
            if CharacterSet.controlCharacters.contains(scalar) || CharacterSet.newlines.contains(scalar) { return " " }
            return String(scalar)
        }.joined()
        let words = kept.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return words.isEmpty ? nil : words
    }

    /// A repository name worth showing, since a folder named only by dots says nothing about where the work is.
    public static func repository(_ name: String?) -> String? {
        guard let name = readable(name), !name.allSatisfy({ $0 == "." || $0 == "/" }) else { return nil }
        return name
    }
}

/// One line of a file's diff as the live window draws it, numbered on the side it belongs to.
public struct DiffLine: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Where a run of changes starts, with the code it sits in when the diff names it.
        case hunk
        case added
        case removed
        case context
    }

    public let kind: Kind
    public let text: String
    /// The line's number in the file before the change, for a removed or unchanged line.
    public let old: Int?
    /// Its number after the change, for an added or unchanged line.
    public let new: Int?

    public init(kind: Kind, text: String, old: Int? = nil, new: Int? = nil) {
        self.kind = kind
        self.text = text
        self.old = old
        self.new = new
    }

    /// A unified diff's hunks as numbered lines; header lines before the first hunk are left out.
    public static func of(_ lines: [String]) -> [DiffLine] {
        var old = 0
        var new = 0
        var parsed: [DiffLine] = []
        for line in lines {
            if line.hasPrefix("@@") {
                (old, new) = starts(of: line)
                let tail = line.components(separatedBy: "@@").dropFirst(2).joined(separator: "@@")
                parsed.append(DiffLine(kind: .hunk, text: tail.trimmingCharacters(in: .whitespaces)))
            } else if parsed.isEmpty || line.hasPrefix("\\") {
                continue
            } else if line.hasPrefix("+") {
                parsed.append(DiffLine(kind: .added, text: String(line.dropFirst()), new: new))
                new += 1
            } else if line.hasPrefix("-") {
                parsed.append(DiffLine(kind: .removed, text: String(line.dropFirst()), old: old))
                old += 1
            } else {
                parsed.append(DiffLine(kind: .context, text: String(line.dropFirst()), old: old, new: new))
                old += 1
                new += 1
            }
        }
        return parsed
    }

    /// The first line numbers a hunk header gives, as in `@@ -12,6 +12,9 @@`.
    private static func starts(of header: String) -> (Int, Int) {
        let parts = header.split(separator: " ")
        func number(_ sign: Character) -> Int {
            guard let part = parts.first(where: { $0.first == sign }) else { return 0 }
            return Int(part.dropFirst().split(separator: ",").first ?? "") ?? 0
        }
        return (number("-"), number("+"))
    }
}

/// An agent's reply cut into what markdown makes of it, so a heading reads as one and not as two hashes.
public enum ReplyBlock: Equatable, Sendable {
    case heading(String)
    case bullet(String)
    case numbered(Int, String)
    case code(String)
    case paragraph(String)

    private static let headingMarks: Set<Character> = ["#"]
    private static let bulletMarks = ["- ", "* ", "\u{2022} "]
    private static let fence = "```"

    /// The reply's blocks in order; inline marks such as bold and code stay for the view to draw.
    public static func of(_ text: String) -> [ReplyBlock] {
        var blocks: [ReplyBlock] = []
        var paragraph: [String] = []
        var code: [String]?
        func closeParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix(fence) {
                if let open = code {
                    blocks.append(.code(open.joined(separator: "\n")))
                    code = nil
                } else {
                    closeParagraph()
                    code = []
                }
                continue
            }
            if code != nil {
                code?.append(raw)
                continue
            }
            if line.isEmpty {
                closeParagraph()
            } else if let first = line.first, headingMarks.contains(first) {
                closeParagraph()
                blocks.append(.heading(line.drop(while: { headingMarks.contains($0) }).trimmingCharacters(in: .whitespaces)))
            } else if let mark = bulletMarks.first(where: line.hasPrefix) {
                closeParagraph()
                blocks.append(.bullet(String(line.dropFirst(mark.count))))
            } else if let (number, rest) = numbered(line) {
                closeParagraph()
                blocks.append(.numbered(number, rest))
            } else {
                paragraph.append(line)
            }
        }
        // A reply cut short inside a code block still shows what it had.
        if let open = code { blocks.append(.code(open.joined(separator: "\n"))) }
        closeParagraph()
        return blocks
    }

    /// `3. Do this` as its number and its words.
    private static func numbered(_ line: String) -> (Int, String)? {
        guard let dot = line.firstIndex(of: "."), let number = Int(line[..<dot]),
              line.index(after: dot) < line.endIndex, line[line.index(after: dot)] == " " else { return nil }
        return (number, String(line[line.index(dot, offsetBy: 2)...]))
    }
}
