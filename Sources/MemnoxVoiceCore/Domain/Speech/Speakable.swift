import Foundation

/// Only what a voice should say: no markdown, no code marks, and a pause where a dash stood.
public func speakable(_ text: String) -> String {
    var spoken = text
    for mark in markdownMarks { spoken = spoken.replacingOccurrences(of: mark, with: "") }
    for dash in spokenDashes {
        spoken = spoken.replacingOccurrences(of: dash, with: ", ")
    }
    return spoken.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

/// Code marks, emphasis, headings and strikethrough, which a voice would otherwise read out.
private let markdownMarks = ["`", "*", "#", "_", "~"]
/// Em and en dashes, spaced first so the spaces go with them.
private let spokenDashes = [" \u{2014} ", "\u{2014}", " \u{2013} ", "\u{2013}"]
