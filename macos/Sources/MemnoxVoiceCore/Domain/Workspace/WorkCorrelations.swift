import Foundation

// Which issue a session concerns, as the workspace matched it: exactly, against what a connected tracker delivered,
// and never by resemblance. Read from `GET v1/workspaces/:ws/work-correlations`; mirrors the Tauri core's
// `work-correlations.ts` and the console's `lib/work-correlations.ts`, so a session reads the same on all three.

/// The tracker item a correlation links to, sent only for one the reader may see.
public struct WorkCorrelationItem: Decodable, Equatable, Sendable {
    public let provider: String
    public let label: String
    public let url: String
}

/// One match between a session and an issue, as the workspace keeps it.
public struct WorkCorrelation: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let sessionId: String
    public let source: String
    public let state: String
    public let lateMatch: Bool
    public let claim: String?
    public let matches: Int?
    public let visible: Bool
    public let item: WorkCorrelationItem?

    public init(id: String, sessionId: String, source: String, state: String, lateMatch: Bool = false, claim: String? = nil,
                matches: Int? = nil, visible: Bool = false, item: WorkCorrelationItem? = nil) {
        self.id = id
        self.sessionId = sessionId
        self.source = source
        self.state = state
        self.lateMatch = lateMatch
        self.claim = claim
        self.matches = matches
        self.visible = visible
        self.item = item
    }

    private enum CodingKeys: String, CodingKey {
        case id, sessionId, source, state, lateMatch, claim, matches, visible, item
    }

    /// The four fields that name a match are required; every other one falls back, so an older cloud still reads.
    public init(from decoder: Decoder) throws {
        let row = try decoder.container(keyedBy: CodingKeys.self)
        id = try row.decode(String.self, forKey: .id)
        sessionId = try row.decode(String.self, forKey: .sessionId)
        source = try row.decode(String.self, forKey: .source)
        state = try row.decode(String.self, forKey: .state)
        lateMatch = (try? row.decode(Bool.self, forKey: .lateMatch)) ?? false
        claim = try? row.decode(String.self, forKey: .claim)
        matches = try? row.decode(Int.self, forKey: .matches)
        visible = (try? row.decode(Bool.self, forKey: .visible)) ?? false
        item = try? row.decode(WorkCorrelationItem.self, forKey: .item)
    }
}

/// The cloud's answer, each row read on its own so one it cannot read never hides the rest.
public struct WorkCorrelations: Decodable, Equatable, Sendable {
    public let correlations: [WorkCorrelation]

    private enum CodingKeys: String, CodingKey {
        case correlations
    }

    private struct Lossy: Decodable {
        let row: WorkCorrelation?

        init(from decoder: Decoder) throws {
            row = try? WorkCorrelation(from: decoder)
        }
    }

    public init(from decoder: Decoder) throws {
        let body = try? decoder.container(keyedBy: CodingKeys.self)
        correlations = ((try? body?.decode([Lossy].self, forKey: .correlations)) ?? []).compactMap(\.row)
    }
}

/// The states a correlation is shown in; one a newer claim replaced or a person removed is none of them.
public enum WorkCorrelationState: String, Sendable {
    case linked
    case ambiguous
    case pending
    case expired
    case unverifiable
}

/// The three things a person is told; a session that named no issue shows nothing at all.
public enum WorkShown: Equatable, Sendable {
    case linked
    case unverified
    case ambiguous
}

/// What a link rests on, in the word a person would use for it.
public enum WorkCorrelationSource: String, Sendable {
    case assignment
    case providerLink = "provider_link"
    case handoff
    case sdk
    case automation
    case mcpTarget = "mcp_target"
    case branch
    case commit
    case prompt

    public var word: String {
        switch self {
        case .assignment: "assignment"
        case .providerLink: "pull request"
        case .handoff: "handoff"
        case .sdk: "SDK"
        case .automation: "automation"
        case .mcpTarget: "MCP"
        case .branch: "branch"
        case .commit: "commit"
        case .prompt: "prompt"
        }
    }
}

/// The words a session says about its issue, the same as the console's and the Tauri core's.
public enum WorkCorrelationLines {
    public static let heading = "Issue"
    public static let hidden = "An item you cannot see"
    public static let lateMatch = "A matching item arrived later. Confirm it in the console."
    public static let explain = "Memnox reads the issue key in the branch, commits or agent, and links it only when exactly one connected tracker has that issue. A link is not an assignment."

    /// What a claim reads as when the cloud sent none, and how many trackers an ambiguous one names when it sent no count.
    private static let noClaim = "A claim"
    private static let fewestAmbiguous = 2

    public static func via(_ source: String) -> String {
        "Linked via \(WorkCorrelationSource(rawValue: source)?.word ?? source)"
    }

    public static func unverified(_ claim: String) -> String { "\(claim), not verified" }

    public static func ambiguous(_ claim: String, matches: Int) -> String { "\(claim) matches \(matches) trackers, not linked" }

    /// What a correlation shows as, or nothing for one a newer claim replaced or a person removed.
    public static func shown(_ correlation: WorkCorrelation) -> WorkShown? {
        guard let state = WorkCorrelationState(rawValue: correlation.state) else { return nil }
        switch state {
        case .linked: return .linked
        case .ambiguous: return .ambiguous
        case .pending, .expired, .unverifiable: return .unverified
        }
    }

    /// The item a person may open: a link they are allowed to see, with an address that reads as one.
    public static func link(_ correlation: WorkCorrelation) -> URL? {
        guard shown(correlation) == .linked, correlation.visible, let item = correlation.item else { return nil }
        return URL(string: item.url)
    }

    /// The one line a session shows for a correlation.
    public static func label(_ correlation: WorkCorrelation) -> String {
        let claim = correlation.claim ?? noClaim
        switch shown(correlation) {
        case .linked:
            guard correlation.visible, let item = correlation.item else { return hidden }
            return item.label
        case .ambiguous:
            return ambiguous(claim, matches: correlation.matches ?? fewestAmbiguous)
        case .unverified, nil:
            return unverified(claim)
        }
    }

    /// Why it reads as it does: what a link rests on, or why a claim is not linked.
    public static func reason(_ correlation: WorkCorrelation) -> String? {
        switch shown(correlation) {
        case .linked:
            return via(correlation.source)
        case .unverified:
            if correlation.lateMatch { return lateMatch }
            switch WorkCorrelationState(rawValue: correlation.state) {
            case .pending: return "Waiting for the tracker to deliver it."
            case .expired: return "No tracker delivered it within a day."
            case .unverifiable: return "Its tracker is no longer connected."
            case .linked, .ambiguous, nil: return nil
            }
        case .ambiguous, nil:
            return nil
        }
    }

    /// The ones a session shows, one per claim, replaced and removed left out.
    public static func forSession(_ all: [WorkCorrelation], _ sessionId: String) -> [WorkCorrelation] {
        var kept: [WorkCorrelation] = []
        for each in all where each.sessionId == sessionId && shown(each) != nil {
            if !kept.contains(where: { $0.claim != nil && $0.claim == each.claim }) { kept.append(each) }
        }
        return kept
    }

    /// The sessions as the cloud is asked for them: sorted, so the same sessions always ask the same question.
    public static func asked(_ sessionIds: [String]) -> String {
        sessionIds.sorted().joined(separator: ",")
    }
}
