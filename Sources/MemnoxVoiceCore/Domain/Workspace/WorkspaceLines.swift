import Foundation

/// What the person reads about signing in to their workspace and answering its calls, in words they can act on.
public enum WorkspaceLines {
    public static let noKey = "This Mac has no Touch ID key, so it cannot answer what your workspace routes to you."
    public static let unreachable = "Memnox Cloud did not answer. Check the connection and try again."
    public static let expired = "The code ran out before it was approved. Start again for a new one."
    public static let cancelled = "Signing in was stopped."
    public static let noWorkspace = "Your account reaches no workspace yet, so there is nothing to answer."
    public static let notKept = "Signed in, but the credential could not be kept in the keychain, so this Mac was removed again."
    public static let signedOut = "Your workspace signed this Mac out. Sign in again to answer its calls."
    public static let notReached = "Memnox Cloud would not take that answer: the call has not reached you, or this Mac's signature was not accepted."
    public static let gone = "That call is no longer waiting on you."
    public static let answeredByVoice = "Very well. Your team has your answer."

    /// The console's refusal of the code, said plainly where it is one the contract names.
    public static func refused(_ word: String) -> String {
        switch word {
        case "access_denied": return "The sign in was declined in the console."
        case "expired_token": return expired
        case "invalid_grant": return "That code was already used. Start again for a new one."
        default: return "Memnox Cloud refused the sign in: \(word)."
        }
    }

    /// The code to type, said once the console page is open.
    public static func enterCode(_ code: String) -> String {
        "Approve this Mac in the console with the code \(code)."
    }
}
