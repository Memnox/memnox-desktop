import Foundation

/// The skills one agent already had in its own folder, as the Found on this computer list groups them.
public struct FoundSkillGroup: Equatable, Sendable {
    public let agent: String
    public let label: String
    public let skills: [FoundSkillView]
}

/// The Skills page's search and the Found on this computer list's words. One query narrows both the hub and what
/// agents already had, matched on what a person can see in each row and never on a score.
public enum SkillSearch {
    /// Rows a group shows before its Show all, so one agent with many skills does not bury the rest.
    public static let collapsedRows = 5

    /// The query as matched: trimmed, case and accents set aside, nil when nothing was typed.
    public static func words(_ query: String) -> [String]? {
        let words = query.split(whereSeparator: \.isWhitespace).map { fold(String($0)) }
        return words.isEmpty ? nil : words
    }

    /// Every word typed appears somewhere in the fields, so "higgs video" finds higgsfield-video-explainer.
    public static func matches(_ fields: [String], _ query: String) -> Bool {
        guard let words = words(query) else { return true }
        let haystack = fold(fields.joined(separator: " "))
        return words.allSatisfy { haystack.contains($0) }
    }

    /// The hub's skills a query keeps: by name, description, category and the agents each is given to.
    public static func hub(_ skills: [SkillView], _ query: String, label: (String) -> String) -> [SkillView] {
        skills.filter { skill in
            matches([skill.name, skill.description, skill.category ?? ""] + skill.agents.map(label) + skill.agents, query)
        }
    }

    /// What agents already had and is not in the hub yet, kept by a query on its name, agent, path and tools.
    public static func found(_ found: [FoundSkillView], _ query: String, label: (String) -> String) -> [FoundSkillView] {
        found.filter { !$0.imported && matches([$0.name, $0.agent, label($0.agent), $0.path] + $0.tools, query) }
    }

    /// The found skills by agent, agents in the order of their labels and each agent's skills by name.
    public static func grouped(_ found: [FoundSkillView], label: (String) -> String) -> [FoundSkillGroup] {
        Dictionary(grouping: found, by: \.agent)
            .map { agent, skills in FoundSkillGroup(agent: agent, label: label(agent), skills: skills.sorted { $0.name < $1.name }) }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    /// "12", or "3 of 12" while a search narrows the list.
    public static func counted(shown: Int, of total: Int, searching: Bool) -> String {
        searching && shown != total ? "\(shown) of \(total)" : "\(total)"
    }

    /// Said where a search leaves nothing in the hub.
    public static func noMatch(_ query: String) -> String {
        "No skills match \u{201C}\(query.trimmingCharacters(in: .whitespaces))\u{201D}"
    }

    /// What the empty search says next, pointing at the found list when it still holds matches.
    public static func noMatchDetail(foundMatching: Int) -> String {
        if foundMatching == 0 { return "Nothing in the hub or on this computer has that in its name, description or agent." }
        let some = foundMatching == 1 ? "1 skill an agent already has matches" : "\(foundMatching) skills agents already have match"
        return "Nothing in the hub has that yet, but \(some) below, ready to import."
    }

    /// "Import all 83", or "Import 9 shown" while a search narrows the list, so the press says what it takes.
    public static func importAllTitle(_ count: Int, searching: Bool) -> String {
        searching ? "Import \(count) shown" : "Import all \(count)"
    }

    /// "Importing 4 of 9" while an Import all runs.
    public static func importing(done: Int, of total: Int) -> String {
        "Importing \(done) of \(total)"
    }

    /// What an Import all came to, in one line.
    public static func imported(_ results: ImportResults) -> String {
        var parts: [String] = []
        if results.done > 0 { parts.append(results.done == 1 ? "1 skill is in the hub now." : "\(results.done) skills are in the hub now.") }
        if results.proposed > 0 {
            parts.append(results.proposed == 1 ? "1 waits for your signature on the island."
                : "\(results.proposed) wait for your signature on the island.")
        }
        if let first = results.failed.first {
            let more = results.failed.count - 1
            parts.append(more == 0 ? "1 did not import: \(first)" : "\(results.failed.count) did not import, and the first said: \(first)")
        }
        return parts.isEmpty ? "Nothing was imported." : parts.joined(separator: " ")
    }

    /// A path under the home folder written from ~, so the row reads the part that differs.
    public static func shortPath(_ path: String, home: String) -> String {
        let base = home.hasSuffix("/") ? String(home.dropLast()) : home
        guard !base.isEmpty, path == base || path.hasPrefix(base + "/") else { return path }
        return "~" + path.dropFirst(base.count)
    }

    /// What a found skill reaches in a few words, or nil where it declares nothing, which is said by saying nothing.
    public static func reach(_ found: FoundSkillView) -> String? {
        guard !found.tools.isEmpty else { return nil }
        return "Uses \(SkillsLines.listed(found.tools))"
    }

    /// Where its SKILL.md sits: the path itself when it names a markdown file, otherwise SKILL.md inside the folder.
    public static func instructionsFile(_ found: FoundSkillView) -> String {
        if found.path.lowercased().hasSuffix(".md") { return found.path }
        return (found.path.hasSuffix("/") ? found.path : found.path + "/") + skillFile
    }

    /// The file every agent folder keeps a skill's instructions in.
    public static let skillFile = "SKILL.md"

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

/// What an Import all came to, counted so one line says it.
public struct ImportResults: Equatable, Sendable {
    public var done = 0
    public var proposed = 0
    public var failed: [String] = []

    public init(done: Int = 0, proposed: Int = 0, failed: [String] = []) {
        self.done = done
        self.proposed = proposed
        self.failed = failed
    }
}
