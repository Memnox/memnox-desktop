import Foundation
import MemnoxVoiceCore

/// The person's dictionary and their latest dictations, kept on this Mac only and shown on the Dictation page.
@MainActor
final class DictationStore: ObservableObject {
    @Published private(set) var dictionary: DictationDictionary
    @Published private(set) var history: DictationHistory

    /// Whether dictation is polished by the person's own Claude Code, which sends it to their model provider as any of
    /// their Claude Code use does; on from the start, and off means it is cleaned on this Mac only.
    static let polishKey = "dictationPolish"
    /// Whether the words go into the field while the person is still speaking, revised as they firm up.
    static let liveKey = "dictationLive"
    private static let dictionaryKey = "dictationDictionary"
    private static let historyKey = "dictationHistory"

    init() {
        dictionary = Self.load(Self.dictionaryKey) ?? DictationDictionary()
        history = Self.load(Self.historyKey) ?? DictationHistory()
    }

    var polishes: Bool { UserDefaults.standard.bool(forKey: Self.polishKey) }
    var typesLive: Bool { UserDefaults.standard.bool(forKey: Self.liveKey) }

    func add(_ word: DictationWord) {
        dictionary.add(word)
        save(dictionary, Self.dictionaryKey)
    }

    func remove(_ id: UUID) {
        dictionary.remove(id)
        save(dictionary, Self.dictionaryKey)
    }

    func learn(_ corrections: [WordCorrection]) {
        guard !corrections.isEmpty else { return }
        dictionary.learn(corrections)
        save(dictionary, Self.dictionaryKey)
    }

    func record(_ entry: DictationEntry) {
        history.add(entry)
        save(history, Self.historyKey)
    }

    func clearHistory() {
        history.clear()
        save(history, Self.historyKey)
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }
}
