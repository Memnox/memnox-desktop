import Foundation

/// What it says when called, the way J.A.R.V.I.S. looks up from his work: brief, composed, and
/// using the address they chose, never one guessed. The first call in a while is greeted for the
/// hour; any other is a word or two, and never the same line twice running.
public struct WakeLines {
    /// Long enough apart that being called again is a fresh start, and earns a greeting.
    public static let freshAfter: TimeInterval = 3 * 60 * 60
    /// The hour the morning greeting gives way to the afternoon one.
    private static let afternoonFrom = 12
    /// The hour the afternoon greeting gives way to the evening one.
    private static let eveningFrom = 17
    private var last: String?

    public init() {}

    public mutating func line(
        address: String?,
        hour: Int,
        sinceLastCall: TimeInterval?,
        pick: ([String]) -> String? = { $0.randomElement() }
    ) -> String {
        let to = address.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
        let fresh = sinceLastCall.map { $0 >= Self.freshAfter } ?? true
        let lines = fresh ? Self.greetings(to: to, hour: hour) : Self.replies(to: to)
        let choices = lines.count > 1 ? lines.filter { $0 != last } : lines
        let chosen = pick(choices) ?? lines[0]
        last = chosen
        return chosen
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
