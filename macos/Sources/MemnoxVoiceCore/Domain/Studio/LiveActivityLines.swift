import Foundation

/// Whether a live row belongs under a filter: shown at once, left out because the filter excludes it, or not knowable
/// from names alone, in which case it is counted for a refresh that reads it whole.
public enum LiveMatch: Equatable, Sendable {
    case shown
    case hidden
    case unknown
}

/// The rows the runtime sends as the ledger gains them, held against the filter a person looks through, as the Tauri
/// core's `live-activity.ts` holds them. A live row carries names only, so a filter it cannot be told against is never guessed.
public enum LiveActivityLines {
    /// The most live rows a list keeps above its first page; older ones are counted for a refresh rather than grown without end.
    public static let mostKept = 200

    /// The kind needs the surface a live row does not carry, so it is unknown; a search is told on the operation, the
    /// target and the agent, and a match on the rule's name alone waits for a refresh.
    public static func match(_ row: LiveActivityRow, _ filter: ActivityFilter) -> LiveMatch {
        if let effect = filter.effect, row.effect != effect { return .hidden }
        if let agent = filter.agent, row.agent != agent { return .hidden }
        if let since = filter.since, row.at < since { return .hidden }
        if let until = filter.until, row.at > until { return .hidden }
        let text = (filter.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !text.isEmpty, ![row.operation, row.target ?? "", row.agent].contains(where: { $0.lowercased().contains(text) }) {
            return .hidden
        }
        return filter.kind == nil ? .shown : .unknown
    }

    /// The pill over a list scrolled away from its top.
    public static func newRows(_ count: Int) -> String { "\(count) new" }

    /// Said under the live rows when some could not be carried or told against the filter.
    public static func missedRows(_ count: Int) -> String { "and \(count) more, refresh to see them" }
}
