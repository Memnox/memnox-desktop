import Foundation

/// One rule change as Rules' History lists it.
public struct RuleHistoryLine: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let caption: String
    public let outcome: String
    public let inForce: Bool
}

/// The words for Rules' History: what changed, who said so and when, and whether it holds.
public enum RuleHistoryLines {
    public static let title = "History"
    public static let empty = "No rule has changed on this computer yet. A rule you add or take out shows here once you answer it."

    public static func lines(_ rows: [RuleHistoryRow], now: Date) -> [RuleHistoryLine] {
        rows.map { row in
            let removed = row.kind == "removed"
            let confirmed = row.answer == "confirmed"
            let what = row.rules.joined(separator: " ")
            let title = removed ? "Take out \(what)" : what
            let who = row.answeredBy.map { "\(confirmed ? "Signed" : "Declined") by \($0)" } ?? (confirmed ? "Signed" : "Declined")
            let caption = [who, SessionText.ago(row.answeredAt, now: now)].compactMap { $0 }.joined(separator: ", ")
            let outcome = confirmed ? (removed ? "Taken out" : "In force") : "Left as it was"
            return RuleHistoryLine(id: row.id, title: title, caption: caption, outcome: outcome, inForce: confirmed && !removed)
        }
    }
}
