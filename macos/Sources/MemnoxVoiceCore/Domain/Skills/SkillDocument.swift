import Foundation

/// One block of a SKILL.md as the skill page draws it; the text inside each stays markdown, so bold, italics, inline
/// code and links are styled where it is drawn.
public enum SkillBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    /// One item of a list, how deep it sits, and its number when the list is numbered.
    case item(depth: Int, number: Int?, text: String)
    case code(language: String?, text: String)
    case quote(String)
    /// A table's rows, the header first, its separator line dropped.
    case table([[String]])
    case rule
}

/// A SKILL.md read whole: the front matter's fields in the order written, then its body as blocks.
public struct SkillDocument: Equatable, Sendable {
    public let fields: [SkillField]
    public let blocks: [SkillBlock]
}

/// One `key: value` line of the front matter.
public struct SkillField: Equatable, Sendable {
    public let key: String
    public let value: String
}

/// Splits a SKILL.md into blocks with no rendering of its own, so the page draws headings, lists and code fences the
/// way the person's agent reads them. Enough of CommonMark for skills, never all of it.
public enum SkillMarkdownReader {
    /// A heading is one to six hashes, as CommonMark has it.
    static let deepestHeading = 6
    /// The spaces one level of list nesting takes.
    static let indentPerDepth = 2
    private static let fence = "```"
    private static let tildeFence = "~~~"
    private static let frontMatterEdge = "---"

    public static func document(_ text: String) -> SkillDocument {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let fields = frontMatter(&lines)
        return SkillDocument(fields: fields, blocks: blocks(lines))
    }

    public static func parse(_ text: String) -> [SkillBlock] {
        document(text).blocks
    }

    /// Takes the front matter off the top, when the text opens with one, and reads its plain fields.
    private static func frontMatter(_ lines: inout [String]) -> [SkillField] {
        guard lines.first?.trimmingCharacters(in: .whitespaces) == frontMatterEdge,
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == frontMatterEdge })
        else { return [] }
        let fields: [SkillField] = lines[1 ..< end].compactMap { line in
            guard !line.hasPrefix(" "), let colon = line.firstIndex(of: ":") else { return nil }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard !key.isEmpty, !value.isEmpty else { return nil }
            return SkillField(key: key, value: value)
        }
        lines.removeSubrange(0 ... end)
        return fields
    }

    private static func blocks(_ lines: [String]) -> [SkillBlock] {
        var out: [SkillBlock] = []
        var paragraph: [String] = []
        var index = 0

        func flush() {
            if !paragraph.isEmpty { out.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(fence) || trimmed.hasPrefix(tildeFence) {
                flush()
                let marker = trimmed.hasPrefix(fence) ? fence : tildeFence
                let language = String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
                var body: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(marker) {
                    body.append(lines[index])
                    index += 1
                }
                out.append(.code(language: language.isEmpty ? nil : language, text: body.joined(separator: "\n")))
                index += 1
                continue
            }
            if trimmed.isEmpty {
                flush()
            } else if let heading = heading(trimmed) {
                flush()
                out.append(heading)
            } else if isRule(trimmed) {
                flush()
                out.append(.rule)
            } else if trimmed.hasPrefix(">") {
                flush()
                var quoted: [String] = []
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    quoted.append(String(lines[index].trimmingCharacters(in: .whitespaces).dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                out.append(.quote(quoted.joined(separator: " ")))
                continue
            } else if trimmed.hasPrefix("|") {
                flush()
                var rows: [[String]] = []
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    let row = lines[index].trimmingCharacters(in: .whitespaces)
                    if !isTableSeparator(row) { rows.append(cells(row)) }
                    index += 1
                }
                out.append(.table(rows))
                continue
            } else if let item = item(line) {
                flush()
                out.append(item)
            } else if case .item(let depth, let number, let text)? = out.last, paragraph.isEmpty, line.hasPrefix(" ") {
                // An indented line under an item carries the item on.
                out[out.count - 1] = .item(depth: depth, number: number, text: "\(text) \(trimmed)")
            } else {
                paragraph.append(trimmed)
            }
            index += 1
        }
        flush()
        return out
    }

    private static func heading(_ trimmed: String) -> SkillBlock? {
        let hashes = trimmed.prefix { $0 == "#" }.count
        guard hashes > 0, hashes <= deepestHeading else { return nil }
        let rest = trimmed.dropFirst(hashes)
        guard rest.isEmpty || rest.hasPrefix(" ") else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .trimmingCharacters(in: .whitespaces)
        return .heading(level: hashes, text: text)
    }

    private static func isRule(_ trimmed: String) -> Bool {
        let marks = trimmed.filter { $0 != " " }
        guard marks.count >= 3, let first = marks.first, "-*_".contains(first) else { return false }
        return marks.allSatisfy { $0 == first }
    }

    private static func item(_ line: String) -> SkillBlock? {
        let indent = line.prefix { $0 == " " }.count
        let depth = indent / indentPerDepth
        let rest = line.dropFirst(indent)
        for bullet in ["- ", "* ", "+ "] where rest.hasPrefix(bullet) {
            return .item(depth: depth, number: nil, text: String(rest.dropFirst(bullet.count)).trimmingCharacters(in: .whitespaces))
        }
        let digits = rest.prefix { $0.isNumber }
        guard !digits.isEmpty, let number = Int(digits) else { return nil }
        let after = rest.dropFirst(digits.count)
        guard after.hasPrefix(". ") || after.hasPrefix(") ") else { return nil }
        return .item(depth: depth, number: number, text: String(after.dropFirst(2)).trimmingCharacters(in: .whitespaces))
    }

    private static func isTableSeparator(_ row: String) -> Bool {
        row.allSatisfy { "|-: ".contains($0) }
    }

    private static func cells(_ row: String) -> [String] {
        var inner = Substring(row)
        if inner.hasPrefix("|") { inner = inner.dropFirst() }
        if inner.hasSuffix("|") { inner = inner.dropLast() }
        return inner.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
