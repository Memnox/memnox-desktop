import Foundation

/// A sentence as a voice should read it: the abbreviations, file names, flags and folder names
/// an agent's world is full of, written the way a person says them, so a speech model reads
/// "npm" as N P M and "Speech.swift" as Speech dot swift instead of guessing at the letters.
/// Only what is spoken passes through here; the caption and the card keep the words as written.
public func pronounced(_ text: String) -> String {
    var spoken = websites(in: text)
    spoken = fileNames(in: spoken)
    spoken = machineText(in: spoken)
    spoken = spoken.replacingOccurrences(of: Pattern.flag, with: "dash dash $1", options: .regularExpression)
    for (written, said) in phrases { spoken = replacingWord(written, with: said, in: spoken) }
    // "memnox-runtime" is two words said together, and a hyphen read aloud is a stumble.
    spoken = spoken.replacingOccurrences(of: Pattern.joiningHyphen, with: " ", options: .regularExpression)
    spoken = abbreviations(in: spoken)
    for (symbol, said) in symbols { spoken = spoken.replacingOccurrences(of: symbol, with: said) }
    return spoken.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

/// The regular expressions that find what a voice must say differently from how it is written.
private enum Pattern {
    /// A command line flag such as `--force`, but not a dash inside a word.
    static let flag = #"(?<![\w-])--([a-z][\w-]*)"#
    /// A hyphen between two letters, as in "memnox-runtime".
    static let joiningHyphen = #"(?<=[A-Za-z])-(?=[A-Za-z])"#
    /// A web address, capturing its host without "www.", and leaving any punctuation that ends the sentence.
    static let website = #"https?://(?:www\.)?([A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+)(?:[/?#][^\s]*[^\s.,;:!?)])?"#
    /// A file name with an ending of up to five letters, capturing the name and the ending past any folders.
    static let fileName = #"(?:[\w.~-]+/)*([\w-]+(?:\.[\w-]+)*)\.([A-Za-z]{1,5})\b"#
    /// Not preceded by a word character or a hyphen, so a phrase only matches as a whole word.
    static let wordStart = #"(?<![\w-])"#
    /// Not followed by a word character, the other half of matching a whole word.
    static let wordEnd = #"(?![\w])"#
}

/// Names that read wrong however they are spelled out, matched as whole words, first.
private let phrases: [(String, String)] = [
    ("Codex CLI", "Codex"),
    ("iTerm2", "eye term"),
    ("iTerm", "eye term"),
    ("Xcode", "X code"),
    ("SwiftUI", "Swift U I"),
    ("Vercel", "ver sell"),
    ("vitest", "vee test"),
    ("zsh", "Z shell"),
    ("stdout", "standard out"),
    ("stderr", "standard error"),
    ("sudo", "sue doo"),
    ("w/", "with"),
    ("macOS", "mac O S"),
    ("iOS", "i O S"),
    ("VS Code", "V S Code"),
    ("JSON", "Jason"),
    ("YAML", "yammel"),
    ("TOML", "tommel"),
    ("SQL", "sequel"),
    ("SQLite", "sequel light"),
    ("GitHub", "Git Hub"),
    ("OAuth", "O auth"),
    ("README", "read me"),
    ("TODO", "to do"),
    ("OK", "okay"),
    ("e.g.", "for example"),
    ("i.e.", "that is"),
    ("vs.", "versus"),
    ("etc.", "and so on"),
]

/// Short words a model reads as one word when a person spells them, lower case included.
private let spelled: Set<String> = [
    "npm", "cli", "api", "ui", "ux", "mcp", "ssh", "url", "pr", "id", "ci", "cd",
    "aws", "gcp", "gpu", "cpu", "tts", "llm", "sdk", "dm", "pid", "tty", "html", "css",
    "http", "https", "dns", "jwt", "pdf", "png", "svg", "csv", "os", "ai", "ip", "vm",
    "pnpm", "npx", "otlp", "sha", "ssd", "tsx",
]

/// Upper case words a person says as a word rather than letter by letter.
private let wordsInCapitals: Set<String> = ["NASA", "I", "A", "OK", "JSON", "YAML", "TOML", "SQL", "GIF", "RAM", "ROM", "LAN", "WAN", "ASAP"]

/// File endings as they are said.
private let endings: [String: String] = [
    "ts": "T S", "tsx": "T S X", "js": "J S", "jsx": "J S X", "py": "pie", "md": "markdown",
    "rs": "R S", "go": "go", "rb": "ruby", "sh": "S H", "yml": "yammel", "yaml": "yammel",
    "json": "Jason", "toml": "tommel", "swift": "swift", "css": "C S S", "html": "H T M L",
    "png": "P N G", "svg": "S V G", "plist": "P list", "lock": "lock", "txt": "text",
]

/// Symbols as they are said, spaced where a symbol alone would be ambiguous.
private let symbols: [(String, String)] = [
    (" & ", " and "), ("%", " percent"), (" + ", " plus "), (" = ", " equals "),
    (" -> ", " to "), (" => ", " to "), ("~/", "home "), ("@", " at "),
]

/// A web address as the site it is on, since nobody reads a whole link out: "github dot com".
private func websites(in text: String) -> String {
    guard let expression = try? NSRegularExpression(pattern: Pattern.website) else { return text }
    var result = text
    for match in expression.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
        guard let whole = Range(match.range, in: result), let host = Range(match.range(at: 1), in: result) else { continue }
        result.replaceSubrange(whole, with: result[host].replacingOccurrences(of: ".", with: " dot "))
    }
    return result
}

