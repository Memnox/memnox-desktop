import Foundation

/// The words a held call is answered with, the same on the terminal, the console, this Mac, Windows, Linux and the
/// phone. Mirrors `memnox-runtime/docs/ux/contract.json`, whose verbatim copy at `shared/ux/contract.json` is tested.
public enum AnswerWords {
    /// The narrowest yes first and Deny last on every surface, so a hand reaching for the usual place never lands on the
    /// wrong answer. Always allow writes a rule, so it stands apart from these, where a rule can be signed.
    public static let order: [HoldAnswer] = [.once, .session, .deny]

    public static func label(_ answer: HoldAnswer) -> String {
        switch answer {
        case .once: "Allow once"
        case .session: "Allow for this session"
        case .deny: "Deny"
        case .always: "Always allow"
        }
    }

    /// What stays on screen once a call is decided.
    public static func outcome(_ answer: HoldAnswer) -> String {
        switch answer {
        case .once: "allowed once"
        case .session: "allowed for this session"
        case .deny: "denied"
        case .always: "allowed, with a rule to sign"
        }
    }

    /// The edit a terminal offers beside a command, named here so the contract's whole answer set is in one place.
    public static let edit = "Edit the command first"
    /// The answer that writes a deny rule, offered only where a rule can be signed.
    public static let alwaysDeny = "Always deny"
}

/// Why a session needs its person or was stopped, worded as what the person will do about it.
public enum SessionReason: String, CaseIterable, Sendable {
    case approval
    case question
    case plan
    case paused
    case breaker
    case budget
    case interrupted

    public var label: String {
        switch self {
        case .approval: "Needs approval"
        case .question: "Has a question"
        case .plan: "Plan to review"
        case .paused: "Paused"
        case .breaker: "Paused by the breaker"
        case .budget: "Stopped by a budget"
        case .interrupted: "Interrupted, resumable"
        }
    }
}
