import Foundation

/// One phrase taught to the recognizer's own language model, with how often people say it. Like the
/// hints it only helps the recognizer hear a word, and nothing acts on one.
public struct TaughtPhrase: Equatable, Sendable {
    public let phrase: String
    public let count: Int

    public init(_ phrase: String, _ count: Int) {
        self.phrase = phrase
        self.count = count
    }
}

/// How a name nobody's dictionary has is said, in the X-SAMPA the recognizer reads, one phoneme per space.
public struct TaughtPronunciation: Equatable, Sendable {
    public let grapheme: String
    public let phonemes: String

    public init(_ grapheme: String, _ phonemes: String) {
        self.grapheme = grapheme
        self.phonemes = phonemes
    }

    /// Whether every sound in it is one the recognizer knows, since one unknown sound fails the whole model.
    public func readable(by known: Set<String>) -> Bool {
        phonemes.split(separator: " ").allSatisfy { known.contains(String($0)) }
    }
}

/// The names said most, always taught, since they are what a person names most.
public let taughtAgents = ["Claude Code", "Claude", "Codex", "Cursor", "Hermes", "OpenClaw", "Memnox", "ChatGPT"]

/// Where an agent's name falls in a sentence, so it is expected where it is said.
private let agentSlot: [(String, Int)] = [
    ("<name>", 400),
    ("open a new <name> session", 300),
    ("start a new <name> session", 300),
    ("start <name>", 200),
    ("open <name>", 200),
    ("ask <name>", 200),
    ("tell <name> to", 150),
    ("have <name> review", 150),
    ("open <name> desktop", 200),
    ("open the <name> app", 200),
    ("ask <name> to review my changes", 150),
    ("what is <name> doing", 150),
    ("show me the <name> session", 150),
    ("is <name> working", 100),
    ("stop <name>", 100),
    ("close the <name> session", 100),
    ("the <name> session", 150),
]

/// Where this machine's own names fall: its folders, repositories, servers and tools, so "within the babco
/// folder" is expected rather than "within Lab Babco". Each count is per name, kept well under the agents'
/// so a few hundred folder names never outweigh the requests around them.
private let placeSlot: [(String, Int)] = [
    ("<name>", 50),
    ("the <name> folder", 20),
    ("in the <name> folder", 20),
    ("within the <name> folder", 15),
    ("within <name> folder", 10),
    ("in <name>", 15),
    ("within <name>", 10),
    ("open the <name> folder", 15),
    ("start a new session in <name>", 15),
    ("start a new session in the <name> folder", 15),
    ("start a new session within the <name> folder", 10),
    ("the <name> repository", 15),
    ("on the <name> repository", 10),
    ("the <name> session", 10),
]

/// Stands for the name in a slot's sentence.
private let slotMark = "<name>"

/// Every agent and every name of this machine said in the sentences they come in, each phrase spelled
/// out with its own count, so a name's weight is the same however many other names there are.
/// The agents take their own sentences, and every other name the sentences about a place.
public func taughtNamePhrases(agents: [String] = taughtAgents, names: [String]) -> [TaughtPhrase] {
    let agentKeys = Set(agents.map { $0.lowercased() })
    let places = names.filter { !agentKeys.contains($0.lowercased()) }
    var seen = Set<String>()
    var taught: [TaughtPhrase] = []
    func teach(_ values: [String], in slots: [(String, Int)]) {
        for value in values {
            let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            for (sentence, count) in slots {
                let phrase = sentence.replacingOccurrences(of: slotMark, with: name)
                guard seen.insert(phrase.lowercased()).inserted else { continue }
                taught.append(TaughtPhrase(phrase, count))
            }
        }
    }
    teach(agents, in: agentSlot)
    teach(places, in: placeSlot)
    return taught
}

/// How the names nobody's dictionary has are said. The r coloured vowel is written "@r", the one
/// the recognizer reads; "3`" is standard X-SAMPA and it refused iTerm, Hermes and Cursor over it.
public let taughtPronunciations: [TaughtPronunciation] = [
    TaughtPronunciation("Claude", "k l O d"),
    // Stressed on its first half, as people say it, and with the open and the rounded "o" of nox,
    // so "mem knocks" and "mem nox" both land on Memnox rather than on "my Knox".
    TaughtPronunciation("Memnox", "m E m n A k s"),
    TaughtPronunciation("Memnox", "m \"E m . n A k s"),
    TaughtPronunciation("Memnox", "m \"E m . n O k s"),
    TaughtPronunciation("Memnox", "m \"E m . n Q k s"),
    TaughtPronunciation("Codex", "k o d E k s"),
    TaughtPronunciation("OpenClaw", "o p @ n k l O"),
    // Said as two words, which the recognizer otherwise hears as "an item" or "eye term".
    TaughtPronunciation("iTerm", "aI t @r m"),
    TaughtPronunciation("macOS", "m { k o E s"),
    // Heard as "gate" and "get" before push or status, and as "a mess" for Hermes.
    TaughtPronunciation("git", "g I t"),
    // Heard as "get up" after push.
    TaughtPronunciation("GitHub", "g I t h V b"),
    // Heard as "VS studio" and "videos studios".
    TaughtPronunciation("VS Code", "v i E s k o d"),
    TaughtPronunciation("Hermes", "h @r m i z"),
    TaughtPronunciation("Cursor", "k @r s @r"),
]
