import Foundation

/// The longest caption the pill shows, which fits its width in one line at the caption size.
public let captionLimit = 40

/// The pill's one line: short enough to read at a glance, cut at a word.
public func caption(_ text: String, limit: Int = captionLimit) -> String {
    let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
    guard flat.count > limit else { return flat }
    let cut = flat.prefix(limit)
    let word = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
    return "\(word)…"
}

/// `mcp__memnox-operator__sessions` as a person would read it.
public func toolWord(_ tool: String?) -> String {
    guard let tool else { return "the machine" }
    return tool.components(separatedBy: mcpToolSeparator).last ?? tool
}

/// What an MCP tool name puts between its server and the tool itself.
private let mcpToolSeparator = "__"
