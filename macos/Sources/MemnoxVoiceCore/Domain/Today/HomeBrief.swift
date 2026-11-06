import Foundation

/// The blocks Home reads top to bottom below the greeting, named and ordered as the console's home brief, so a person
/// moving between the two reads the same answer in the same words.
public enum HomeBriefBlock: String, CaseIterable, Sendable {
    case waiting
    case working
    case today
    case ready
    case notCovered

    public var title: String {
        switch self {
        case .waiting: "Waiting on you"
        case .working: "Working now"
        case .today: "Today"
        case .ready: "Ready to hand over"
        case .notCovered: "Not covered"
        }
    }

    /// What the block says while it holds nothing, so an empty block still says where things stand.
    public var none: String {
        switch self {
        case .waiting: "Nothing is waiting on you."
        case .working: "No agent is working right now."
        case .today: "Nothing was recorded today."
        case .ready: "Nothing yet. This fills in once you approve the same action a few times."
        case .notCovered: "Every agent on this Mac is under Memnox."
        }
    }
}

/// Today's items laid into Home's blocks, read off the same sources Today reads, so nothing is counted twice.
public enum HomeBrief {
    /// Not covered is left off for now, so Home stays straightforward; its items still reach Today's own list.
    public static let shown: [HomeBriefBlock] = HomeBriefBlock.allCases.filter { $0 != .notCovered }

    /// Every block shown in the console's order, an empty one kept so it can say so.
    public static func blocks(_ sources: TodaySources, now: Date,
                              calendar: Calendar = .current) -> [(block: HomeBriefBlock, items: [TodayItem])] {
        let overview = TodayBoard.overview(sources, now: now, calendar: calendar)
        let done = TodayBoard.done(sources.activity, now: now, calendar: calendar)
        return shown.map { block in
            switch block {
            // What only the person can do waits on them as much as a held call does.
            case .waiting: (block, overview.filter { $0.section == .needsYou || $0.kind == .owed })
            case .working: (block, overview.filter { $0.kind == .working })
            case .today: (block, done)
            case .ready: (block, overview.filter { $0.kind == .handOver })
            case .notCovered: (block, overview.filter { $0.kind == .unprotected })
            }
        }
    }

    /// The items in the order the blocks draw them, which is the order Up and Down step through.
    public static func items(_ blocks: [(block: HomeBriefBlock, items: [TodayItem])]) -> [TodayItem] {
        blocks.flatMap(\.items)
    }
}
