import Foundation

/// A card's summary as the brain wrote it, cut into the few block shapes a card lays out: headings,
/// bullets, fenced code and plain lines. Inline marks such as backticks and bold stay in the text,
/// for the view to render, so nothing the brain wrote is lost on the way to the screen.
public enum MarkdownBlock: Equatable {
    case heading(String)
    case bullet(String)
    case code(String)
    case text(String)

    public static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var fence: [String]?
        for raw in source.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let open = fence {
                    blocks.append(.code(open.joined(separator: "\n")))
                    fence = nil
                } else {
                    fence = []
                }
                continue
            }
            if fence != nil {
                fence?.append(raw)
                continue
            }
            if line.isEmpty { continue }
            if let heading = stripped(line, of: "#") {
                blocks.append(.heading(heading))
            } else if let item = bulleted(line) {
                blocks.append(.bullet(item))
            } else {
                blocks.append(.text(line))
            }
        }
        // A fence the brain never closed is still code, rather than lines that vanish.
        if let open = fence, !open.isEmpty { blocks.append(.code(open.joined(separator: "\n"))) }
        return blocks
    }

    /// "## Pushed" as "Pushed", for any depth of heading.
    private static func stripped(_ line: String, of mark: Character) -> String? {
        guard line.first == mark else { return nil }
        let rest = line.drop(while: { $0 == mark })
        guard rest.first == " " else { return nil }
        return rest.trimmingCharacters(in: .whitespaces)
    }

    /// "- item", "* item" or "1. item" as "item".
    private static func bulleted(_ line: String) -> String? {
        for mark in ["- ", "* ", "+ "] where line.hasPrefix(mark) {
            return String(line.dropFirst(mark.count))
        }
        guard let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty else {
            return nil
        }
        let rest = line[line.index(after: dot)...]
        return rest.first == " " ? rest.trimmingCharacters(in: .whitespaces) : nil
    }
}
