import Foundation

/// What it says when called, the way J.A.R.V.I.S. looks up from his work: brief, composed, and
/// using the address they chose, never one guessed. The first call in a while is greeted for the
/// hour; any other is a word or two, and never the same line twice running. Their name is kept
/// for the greeting and comes back at most once in a while, since a name said every time grates.
public struct WakeLines {
    /// Long enough apart that being called again is a fresh start, and earns a greeting.
    public static let freshAfter: TimeInterval = 3 * 60 * 60
    /// How long their name rests once said, far longer than the title does.
    public static let nameRests: TimeInterval = 30 * 60
    /// The hour the morning greeting gives way to the afternoon one.
    private static let afternoonFrom = 12
    /// The hour the afternoon greeting gives way to the evening one.
    private static let eveningFrom = 17
    private var last: String?
    private var namedAt: Date?

    public init() {}

    public mutating func line(
        address: String?,
        name: String? = nil,
        hour: Int,
        sinceLastCall: TimeInterval?,
        at moment: Date = Date(),
        pick: ([String]) -> String? = { $0.randomElement() }
    ) -> String {
        let title = Self.trimmed(address)
        let known = Self.trimmed(name).flatMap { $0 == title ? nil : $0 }
        let fresh = sinceLastCall.map { $0 >= Self.freshAfter } ?? true
        let rested = namedAt.map { moment.timeIntervalSince($0) >= Self.nameRests } ?? true
        // The name only once they chose any address at all, since a name alone was never a choice of how to be called.
        let named = title != nil && known != nil && rested
        let to = named ? known : title
        let lines = fresh ? Self.greetings(to: to, hour: hour) : Self.replies(to: to)
        let choices = lines.count > 1 ? lines.filter { $0 != last } : lines
        let chosen = pick(choices) ?? lines[0]
        last = chosen
        if named { namedAt = moment }
        return chosen
    }

    private static func trimmed(_ text: String?) -> String? {
        text.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func greetings(to: String?, hour: Int) -> [String] {
        let part = hour < afternoonFrom ? "Good morning" : hour < eveningFrom ? "Good afternoon" : "Good evening"
        let named = to.map { "\(part), \($0)." } ?? "\(part)."
        return ["\(named) How shall we proceed?", "\(named) What can I do for you?", "\(named) At your service."]
    }

    private static func replies(to: String?) -> [String] {
        guard let to else {
            return ["Yes?", "At your service.", "How may I assist?", "Standing by.", "Ready for your next command."]
        }
        return [
            "Yes, \(to)?", "\(capitalizedFirst(to))?", "At your service, \(to).", "How may I assist, \(to)?",
            "Standing by, \(to).", "Ready when you are, \(to).",
        ]
    }

    private static func capitalizedFirst(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
