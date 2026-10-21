import Foundation

/// One word in the person's dictionary: a spelling of their own when nothing is said for it, as "WakoAI", or a
/// replacement when it is, as "my email" written as their address. Corrections they make after dictating land here too.
public struct DictationWord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    /// What they say, or nil for a spelling, which is matched by how it sounds run together.
    public var said: String?
    public var written: String

    public init(id: UUID = UUID(), said: String? = nil, written: String) {
        self.id = id
        self.said = said.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        self.written = written
    }
}

/// The dictionary as a whole: spellings for the cleanup and the model, replacements for both.
public struct DictationDictionary: Codable, Equatable, Sendable {
    public private(set) var words: [DictationWord]

    public init(words: [DictationWord] = []) {
        self.words = words
    }

    /// The person's own spellings, which also go to the model as their vocabulary.
    public var spellings: [String] { words.filter { $0.said == nil }.map(\.written) }
    public var replacements: [DictationWord] { words.filter { $0.said != nil } }

    /// Added once: a second entry for the same said words replaces the first, so a correction made twice is one entry.
    public mutating func add(_ word: DictationWord) {
        let written = word.written.trimmingCharacters(in: .whitespaces)
        guard !written.isEmpty else { return }
        let key = word.said?.lowercased() ?? written.lowercased()
        words.removeAll { ($0.said?.lowercased() ?? $0.written.lowercased()) == key }
        words.append(DictationWord(id: word.id, said: word.said, written: written))
    }

    public mutating func remove(_ id: UUID) {
        words.removeAll { $0.id == id }
    }

    /// What the person fixed in text they dictated, kept as replacements so the same mishearing is written right next time.
    public mutating func learn(_ corrections: [WordCorrection]) {
        for correction in corrections { add(DictationWord(said: correction.heard, written: correction.meant)) }
    }
}

/// One dictation as it went: what was heard, what was written, and where.
public struct DictationEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var at: Date
    public var heard: String
    public var written: String
    public var app: String?
    /// How long the person spoke, for words a minute; absent from a dictation recorded before it was kept.
    public var seconds: Double?

    public init(id: UUID = UUID(), at: Date, heard: String, written: String, app: String?, seconds: Double? = nil) {
        self.id = id
        self.at = at
        self.heard = heard
        self.written = written
        self.app = app
        self.seconds = seconds
    }

    /// The words that went in, as the person would count them.
    public var words: Int { written.split(whereSeparator: \.isWhitespace).count }
}

/// The latest dictations, newest first, so a lost one can be copied again and a bad one seen for what was heard.
public struct DictationHistory: Codable, Equatable, Sendable {
    public private(set) var entries: [DictationEntry]
    /// Enough to find this morning's, few enough to keep nothing the person forgot they said.
    public static let kept = 50

    public init(entries: [DictationEntry] = []) {
        self.entries = entries
    }

    public mutating func add(_ entry: DictationEntry) {
        entries.insert(entry, at: 0)
        if entries.count > Self.kept { entries.removeLast(entries.count - Self.kept) }
    }

    public mutating func clear() {
        entries.removeAll()
    }

    public mutating func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }

    public var last: DictationEntry? { entries.first }
}
