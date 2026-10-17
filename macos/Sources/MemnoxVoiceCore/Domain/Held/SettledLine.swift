import Foundation

/// What the card says for a moment when its call was settled somewhere else, built only from what was reported:
/// "Allowed once by Ana in the console", "Denied on Ana's iPhone", and no claim at all where nothing was said.
public enum SettledLine {
    /// Nothing says who or how, and it may have run out rather than been answered, so it claims neither.
    public static let unknown = "No longer waiting"

    public static func line(answer: String?, by person: String?, on device: String?) -> String {
        let person = CallLabel.trimmed(person)
        let device = CallLabel.trimmed(device)
        let verb = CallLabel.trimmed(answer).flatMap { verbs[$0] }
        guard person != nil || device != nil else { return verb.map { "\($0) elsewhere" }.map(capitalized) ?? unknown }
        var line = verb ?? "answered"
        // "Ana's iPhone" already says whose, so "by Ana" beside it would say it twice.
        if let person, !(device?.hasPrefix("\(person)'s ") ?? false) { line += " by \(person)" }
        if let device { line += " \(Self.where(device))" }
        return capitalized(line)
    }

    /// The console and chat are places rather than devices, so they are said as places.
    private static func `where`(_ device: String) -> String {
        places[device.lowercased()] ?? "on \(device)"
    }

    private static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    private static let verbs: [String: String] = [
        HoldAnswer.once.rawValue: "allowed once",
        HoldAnswer.session.rawValue: "allowed for the session",
        HoldAnswer.deny.rawValue: "denied",
    ]

    private static let places: [String: String] = [
        "console": "in the console",
        "slack": "in Slack",
    ]
}
