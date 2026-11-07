import Foundation

/// One `[policies.match.arguments]` line: an argument's name and the values it matches.
public struct RuleArgument: Equatable, Sendable {
    public let name: String
    public let values: [String]

    public init(_ name: String, _ values: [String]) {
        self.name = name
        self.values = values
    }
}

/// What a refused agent is told it may do instead, which only a deny carries.
public struct RuleAlternative: Equatable, Sendable {
    public let action: String
    public let note: String

    public init(action: String, note: String) {
        self.action = action
        self.note = note
    }
}

/// A rule's `[policies.match]` table: the actions, then every list that narrows them, absent where it narrows nothing.
public struct RuleMatchTable: Equatable, Sendable {
    public var actions: [String]
    public var agents: [String]?
    public var targets: [String]?
    public var environments: [String]?
    public var classes: [String]?
    public var capabilities: [String]?
    public var dataClassifications: [String]?
    public var workingDirectories: [String]?
    public var branches: [String]?
    public var arguments: [RuleArgument]

    public init(actions: [String], agents: [String]? = nil, targets: [String]? = nil, environments: [String]? = nil,
                classes: [String]? = nil, capabilities: [String]? = nil, dataClassifications: [String]? = nil,
                workingDirectories: [String]? = nil, branches: [String]? = nil, arguments: [RuleArgument] = []) {
        self.actions = actions
        self.agents = agents
        self.targets = targets
        self.environments = environments
        self.classes = classes
        self.capabilities = capabilities
        self.dataClassifications = dataClassifications
        self.workingDirectories = workingDirectories
        self.branches = branches
        self.arguments = arguments
    }

    /// The narrowing lists in the order the runtime writes them, each under its own key.
    var lists: [(String, [String]?)] {
        [("agents", agents), ("targets", targets), ("environments", environments), ("classes", classes),
         ("capabilities", capabilities), ("dataClassifications", dataClassifications),
         ("workingDirectories", workingDirectories), ("branches", branches)]
    }
}

/// One rule as `memnox.policies.toml` holds it, so a preview is what somebody would find in their own file.
public struct RuleTable: Equatable, Sendable {
    public let name: String
    public var description: String?
    public let match: RuleMatchTable
    public let effect: String
    public var reason: String?
    public var alternative: RuleAlternative?

    public init(name: String, description: String? = nil, match: RuleMatchTable, effect: String, reason: String? = nil,
                alternative: RuleAlternative? = nil) {
        self.name = name
        self.description = description
        self.match = match
        self.effect = effect
        self.reason = reason
        self.alternative = alternative
    }
}

/// Rules written out in the runtime's own table shape, and the vocabularies a rule's fields may name.
public enum RuleToml {
    /// The file a person keeps this machine's rules in, named over every preview so the shape is recognisable.
    public static let file = "memnox.policies.toml"
    /// The line every rules document starts with, which the runtime refuses a document without.
    public static let header = "version = 1"

    /// What a rule's `dataClassifications` can name, the runtime's own vocabulary in its order.
    public static let dataClassifications = [
        "sensitive", "secret", "financial", "health", "government-id",
        "personal-data", "customer-record", "confidential", "source-code", "bulk-records",
    ]

    /// The classes the runtime compares a call's class with, the only ones a rule may name.
    public static let actionClasses = ["read", "write", "destructive", "communication", "unknown"]

    /// Stands in the preview until somebody names an action.
    static let actionPlaceholder = "<action>"
    /// A rule's name before an action gives it words.
    private static let fallbackName = "rule"

    /// The rule as TOML, tables in the runtime's order with a blank line between them.
    public static func text(_ table: RuleTable) -> String {
        var lines = ["[[policies]]", "name = \(quoted(table.name))"]
        if let description = table.description { lines.append("description = \(quoted(description))") }
        lines += ["", "[policies.match]", "actions = \(list(table.match.actions))"]
        for (key, values) in table.match.lists {
            if let values { lines.append("\(key) = \(list(values))") }
        }
        if !table.match.arguments.isEmpty {
            lines += ["", "[policies.match.arguments]"] + table.match.arguments.map { "\($0.name) = \(list($0.values))" }
        }
        lines += ["", "[policies.decision]", "effect = \(quoted(table.effect))"]
        if let reason = table.reason { lines.append("reason = \(quoted(reason))") }
        if let alternative = table.alternative {
            lines += ["", "[policies.decision.alternative]", "action = \(quoted(alternative.action))",
                      "note = \(quoted(alternative.note))"]
        }
        return lines.joined(separator: "\n")
    }

    /// Several rules as one document the runtime imports, each still proposed and signed on its own.
    public static func document(_ tables: [String], header: String = header) -> String {
        ([header] + tables).joined(separator: "\n\n")
    }

    /// A rule in force written back out, from the fields the runtime reports for it.
    public static func table(of rule: PolicyRuleView) -> RuleTable {
        let match = rule.match
        return RuleTable(name: rule.name,
                         match: RuleMatchTable(actions: match.actions, agents: match.agents, targets: match.targets,
                                               classes: match.classes, workingDirectories: match.workingDirectories,
                                               branches: match.branches),
                         effect: rule.effect, reason: rule.reason)
    }

    /// A rule being written in the propose dialog, with the data it carries that a draft alone cannot say.
    public static func table(of draft: RuleDraftInput, dataClassifications: [String]?) -> RuleTable {
        let action = draft.action.isEmpty ? actionPlaceholder : draft.action
        return RuleTable(name: name(effect: draft.effect, action: draft.action),
                         match: RuleMatchTable(actions: [action], agents: draft.agents, targets: draft.targets,
                                               classes: draft.classes, dataClassifications: dataClassifications,
                                               workingDirectories: draft.workingDirectories, branches: draft.branches),
                         effect: draft.effect, reason: draft.reason)
    }

    /// A rule's name as the runtime keys it: the action's words lowercased and joined by hyphens, then the effect.
    public static func name(effect: String, action: String) -> String {
        let words = action.lowercased().split { !($0.isLetter || $0.isNumber) }.joined(separator: "-")
        return "\(words.isEmpty ? fallbackName : words)-\(effect)"
    }

    /// A comma separated field as the list it names, nil when it names nothing.
    public static func words(_ text: String) -> [String]? {
        let words = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return words.isEmpty ? nil : words
    }

    /// The field with one word added or taken away, so a chip and typing edit the same text.
    public static func toggled(_ word: String, in text: String) -> String {
        let chosen = words(text) ?? []
        let next = chosen.contains(word) ? chosen.filter { $0 != word } : chosen + [word]
        return next.joined(separator: ", ")
    }

    /// A TOML basic string, escaped the way JSON escapes, which TOML reads the same.
    static func quoted(_ text: String) -> String {
        var escaped = ""
        for character in text {
            switch character {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n": escaped += "\\n"
            case "\t": escaped += "\\t"
            default: escaped.append(character)
            }
        }
        return "\"\(escaped)\""
    }

    private static func list(_ values: [String]) -> String {
        "[ \(values.map(quoted).joined(separator: ", ")) ]"
    }
}
