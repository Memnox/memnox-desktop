import Foundation

// What a hub and a person wear on the brain. A source shows its maker's logo where one is known, the way the person
// knows the tool, and a person shows an avatar: their initials on a colour drawn from their name, the same on every
// launch. Nothing here fetches a picture; a logo is a slug the app already draws, and a person has no photo until the
// record carries one.

/// The logo a node wears: a tool's by its Composio slug, or an agent's by the kind its logo file is kept under.
public enum BrainBrand: Equatable, Sendable {
    case toolkit(String)
    case agent(String)
}

/// Who a person is on the brain, read off the lines the record joins them by.
public struct BrainProfile: Equatable, Sendable {
    /// What they said, what names them as owner or approver, and what they confirmed, by node id.
    public let said: [String]
    public let named: [String]
    public let confirmed: [String]
    /// The tools what they are linked to was read out of, by node id.
    public let sources: [String]
    /// Their address, where their name is one.
    public let email: String?
}

public enum BrainFaces {
    /// The words a source's name or place says its tool by, and the slug that tool's logo is drawn from.
    private static let toolkits: [(word: String, slug: String)] = [
        ("notion", "notion"), ("obsidian", "obsidian"), ("github", "github"), ("gitlab", "gitlab"), ("slack", "slack"),
        ("google drive", "googledrive"), ("googledrive", "googledrive"), ("gdrive", "googledrive"), ("linear", "linear"),
        ("gmail", "gmail"), ("jira", "jira"), ("confluence", "confluence"), ("figma", "figma"), ("discord", "discord"),
        ("supermemory", "supermemory"), ("dropbox", "dropbox"), ("airtable", "airtable"),
    ]
    /// The words an instruction file or a folder says its agent by, and the kind that agent's logo is kept under.
    private static let agents: [(word: String, kind: String)] = [
        ("claude", "claude"), ("agents.md", "codex"), ("codex", "codex"), ("cursor", "cursor"), ("gemini", "antigravity"),
        ("copilot", "copilot-cli"), ("opencode", "opencode"), ("cline", "cline"), ("hermes", "hermes"), ("openclaw", "openclaw"),
    ]
    /// How many letters an avatar's initials hold at the most.
    public static let mostInitials = 2

    /// The logo a source wears, by what kind of source it is and else by the words in its name and place; nil where
    /// none is known, so the hub keeps its glyph.
    public static func brand(kind: MemorySourceKind?, name: String, location: String?) -> BrainBrand? {
        switch kind {
        case .obsidian: return .toolkit("obsidian")
        case .notionExport: return .toolkit("notion")
        case .supermemory: return .toolkit("supermemory")
        case .markdown, .instructions, .mcp, nil: break
        }
        let words = [name, location ?? ""].joined(separator: " ").lowercased()
        if let tool = toolkits.first(where: { words.contains($0.word) }) { return .toolkit(tool.slug) }
        if let agent = agents.first(where: { words.contains($0.word) }) { return .agent(agent.kind) }
        return nil
    }

    /// A person's initials, the first letters of their first two words as the console letters an avatar, and an at
    /// sign for nobody named.
    public static func initials(_ name: String) -> String {
        let letters = name.split(whereSeparator: { $0.isWhitespace }).prefix(mostInitials).compactMap(\.first)
        return letters.isEmpty ? nobody : String(letters).uppercased()
    }

    /// Which of `count` colours a person's avatar is painted in, by the console's own 32 bit FNV hash of their name
    /// trimmed and lowered, so a person wears the same colour on the Mac and in the console.
    public static func colour(_ name: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        var hash = fnvBasis
        for unit in name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().utf16 {
            hash ^= UInt32(unit)
            hash = hash &* fnvPrime
        }
        return Int(hash % UInt32(count))
    }

    /// The colours the console's avatars are drawn in, so the Mac draws from as many.
    public static let avatarColours = 6
    private static let nobody = "@"
    private static let fnvBasis: UInt32 = 2_166_136_261
    private static let fnvPrime: UInt32 = 16_777_619

    /// A person's profile off the map: what they said, what names them and what they confirmed, each joined to them by
    /// its own kind of line, and every tool those were read out of.
    public static func profile(_ person: String, in map: MemoryMap, label: String) -> BrainProfile {
        var said: [String] = []
        var named: [String] = []
        var confirmed: [String] = []
        for edge in map.edges {
            if edge.kind == .said, edge.from == person { said.append(edge.to) }
            if edge.kind == .names, edge.to == person { named.append(edge.from) }
            if edge.kind == .confirmed, edge.from == person { confirmed.append(edge.to) }
        }
        let linked = Set(said + named + confirmed)
        var seen: Set<String> = []
        let sources = map.edges.filter { $0.kind == .pulledFrom && linked.contains($0.from) }.map(\.to).filter { seen.insert($0).inserted }
        let email = label.contains("@") && !label.contains(" ") ? label : nil
        return BrainProfile(said: said, named: named, confirmed: confirmed, sources: sources, email: email)
    }
}
