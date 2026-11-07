import Foundation

/// One ready-made rule as a card offers it: one of the console's library, or a rule a pack the runtime ships carries.
/// Nothing here decides anything, because adding one only raises a proposal the person signs on the island.
public struct ReadyRule: Equatable, Identifiable, Sendable {
    /// Where the rule's text comes from once it is added.
    public enum Origin: Equatable, Sendable {
        /// The console's library, written out as a table with whichever effect the person chose.
        case library(LibraryRule)
        /// A pack's rule: the pack's header and this rule's own `[[policies]]` table, imported whole.
        case pack(header: String, table: String)
    }

    /// The rule's name, which it keeps once in force.
    public let id: String
    public let title: String
    public let says: String
    public let actions: [String]
    /// The effect it ships with, offered first and marked suggested.
    public let effect: RuleEffect
    /// The products and kinds of act it is about; empty for a pack's rule, which a screen draws from its actions.
    public let marks: [RuleMark]
    public let origin: Origin
}

/// Ready-made rules under one heading: a library category, or one pack Memnox ships.
public struct ReadyRuleGroup: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let rules: [ReadyRule]
}

public enum ReadyRules {
    /// Allow, Ask and Deny, the three choices every card and dialog offers; an allow is proposed and signed like any other.
    public static let effects: [RuleEffect] = [.allow, .ask, .deny]

    private static let table = "[[policies]]"
    private static let matchTable = "[policies.match]"
    private static let decisionTable = "[policies.decision]"

    /// The library in category order, then every pack in the order the runtime lists them, each keeping only the rules
    /// the library does not already offer.
    public static func groups(_ packs: [RulePackView]) -> [ReadyRuleGroup] {
        let library = ReadyRuleCategory.allCases.map { category in
            ReadyRuleGroup(id: category.rawValue, title: category.title,
                           rules: ReadyRuleLibrary.rules.filter { $0.category == category }.map(rule))
        }
        let offered = Set(ReadyRuleLibrary.rules.map(\.id))
        let shipped = packs.map { pack in
            ReadyRuleGroup(id: pack.id, title: pack.name, rules: rules(of: pack).filter { !offered.contains($0.id) })
        }
        return (library + shipped).filter { !$0.rules.isEmpty }
    }

    /// The library rule as a card offers it.
    public static func rule(_ library: LibraryRule) -> ReadyRule {
        ReadyRule(id: library.id, title: library.title, says: library.says, actions: library.match.actions,
                  effect: library.recommended, marks: library.marks, origin: .library(library))
    }

    /// The runtime's first run set, the library's own rules in library order.
    public static var starter: [ReadyRule] {
        ReadyRuleLibrary.rules.filter { ReadyRuleLibrary.starterSet.contains($0.id) }.map(rule)
    }

    /// A pack's rules read from its TOML, each kept as text the runtime can import on its own.
    public static func rules(of pack: RulePackView) -> [ReadyRule] {
        let lines = pack.toml.components(separatedBy: "\n")
        let starts = lines.indices.filter { trimmed(lines[$0]) == table }
        guard let first = starts.first else { return [] }
        let header = lines[..<first].joined(separator: "\n")
        return starts.enumerated().compactMap { index, start in
            let end = index + 1 < starts.count ? starts[index + 1] : lines.count
            return rule(Array(lines[start..<end]), header: header)
        }
    }