/// What machines print and people never say as written: branch prefixes, commit hashes, version
/// numbers, units and issue numbers, each turned into the words a person would use.
private func machineText(in text: String) -> String {
    var spoken = text
    for (pattern, template) in machineWords {
        spoken = spoken.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
    }
    return spoken
}

/// Each pattern with the words it is said as, applied in order.
private let machineWords: [(String, String)] = [
    // "feat/voice-answers" is the voice answers feature branch, and read as written it is a stumble.
    (#"\bfeat/"#, "feature "),
    (#"\b(fix|chore|docs|refactor|perf|test|style|release|hotfix)/"#, "$1 "),
    // A commit hash is never said; that it was a commit is the part worth hearing.
    (#"\b(?=[0-9a-f]*[0-9])(?=[0-9a-f]*[a-f])[0-9a-f]{7,40}\b"#, "commit"),
    (#"\bv?(\d+)\.(\d+)\.(\d+)\b"#, "$1 point $2 point $3"),
    (#"(\d)\s?ms\b"#, "$1 milliseconds"),
    (#"(\d)\s?KB\b"#, "$1 kilobytes"),
    (#"(\d)\s?MB\b"#, "$1 megabytes"),
    (#"(\d)\s?GB\b"#, "$1 gigabytes"),
    (#"(\d)x\b"#, "$1 times"),
    (#"#(\d+)"#, "number $1"),
]

/// `Speech.swift` as Speech dot swift, and a path down to its last part, which is how a file is named aloud.
private func fileNames(in text: String) -> String {
    guard let expression = try? NSRegularExpression(pattern: Pattern.fileName) else { return text }
    var result = text
    let range = NSRange(result.startIndex..., in: result)
    for match in expression.matches(in: result, range: range).reversed() {
        guard let whole = Range(match.range, in: result),
              let name = Range(match.range(at: 1), in: result),
              let ending = Range(match.range(at: 2), in: result),
              let said = endings[result[ending].lowercased()]
        else { continue }
        let base = result[name].replacingOccurrences(of: ".", with: " dot ")
        result.replaceSubrange(whole, with: "\(base) dot \(said)")
    }
    return result
}

/// "UI", "MCP" and "npm" said letter by letter, leaving words a person says whole.
private func abbreviations(in text: String) -> String {
    var words: [String] = []
    for token in text.split(separator: " ", omittingEmptySubsequences: false) {
        let core = token.trimmingCharacters(in: .punctuationCharacters)
        guard !core.isEmpty, let range = token.range(of: core) else {
            words.append(String(token))
            continue
        }
        let lower = core.lowercased()
        let capitals = spelledCapitals.contains(core.count) && core.allSatisfy { $0.isUppercase && $0.isLetter }
        let plural = core.count >= shortestPlural && core.dropLast().allSatisfy { $0.isUppercase } && core.last == "s"
        let spell = spelled.contains(lower) || (capitals && !wordsInCapitals.contains(core))
        guard spell || plural else {
            words.append(String(token))
            continue
        }
        let letters = (plural ? core.dropLast() : Substring(core)).uppercased().map(String.init).joined(separator: " ")
        let said = plural ? "\(letters)'s" : letters
        words.append(token.replacingCharacters(in: range, with: said))
    }
    return words.joined(separator: " ")
}

/// A run of capitals this long reads as an abbreviation, so it is spelled out letter by letter.
private let spelledCapitals = 2...5
/// "PRs" or "IDs": at least two capitals and the plural "s".
private let shortestPlural = 3

private func replacingWord(_ word: String, with said: String, in text: String) -> String {
    let escaped = NSRegularExpression.escapedPattern(for: word)
    return text.replacingOccurrences(of: Pattern.wordStart + escaped + Pattern.wordEnd, with: said, options: .regularExpression)
}
