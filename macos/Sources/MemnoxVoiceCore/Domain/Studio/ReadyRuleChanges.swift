import Foundation

/// One change waiting in the bar under the ready-made rules: the rule, what holds now, and the effect picked.
public struct ReadyRuleChange: Equatable, Identifiable, Sendable {
    public let rule: ReadyRule
    /// The effect in force now, nil while the rule is not added.
    public let from: RuleEffect?
    public let to: RuleEffect

    public var id: String { rule.id }

    public init(rule: ReadyRule, from: RuleEffect?, to: RuleEffect) {
        self.rule = rule
        self.from = from
        self.to = to
    }
}

/// What a ready-made card shows and what the bar under the cards gathers. Nothing here decides anything, because every
/// change is still proposed to the runtime and signed on the island.
public enum ReadyRuleChanges {
    /// The word a card's badge says while the rule is not in force.
    public static let notAdded = ProtectionLines.notAdded
    /// The marker on the effect the rule ships with.
    public static let suggested = ProtectionLines.suggested

    /// The effect the rule holds with now, nil while it is not in force or holds with a word this app does not know.
    public static func current(_ rule: ReadyRule, among rules: [PolicyRuleView]) -> RuleEffect? {
        ReadyRules.inForce(rule, among: rules)?.ruleEffect
    }

    /// The card's coloured badge: In force as its effect, as the console's card says it, or Not added in grey.
    public static func badge(_ rule: ReadyRule, among rules: [PolicyRuleView]) -> (word: String, tone: StudioTone) {
        guard let live = ReadyRules.inForce(rule, among: rules) else { return (notAdded, .quiet) }
        let word = live.ruleEffect.map(ProtectionLines.inForceAs) ?? StudioLines.title(live.effect)
        return (word, StudioLines.tone(live.effect))
    }

    /// Whether the card's control can change it: a rule not added yet, or one a person added on this machine. A rule
    /// from a file or the workspace is changed where it came from.
    public static func canChange(_ rule: ReadyRule, among rules: [PolicyRuleView]) -> Bool {
        ReadyRules.inForce(rule, among: rules)?.editable ?? true
    }

    /// The picks that change something, in the order the rules are listed; a pick equal to what holds is dropped.
    public static func changes(_ picked: [String: RuleEffect], rules: [ReadyRule],
                               among inForce: [PolicyRuleView]) -> [ReadyRuleChange] {
        var seen = Set<String>()
        return rules.compactMap { rule in
            guard seen.insert(rule.id).inserted, let to = picked[rule.id], canChange(rule, among: inForce) else { return nil }
            let from = current(rule, among: inForce)
            return from == to ? nil : ReadyRuleChange(rule: rule, from: from, to: to)
        }
    }

    /// The picks with every rule given not added yet set to its suggested effect, as Add all and the starter set do.
    public static func picking(_ rules: [ReadyRule], into picked: [String: RuleEffect],
                               among inForce: [PolicyRuleView]) -> [String: RuleEffect] {
        var next = picked
        for rule in rules where ReadyRules.inForce(rule, among: inForce) == nil && next[rule.id] == nil {
            next[rule.id] = rule.effect
        }
        return next
    }

    /// Every rule of the groups once, in their order, for a grid that draws no headings.
    public static func flat(_ groups: [ReadyRuleGroup]) -> [ReadyRule] {
        var seen = Set<String>()
        return groups.flatMap(\.rules).filter { seen.insert($0.id).inserted }
    }

    /// "1 change", "3 changes", the bar's count.
    public static func countLine(_ count: Int) -> String {
        count == 1 ? "1 change" : "\(count) changes"
    }

    /// "12 of 48", beside the search.
    public static func shownLine(_ shown: Int, of total: Int) -> String {
        "\(shown) of \(total)"
    }

    /// "Not added to Ask", "Ask to Deny", one change as the review lists it.
    public static func changeLine(_ change: ReadyRuleChange) -> String {
        let from = change.from.map { StudioLines.words($0).title } ?? notAdded
        return "\(from) to \(StudioLines.words(change.to).title)"
    }

    /// The rules in force a change takes out first, by name, since a changed effect is the old rule gone and the new
    /// one proposed.
    public static func removals(_ changes: [ReadyRuleChange]) -> [String] {
        changes.filter { $0.from != nil }.map(\.rule.id)
    }

    /// Every change as one document to import, each rule still its own proposal signed on its own.
    public static func toml(_ changes: [ReadyRuleChange]) -> String? {
        ReadyRules.toml(changes.map { ($0.rule, $0.to) })
    }
}