    /// The groups a chip and a search leave, dropping any group with nothing left in it. Every word of the search has to
    /// appear in the title, the line under it, the group or an action, so typing `kubectl` finds the rule.
    public static func shown(_ groups: [ReadyRuleGroup], group: String?, query: String) -> [ReadyRuleGroup] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return groups.compactMap { each in
            guard group == nil || group == each.id else { return nil }
            let kept = words.isEmpty ? each.rules : each.rules.filter { matches($0, in: each, words) }
            return kept.isEmpty ? nil : ReadyRuleGroup(id: each.id, title: each.title, rules: kept)
        }
    }

    /// The rule in force this card stands for, by the name it keeps.
    public static func inForce(_ rule: ReadyRule, among rules: [PolicyRuleView]) -> PolicyRuleView? {
        rules.first { $0.name == rule.id }
    }

    /// The rule's table as it goes to the runtime with the effect the person chose.
    public static func table(_ rule: ReadyRule, effect: RuleEffect) -> String {
        switch rule.origin {
        case .library(let library):
            return RuleToml.text(libraryTable(library, effect: effect))
        case .pack(_, let table):
            return withEffect(table, effect)
        }
    }

    /// Several rules as one document to import, each still its own proposal signed on its own.
    public static func toml(_ picks: [(rule: ReadyRule, effect: RuleEffect)]) -> String? {
        guard !picks.isEmpty else { return nil }
        let header = picks.lazy.compactMap { pick -> String? in
            guard case .pack(let header, _) = pick.rule.origin else { return nil }
            return header
        }.first
        let tables = picks.map { table($0.rule, effect: $0.effect) }
        // A pack's header already opens with the version line, so it stands in for the plain one.
        guard let header else { return RuleToml.document(tables) }
        return ([header] + tables).joined(separator: "\n")
    }

    /// A library rule as the runtime reads it: the reason says who chose the effect, and only a refusal names a way round.
    public static func libraryTable(_ library: LibraryRule, effect: RuleEffect) -> RuleTable {
        RuleTable(name: library.id, description: library.title, match: library.match, effect: effect.rawValue,
                  reason: "\(chose(effect)): \(library.because)",
                  alternative: effect == .deny ? library.alternative : nil)
    }

    /// The opening of the reason an agent is told, by the effect somebody chose.
    private static func chose(_ effect: RuleEffect) -> String {
        switch effect {
        case .allow: "you chose to allow this"
        case .ask: "you chose to be asked about this"
        case .deny: "you chose to deny this"
        }
    }

    private static func rule(_ lines: [String], header: String) -> ReadyRule? {
        var section = ""
        var name: String?
        var description: String?
        var actions: [String] = []
        var effect: String?
        var reason: String?
        for line in lines {
            let text = trimmed(line)
            if text.hasPrefix("[") {
                section = text
                continue
            }
            switch (section, key(text) ?? "") {
            case (table, "name"): name = quoted(text).first
            case (table, "description"): description = quoted(text).first
            case (matchTable, "actions"): actions = quoted(text)
            case (decisionTable, "effect"): effect = quoted(text).first
            case (decisionTable, "reason"): reason = quoted(text).first
            default: break
            }
        }
        guard let name, let effect = effect.flatMap(RuleEffect.init(rawValue:)) else { return nil }
        let says = reason.map(sentence) ?? actions.joined(separator: ", ")
        return ReadyRule(id: name, title: description ?? name, says: says, actions: actions, effect: effect, marks: [],
                         origin: .pack(header: header, table: lines.joined(separator: "\n")))
    }

    /// The table with its decision's effect rewritten, every other line kept as the pack wrote it.
    private static func withEffect(_ table: String, _ effect: RuleEffect) -> String {
        var section = ""
        return table.components(separatedBy: "\n").map { line in
            let text = trimmed(line)
            if text.hasPrefix("[") { section = text }
            return section == decisionTable && key(text) == "effect" ? "effect = \"\(effect.rawValue)\"" : line
        }.joined(separator: "\n")
    }

    private static func matches(_ rule: ReadyRule, in group: ReadyRuleGroup, _ words: [String]) -> Bool {
        let text = ([rule.title, rule.says, group.title] + rule.actions).joined(separator: " ").lowercased()
        return words.allSatisfy { text.contains($0) }
    }

    /// The key of a `key = value` line, nil on any other line.
    private static func key(_ text: String) -> String? {
        guard let equals = text.firstIndex(of: "=") else { return nil }
        return trimmed(String(text[..<equals]))
    }

    /// Every double quoted string after the line's equals sign, which is all a pack's values are.
    private static func quoted(_ text: String) -> [String] {
        guard let equals = text.firstIndex(of: "=") else { return [] }
        let parts = text[text.index(after: equals)...].components(separatedBy: "\"")
        return stride(from: 1, to: parts.count, by: 2).map { parts[$0] }
    }

    /// A pack's reason is a clause, so a card says it as a sentence.
    private static func sentence(_ clause: String) -> String {
        guard let first = clause.first else { return clause }
        let body = first.uppercased() + clause.dropFirst()
        return body.hasSuffix(".") ? body : body + "."
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces)
    }
}
