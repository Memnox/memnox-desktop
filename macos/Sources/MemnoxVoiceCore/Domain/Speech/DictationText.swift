import Foundation

/// How dictated words are laid out for the app they land in: whole written sentences for mail, documents and
/// editors, and a chat message for a messenger, which nobody ends with a full stop.
public enum DictationStyle: Equatable, Sendable {
    case written
    case chat
    /// A prompt for an agent or a line in an editor or terminal: sentences as said, and no full stop at the end.
    case bare

    /// The style for the app in front, by the name macOS gives it; written wherever it is not a known messenger.
    public init(appName: String?) {
        let name = appName?.lowercased() ?? ""
        self = DictationStyle.messengers.contains(where: { name.contains($0) }) ? .chat : .written
    }

    private static let messengers = ["messages", "slack", "whatsapp", "discord", "telegram", "signal", "teams", "messenger"]
}

/// What was said, written the way the person would have typed it: hesitations gone, "scratch that" taking back
/// the sentence before it, "new line" and "new paragraph" kept as breaks, names spelled as their dictionary spells
/// them, items counted off one by one laid out as a list, and the sentences capitalised and closed. Every rule here
/// is about how the words are written and never about what they mean, so nothing acts on a word.
public func cleanedDictation(
    _ said: String, dictionary: [String] = [], replacements: [DictationWord] = [], style: DictationStyle = .written
) -> String {
    var text = takingBack(said)
    text = withBreaks(text)
    text = withoutHesitations(text)
    text = replaced(text, by: replacements)
    text = spelledAsTheirs(text, dictionary: dictionary)
    text = asList(text) ?? text
    return tidied(text, style: style)
}

/// What is typed while the person is still speaking: the same cleanup without the layout only the whole can decide,
/// so no list and no closing stop yet, and the word still being said held back until the next one starts, since the
/// recognizer is still changing it. Once `final`, every word goes in.
public func liveDictation(
    _ heard: String, final: Bool, dictionary: [String] = [], replacements: [DictationWord] = []
) -> String {
    let said = final ? heard : wordsSettled(heard)
    var text = takingBack(said)
    text = withBreaks(text)
    text = withoutHesitations(text)
    text = replaced(text, by: replacements)
    text = spelledAsTheirs(text, dictionary: dictionary)
    return tidied(text, style: .bare)
}

/// Everything up to the word still being said: whole when it already ends on a space or a mark.
private func wordsSettled(_ heard: String) -> String {
    guard let last = heard.last, last.isLetter || last.isNumber else { return heard }
    guard let space = heard.lastIndex(where: \.isWhitespace) else { return "" }
    return String(heard[..<space])
}

/// The person's own replacements and spoken shortcuts, each said phrase written their way wherever it stands whole,
/// as "my email" for their address. Applied to the Mac's cleanup and again to the polished text, so a shortcut holds
/// whichever wrote it.
public func replaced(_ text: String, by words: [DictationWord]) -> String {
    var result = text
    for word in words {
        guard let said = word.said?.trimmingCharacters(in: .whitespaces), !said.isEmpty else { continue }
        let pattern = "(?i)(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: said) + "(?![\\p{L}\\p{N}])"
        result = result.replacingOccurrences(
            of: pattern, with: NSRegularExpression.escapedTemplate(for: word.written), options: .regularExpression)
    }
    return result
}

/// Dictation fitted to where the cursor is: a space before it when it follows a word, and when it carries on a
/// sentence already begun, no capital at its start and no full stop at its end where more of that sentence follows.
public func fitted(_ text: String, after before: String?, before after: String?) -> String {
    guard !text.isEmpty else { return text }
    var result = text
    let previous = before?.last
    let carriesOn = before.map(sentenceGoesOn) ?? false
    if carriesOn, let first = result.first, first.isUppercase, !keepsItsCapital(result) {
        result = first.lowercased() + result.dropFirst()
    }
    if let next = after?.first, next.isLetter || next.isNumber {
        if result.hasSuffix("."), !result.hasSuffix("...") { result.removeLast() }
        result += " "
    }
    if let previous, !previous.isWhitespace, !"([{\"'".contains(previous) { result = " " + result }
    return result
}

/// Whether the text before the cursor stops mid sentence, so what comes next continues it.
private func sentenceGoesOn(_ before: String) -> Bool {
    guard let last = before.last(where: { !$0.isWhitespace }) else { return false }
    return last.isLetter || last.isNumber || last == ","
}

/// "I", a name and an acronym keep their capital wherever they stand.
private func keepsItsCapital(_ text: String) -> Bool {
    let word = text.prefix { $0.isLetter }
    if word == "I" { return true }
    return word.dropFirst().contains(where: \.isUppercase)
}

// MARK: Taking words back

/// "Scratch that" takes back the sentence before it, so a sentence said twice is written once.
private let takeBacks = ["scratch that", "strike that", "delete that"]

private func takingBack(_ text: String) -> String {
    var result = text
    while let range = takeBacks.compactMap({ result.range(of: $0, options: .caseInsensitive) }).min(by: { $0.lowerBound < $1.lowerBound }) {
        let before = String(result[..<range.lowerBound]).trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
        let after = String(result[range.upperBound...]).trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ",.")))
        // Back to the end of the sentence before the one taken back, or to the start.
        let kept = before.lastIndex(where: { sentenceEnds.contains($0) }).map { String(before[...$0]) } ?? ""
        result = kept.isEmpty ? after : "\(kept) \(after)"
    }
    return result
}

private let sentenceEnds: Set<Character> = [".", "?", "!", "\n"]

// MARK: Breaks

