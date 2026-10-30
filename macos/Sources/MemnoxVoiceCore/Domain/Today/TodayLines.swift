import Foundation

/// The words around Today's table: the line under its title, the strip over it, and the panel's own.
public enum TodayLines {
    /// What the panel says where neither the runtime nor the agent recommended anything, rather than guessing one.
    public static let noRecommendation = "Neither the runtime nor the agent recommended anything for this, so the choice is yours."
    public static let noChoices = "There is nothing to decide here; it is shown so you know it is there."

    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    private static let secondsPerMinute = 60
    private static let secondsPerHour = 3_600
    private static let secondsPerDay = 86_400
    /// Under this many seconds an age reads as now, since the reads behind it are a few seconds apart.
    private static let nowSeconds = 10

    /// "1 Nov. 13 need you, 1 next, 7 open projects", each count from what the window holds.
    public static func headline(_ now: Date, needYou: Int, next: Int, openProjects: Int, calendar: Calendar = .current) -> String {
        let parts = [
            needYou == 0 ? "nothing needs you" : "\(needYou) \(needYou == 1 ? "needs" : "need") you",
            "\(next) next",
            "\(openProjects) open \(openProjects == 1 ? "project" : "projects")",
        ]
        return "\(day(now, calendar: calendar)) " + parts.joined(separator: ", ")
    }

    /// The day as "1 Nov.", in English month words whatever the Mac's language, as every other line here is.
    public static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.day, .month], from: date)
        let month = parts.month.map { months[($0 - 1) % months.count] } ?? ""
        return "\(parts.day ?? 1) \(month)."
    }

    /// "13 need you, the 5 most urgent here", or how many need you when every one is shown.
    public static func strip(needYou: Int, shown: Int) -> String {
        guard needYou > 0 else { return "Nothing needs you" }
        let lead = "\(needYou) \(needYou == 1 ? "needs" : "need") you"
        return shown < needYou ? "\(lead), the \(shown) most urgent here" : lead
    }

    /// What waits, by kind: "4 held calls, 2 stopped, 1 handed back".
    public static func waits(_ items: [TodayItem]) -> String? {
        let held = items.filter { if case .held = $0.kind { true } else { false } }.count
        let stopped = items.filter { $0.state == .stopped }.count
        let back = items.filter { $0.kind == .handedBack }.count
        let parts = [
            held > 0 ? "\(held) held \(held == 1 ? "call" : "calls")" : nil,
            stopped > 0 ? "\(stopped) stopped" : nil,
            back > 0 ? "\(back) handed back" : nil,
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// "synced 13:14", the last time the window read what it shows.
    public static func synced(_ at: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: at)
        return String(format: "synced %02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// How long ago, short enough for a column: "now", "12 s", "4 min", "2 h", "3 d".
    public static func age(_ since: Date?, now: Date) -> String? {
        guard let since else { return nil }
        let seconds = max(0, Int(now.timeIntervalSince(since)))
        if seconds < nowSeconds { return "now" }
        if seconds < secondsPerMinute { return "\(seconds) s" }
        if seconds < secondsPerHour { return "\(seconds / secondsPerMinute) min" }
        if seconds < secondsPerDay { return "\(seconds / secondsPerHour) h" }
        return "\(seconds / secondsPerDay) d"
    }

    /// How long it has waited, in the panel's words.
    public static func waited(_ since: Date?, now: Date) -> String {
        age(since, now: now).map { $0 == "now" ? "Just now" : "\($0) ago" } ?? "Not recorded"
    }

    /// "1 of 13", the open item's place in what the table shows.
    public static func position(of id: String?, in items: [TodayItem]) -> String? {
        guard let id, let at = items.firstIndex(where: { $0.id == id }) else { return nil }
        return "\(at + 1) of \(items.count)"
    }

    /// The muted line under a title: the runtime's recommendation where it gave one, else the item's own detail.
    public static func under(_ item: TodayItem) -> String? {
        item.recommendation.map { "Recommend: \($0)" } ?? item.detail
    }

    /// How many distinct repositories have a session still open, which is what open projects counts.
    public static func openProjects(_ sessions: [SessionCard]) -> Int {
        Set(sessions.filter { $0.status != .ended }.compactMap { SessionReading.repository($0.repository) }).count
    }
}
