import Foundation

/// Where the person's agent runs, the answer to the first run's second question: one of the six agent categories, or
/// none yet. It only picks what the first run shows and says; it never decides what Memnox may do.
public enum AgentPlace: String, CaseIterable, Identifiable, Sendable {
    case thisMacCoding
    case thisMacApp
    case hosted
    case insideApp
    case noCode
    case ownCode
    case noneYet

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .thisMacCoding: "On this Mac, for code"
        case .thisMacApp: "On this Mac, as an app"
        case .hosted: "Hosted somewhere"
        case .insideApp: "Inside an app you use"
        case .noCode: "Built in a no code tool"
        case .ownCode: "Your own code"
        case .noneYet: "I do not have one yet"
        }
    }

    /// Examples a person recognises, so the right answer is found without knowing the category's name.
    public var detail: String {
        switch self {
        case .thisMacCoding: "Claude Code, Codex, Cursor, Gemini CLI or Windsurf."
        case .thisMacApp: "Claude Desktop, Hermes or OpenClaw."
        case .hosted: "Your agent on a server or in a cloud function."
        case .insideApp: "An agent built into a product you use, such as a helpdesk or a CRM."
        case .noCode: "n8n, Zapier, Copilot Studio or a builder like them."
        case .ownCode: "An agent you write yourself, in TypeScript or Python."
        case .noneYet: "Start from a job, and connect an agent whenever you have one."
        }
    }

    /// Found and put under Memnox by the service on this Mac, with nothing for the person to do.
    public var isLocal: Bool { self == .thisMacCoding || self == .thisMacApp }

    /// Reached through Memnox Cloud, which this Mac's service cannot reach on its own.
    public var throughCloud: Bool { !isLocal && self != .noneYet }

    /// How the agent reaches Memnox, in a line.
    public var connects: String {
        switch self {
        case .thisMacCoding: "Memnox hooks into it on this Mac by itself."
        case .thisMacApp: "Memnox runs its tools through itself on this Mac, by itself."
        case .hosted: "Through the Memnox guard in its code, or the Memnox gateway."
        case .insideApp: "Through an MCP address and a token, which the app calls."
        case .noCode: "Through an MCP address, added in the builder's own steps."
        case .ownCode: "Through the Memnox guard, installed from its SDK."
        case .noneYet: "Nothing yet. Connect an agent whenever you are ready."
        }
    }

    /// What a connection of this kind usually comes to once it reports, as the runtime's mediation table words it.
    /// Nil for this Mac, whose levels the service states for each agent, and for no agent at all. Only a proof the
    /// service or the cloud holds ever shows more.
    public var expected: CapabilityLevel? {
        switch self {
        case .hosted, .ownCode: .mediated
        case .insideApp, .noCode: .advisory
        case .thisMacCoding, .thisMacApp, .noneYet: nil
        }
    }

    /// The answer already likely when the scan found agents here, so pressing Continue is the sensible thing.
    public static func suggested(foundHere: Int) -> AgentPlace? {
        foundHere > 0 ? .thisMacCoding : nil
    }
}

/// The first run's two questions and their words, asked one at a time after the scan.
public enum FirstRunQuestions {
    public static let jobTitle = "What do you want your AI to help with?"
    public static let jobDetail = "Pick the closest. Memnox keeps it as a job your agent works under. Nothing is applied, and you can change it later."
    public static let placeTitle = "Where does your agent run?"
    public static let placeDetail = "Pick where the one you use most lives. You can add the others later under AI agents."

    /// Said where the runtime offers no jobs to start from, so the step never stands empty.
    public static let noJobs = "This Memnox service has no jobs to start from yet. You can write one later under AI agents."

    /// The button that leaves the question unanswered, which is always allowed.
    public static let skip = "Skip for now"

    /// What happens to the job once the place is known: bound to a found agent, or kept with nothing behind it.
    public static func jobLine(job: String?, boundTo agent: String?) -> String? {
        guard let job else { return nil }
        if let agent { return "\(job) now works through \(agent)." }
        return "\(job) has \(AgentProfileLines.noAgent.lowercased()). Connect one whenever you are ready, under AI agents."
    }

    /// What reaching an agent through Memnox Cloud asks of the person: nothing now, since signing in is optional.
    public static let cloudOptional = "This kind of agent reaches Memnox through Memnox Cloud. Signing in is optional, and everything on this Mac works without it."

    /// Said where the person chose this Mac and the scan found nothing yet.
    public static let nothingFound = "No agent is on this Mac yet. Install one and Memnox finds it and puts it under itself."
}

/// One line of the closing card: a level in plain words and the things an agent does that sit at it.
public struct CoverageLine: Equatable, Identifiable, Sendable {
    public let level: CapabilityLevel
    public let things: [String]

    public var id: String { level.rawValue }
    public var plain: String { CapabilityLevelLines.plain(level) }
    /// "Memnox stops this: Commands, Files and Git."
    public var sentence: String { "\(plain): \(FirstRunCoverage.joined(things))." }
}

/// What Memnox can and cannot do, said at the end of the first run in the five plain levels. Every level shown is one
/// the service or the cloud stated; nothing here works one out, so the card can only say less than it was told.
public enum FirstRunCoverage {
    public static let title = "What Memnox can and cannot do"
    public static let lead = "In plain words, for each agent, from what Memnox has seen and proved so far."

    /// Said once, under every agent, so nobody reads the card as more than it is.
    public static let cannot = "Memnox cannot see or stop anything an agent does outside the connections above, and it never acts on its own."

    /// The levels strongest first, so the card opens on what is held.
    private static let strongestFirst: [CapabilityLevel] = [.enforced, .mediated, .advisory, .observed, .noEvidence]

    /// The agent's capabilities and seams grouped by level, strongest first, a level with nothing at it left out.
    public static func lines(_ levels: CapabilityLevels) -> [CoverageLine] {
        let rows = CapabilityLevelLines.rows(levels) + CapabilityLevelLines.seamRows(levels)
        return strongestFirst.compactMap { level in
            let things = rows.filter { $0.level == level }.map(\.title)
            return things.isEmpty ? nil : CoverageLine(level: level, things: things)
        }
    }

    /// The line for an agent the person said runs elsewhere, until a connection of its own reports.
    public static func place(_ place: AgentPlace) -> String {
        guard let expected = place.expected else { return place.connects }
        return "Outside Memnox until it is connected. Connected this way, expect: \(CapabilityLevelLines.plain(expected))."
    }

    /// The line for a job with no agent behind it, which shows no level since nothing does the job.
    public static func job(_ name: String) -> String {
        "\(name) has \(AgentProfileLines.noAgent.lowercased()), so there is nothing for Memnox to stop or see yet."
    }

    /// "Commands, Files and Git", the way a sentence lists things.
    static func joined(_ things: [String]) -> String {
        guard let last = things.last else { return "" }
        let rest = things.dropLast()
        return rest.isEmpty ? last : "\(rest.joined(separator: ", ")) and \(last)"
    }
}
