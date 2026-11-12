import Foundation

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
    public static let lead = "For each agent found here, from what Memnox has seen and proved so far."

    /// Said where the scan found no agent on this Mac yet.
    public static let nothingFound = "No agent is on this Mac yet. Install one and Memnox finds it and puts it under itself."

    /// The press that opens and closes every agent's levels, since the whole list buries the one thing to do next.
    public static let showDetails = "Show what each covers"
    public static let hideDetails = "Hide the details"

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

    /// "Commands, Files and Git", the way a sentence lists things.
    static func joined(_ things: [String]) -> String {
        guard let last = things.last else { return "" }
        let rest = things.dropLast()
        return rest.isEmpty ? last : "\(rest.joined(separator: ", ")) and \(last)"
    }
}
