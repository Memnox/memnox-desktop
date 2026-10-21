import Foundation

/// What the person has dictated, all told: words, how fast, and the days they did, kept apart from the history since that
/// holds only the latest fifty and a total read from it would quietly stop counting.
public struct DictationTally: Codable, Equatable, Sendable {
    public private(set) var words = 0
    /// Words and seconds from dictations that kept their length, so words a minute is never taken over untimed ones.
    public private(set) var timedWords = 0
    public private(set) var timedSeconds = 0.0
    /// The days a dictation went in, as the person's own calendar dates, oldest first.
    public private(set) var days: [String] = []

    /// More than a year, enough for any streak anybody keeps.
    static let keptDays = 400
    /// Under this much speech a speed would be a guess from a sentence or two.
    static let timedEnough = 20.0

    public init() {}

    /// The history as it stands, for a Mac that dictated before the tally was kept.
    public init(_ entries: [DictationEntry], calendar: Calendar = .current) {
        for entry in entries.reversed() { add(entry, calendar: calendar) }
    }

    public mutating func add(_ entry: DictationEntry, calendar: Calendar = .current) {
        words += entry.words
        if let seconds = entry.seconds, seconds > 0 {
            timedWords += entry.words
            timedSeconds += seconds
        }
        let day = Self.day(entry.at, calendar)
        if days.last != day, !days.contains(day) {
            days.append(day)
            days.sort()
            if days.count > Self.keptDays { days.removeFirst(days.count - Self.keptDays) }
        }
    }

    /// Nil until there is enough timed speech to say.
    public var wordsPerMinute: Int? {
        guard timedSeconds >= Self.timedEnough else { return nil }
        return Int((Double(timedWords) / timedSeconds * 60).rounded())
    }

    /// Days in a row ending today, or ending yesterday while today has not been dictated yet, since a streak is not
    /// broken by a morning that has not happened.
    public func streak(today: Date, calendar: Calendar = .current) -> Int {
        let have = Set(days)
        var day = calendar.startOfDay(for: today)
        if !have.contains(Self.day(day, calendar)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while have.contains(Self.day(day, calendar)) {
            count += 1
            guard let before = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = before
        }
        return count
    }

    /// A date as its calendar day, written so the days sort in order as text.
    static func day(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
