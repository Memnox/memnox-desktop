import Foundation

/// Where a held call waits, which is what every label of it names.
public enum CallPlace: Equatable, Sendable {
    case thisMac
    /// A server this Mac paired with over the relay, by the name it paired under.
    case server(String)
    /// A teammate's machine the workspace routed the call from, with whose team it is when the workspace says.
    case team(machine: String, person: String?)

    /// A daemon event's place: the server that raised it, or this Mac when none did.
    public static func raised(on server: String?) -> CallPlace {
        CallLabel.trimmed(server).map(CallPlace.server) ?? .thisMac
    }

    /// The machine alone, as the island groups waiting calls by it.
    public var machine: String {
        switch self {
        case .thisMac: return CallLabel.thisMac
        case .server(let name): return CallLabel.trimmed(name) ?? CallLabel.someServer
        case .team(let machine, _): return CallLabel.trimmed(machine) ?? CallLabel.someMachine
        }
    }
}

/// One label for a held call wherever it shows: the island's card, the Touch ID sheet, the caption and the voice.
/// "codex on build-box", "Claude Code on your Mac", and "codex on build-box, from Ana's team" through the workspace.
public enum CallLabel {
    public static let thisMac = "your Mac"
    static let someServer = "a server"
    static let someMachine = "a teammate's machine"
    static let someAgent = "an agent"

    public static func label(_ agent: String, at place: CallPlace) -> String {
        let named = "\(trimmed(agent) ?? someAgent) on \(place.machine)"
        guard case .team(_, let person) = place else { return named }
        return "\(named), \(team(person))"
    }

    /// Whose team it came through, and the person's own team where the workspace did not say whose.
    static func team(_ person: String?) -> String {
        trimmed(person).map { "from \($0)'s team" } ?? "from your team"
    }

    /// What the Touch ID sheet says it is for, so the sensor is touched knowing whose call, where, and how far the yes reaches.
    public static func touchIDReason(_ label: String, what: String, answer: HoldAnswer) -> String {
        let reach: String
        switch answer {
        case .once: reach = "allow \(label) once"
        case .session: reach = "allow \(label) for this session"
        case .deny: reach = "deny \(label)"
        case .always: reach = "allow \(label) now, and put a rule for from now on to you"
        }
        guard let what = trimmed(what) else { return reach }
        return "\(reach): \(unended(what))"
    }

    /// Nil for nothing but spaces, so a blank name never makes "on ".
    static func trimmed(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    /// A full stop inside the sheet's sentence reads as the end of it, so the last one goes.
    private static func unended(_ text: String) -> String {
        text.hasSuffix(".") ? String(text.dropLast()) : text
    }
}