private func withBreaks(_ text: String) -> String {
    text
        .replacingOccurrences(of: #"[,.]?\s*\bnew paragraph\b[,.]?\s*"#, with: "\n\n", options: [.regularExpression, .caseInsensitive])
        .replacingOccurrences(of: #"[,.]?\s*\bnew line\b[,.]?\s*"#, with: "\n", options: [.regularExpression, .caseInsensitive])
}

// MARK: Hesitations

/// Sounds people make while they think, never words they meant to write.
private let hesitations = ["um", "umm", "uh", "uhh", "uhm", "erm", "er", "hmm", "mm", "ah"]

private func withoutHesitations(_ text: String) -> String {
    let alternatives = hesitations.joined(separator: "|")
    // The comma the recognizer wrote around one goes with it, so no stray comma is left behind.
    return text.replacingOccurrences(of: #"\b(\#(alternatives))\b,?\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
}

// MARK: Their spelling

/// Shortest name worth respelling, so short words that happen to run together never turn into a name.
private let shortestName = 4
/// A name heard as up to this many words, as "post gres" for Postgres or "wako AI" for WakoAI.
private let mostWordsPerName = 3

private func spelledAsTheirs(_ text: String, dictionary: [String]) -> String {
    var spelled: [String: String] = [:]
    for name in dictionary {
        let key = lettersOf(name)
        if key.count >= shortestName { spelled[key] = name }
    }
    guard !spelled.isEmpty else { return text }
    var words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
    var index = 0
    while index < words.count {
        for length in stride(from: min(mostWordsPerName, words.count - index), through: 1, by: -1) {
            let run = words[index..<index + length]
            guard let name = spelled[lettersOf(run.joined())] else { continue }
            // Punctuation the recognizer put after the last word stays after the name.
            let trailing = String((run.last ?? "").reversed().prefix { !$0.isLetter && !$0.isNumber }.reversed())
            words.replaceSubrange(index..<index + length, with: [name + trailing])
            break
        }
        index += 1
    }
    return words.joined(separator: " ")
}

private func lettersOf(_ text: String) -> String {
    String(text.lowercased().filter { $0.isLetter || $0.isNumber })
}

// MARK: Lists

/// Counting words a person uses to go through items, in order.
private let counting = ["first", "second", "third", "fourth", "fifth", "sixth"]
/// Fewer than this is a sentence with a "first" in it, not a list.
private let fewestItems = 3

/// Items counted off as "first ..., second ..., third ..." laid out one per line, with what came before as its lead;
/// nil when nothing was counted off.
private func asList(_ text: String) -> String? {
    let pattern = #"(?i)\b(first|second|third|fourth|fifth|sixth)(ly)?\b[,:]?\s*"#
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
    let whole = NSRange(text.startIndex..., in: text)
    let found = expression.matches(in: text, range: whole)
    // In order from first, so "the second time" in a sentence is never mistaken for an item.
    var marks: [NSTextCheckingResult] = []
    for match in found {
        guard let word = Range(match.range(at: 1), in: text).map({ text[$0].lowercased() }) else { continue }
        if word == counting[marks.count] { marks.append(match) }
        if marks.count == counting.count { break }
    }
    guard marks.count >= fewestItems, let first = marks.first, let start = Range(first.range, in: text) else { return nil }
    let lead = text[..<start.lowerBound].trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ",")))
    var items: [String] = []
    for (position, mark) in marks.enumerated() {
        guard let from = Range(mark.range, in: text) else { return nil }
        let end = position + 1 < marks.count ? Range(marks[position + 1].range, in: text)?.lowerBound ?? text.endIndex : text.endIndex
        let item = text[from.upperBound..<end].trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ",.;")))
        // "and" joining the last item to the one before is part of how it was said, not of the item.
        items.append(capitalisedFirst(item.replacingOccurrences(of: #"\s+and$"#, with: "", options: .regularExpression)))
    }
    let heading = lead.isEmpty ? "" : (lead.hasSuffix(":") ? lead : lead.trimmingCharacters(in: .punctuationCharacters) + ":") + "\n"
    return heading + items.map { "- \($0)" }.joined(separator: "\n")
}

// MARK: Tidying

private func tidied(_ text: String, style: DictationStyle) -> String {
    var result = text
        .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #" +([,.?!:;])"#, with: "$1", options: .regularExpression)
        .replacingOccurrences(of: #"([,;:])\."#, with: ".", options: .regularExpression)
        .replacingOccurrences(of: #" *\n *"#, with: "\n", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    result = capitalisedSentences(result)
    let isList = result.contains("\n- ")
    switch style {
    case .written:
        if !isList, let last = result.last, last.isLetter || last.isNumber { result += "." }
    case .chat, .bare:
        if result.hasSuffix("."), !result.hasSuffix("...") { result.removeLast() }
    }
    return result
}

/// A sentence starts after a full stop, question or exclamation mark only once a space follows it, so the dot in
/// "server.py" or "e.g." never capitalises what comes after it.
private func capitalisedSentences(_ text: String) -> String {
    var result = ""
    var startOfSentence = true
    var previous: Character?
    for character in text {
        if character == "\n" || (character == " " && previous.map { sentenceEnds.contains($0) } == true) {
            startOfSentence = true
        }
        if startOfSentence, character.isLetter {
            result += character.uppercased()
            startOfSentence = false
        } else {
            if startOfSentence, character.isNumber { startOfSentence = false }
            result.append(character)
        }
        previous = character
    }
    return result
}

private func capitalisedFirst(_ text: String) -> String {
    text.prefix(1).uppercased() + text.dropFirst()
}
