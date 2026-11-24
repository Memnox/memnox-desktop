import Foundation

/// How careful agents are inside one project, read off the rules that hold there: none of its own is Relaxed, the safe
/// defaults started here is Careful, and the read-only pack started here is Strict. Each piece of work gets its own care,
/// so a website can stay relaxed while invoicing waits for every change.
public enum ProjectCare: String, CaseIterable, Sendable {
    case relaxed
    case careful
    case strict

    public var label: String {
        switch self {
        case .relaxed: "Relaxed"
        case .careful: "Careful"
        case .strict: "Strict"
        }
    }

    public var line: String {
        switch self {
        case .relaxed: "Agents here follow your general rules and nothing more."
        case .careful: "Agents here wait for you before they delete, publish or change somebody else's system."
        case .strict: "Agents here wait for you before they change anything."
        }
    }

    /// The level of care it starts, which names the shipped pack proposed for this project; Relaxed proposes nothing.
    public var level: CareLevel? {
        switch self {
        case .relaxed: nil
        case .careful: .ask
        case .strict: .strict
        }
    }

    /// The pack a rule came from, read off the name the runtime gives every rule it imports from one.
    private static let packPrefix = "pack-"

    /// The strictest pack started here wins, since one strict rule set is what a person would want named.
    public static func of(rulesHere: [PolicyRuleView]) -> ProjectCare {
        let names = rulesHere.map(\.name)
        func started(_ care: ProjectCare) -> Bool {
            guard let pack = care.level?.packId else { return false }
            return names.contains { $0.hasPrefix("\(packPrefix)\(pack)-") }
        }
        if started(.strict) { return .strict }
        if started(.careful) { return .careful }
        return .relaxed
    }
}

/// A project shown before any exists, so the value of keeping work apart is seen before a folder is chosen.
public struct ProjectExample: Equatable, Identifiable, Sendable {
    public let name: String
    public let care: ProjectCare
    public let line: String

    public var id: String { name }

    public init(name: String, care: ProjectCare, line: String) {
        self.name = name
        self.care = care
        self.line = line
    }

    /// Three kinds of work anybody recognises, each needing a different amount of care.
    public static let all: [ProjectExample] = [
        ProjectExample(name: "Website", care: .relaxed, line: "Agents fix copy and pages freely."),
        ProjectExample(name: "Support inbox", care: .careful, line: "Agents draft replies and wait for you before anything is sent."),
        ProjectExample(name: "Invoicing", care: .strict, line: "Every change waits for you."),
    ]

    public static let startTitle = "Start like this"
}

/// Why a project is worth having, said on the empty Projects page in words anybody uses.
public enum ProjectWhy {
    public static let title = "Keep each piece of work apart"
    /// What a project is, said before why, so nobody reads it as only a folder of code.
    public static let lead = "A project is one piece of work your agents help with, such as your website, invoicing or the support inbox."
    public static let lines = [
        "Its own care: the website stays relaxed while invoicing waits for you.",
        "Its own memory: agents there already know what was decided, so you stop repeating yourself.",
        "Its own story: ask what happened in invoicing this week, not in everything at once.",
        "Its own people: see who is on what, and catch two agents changing the same thing.",
    ]
    public static let examplesTitle = "Start from an example"
    public static let chooseLine = "Choose the folder this work lives in. You can change how careful it is any time."
}
