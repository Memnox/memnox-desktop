import Foundation

/// The two views of Needs you: what waits on the person now, and what they already decided today, so a person who
/// answered on the island or the phone can see what they said yes and no to without opening Activity.
public enum NeedsYouView: String, CaseIterable, Sendable {
    case waiting
    case decided

    public var title: String {
        switch self {
        case .waiting: "Waiting for you"
        case .decided: "Decided today"
        }
    }
}

/// One answer the person gave today, said the way they would tell it.
public struct DecidedLine: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let caption: String
    public let outcome: String
    public let allowed: Bool
}

public enum NeedsYouLines {
    public static let noneDecided = "Nothing was decided today."
    public static let noneDecidedDetail = "What you allow or stop on the island or your phone shows here for the rest of the day."

    /// Today's rows a person answered, newest first as the record reads them.
    public static func decided(_ rows: [ActivityRow]) -> [DecidedLine] {
        rows.compactMap { row in
            guard let answered = StudioLines.answeredWords(by: row.answeredBy, how: row.answeredHow) else { return nil }
            let allowed = row.effect == RuleEffect.allow.rawValue
            return DecidedLine(id: row.id, title: ActivityWords.line(operation: row.operation, target: row.target),
                               caption: [row.agentName, answered].joined(separator: " · "),
                               outcome: outcome(row.effect), allowed: allowed)
        }
    }

    private static func outcome(_ effect: String) -> String {
        switch RuleEffect(rawValue: effect) {
        case .allow: "Let go ahead"
        case .deny: "Stopped"
        case .ask, nil: "Answered"
        }
    }
}
