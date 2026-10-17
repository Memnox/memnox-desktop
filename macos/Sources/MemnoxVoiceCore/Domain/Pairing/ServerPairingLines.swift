import Foundation

/// What setup says while this Mac pairs with a server over the relay, kept apart from the screen so the words are tested.
/// A server keeps no Mac key, so the person accepts there by typing the digits this Mac shows into memnox pair.
public enum ServerPairingLines {
    public static let typeCode = "Type these six digits into memnox pair on the server."

    public static func connected(_ server: String) -> String {
        let name = server.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Connected to your server." : "Connected to \(name)."
    }

    public static func refused(_ why: InvitationError) -> String {
        switch why {
        case .notAPairingLink: return "That is not a Memnox pairing link. Paste the memnox://pair link that memnox pair printed."
        case .unreadable: return "That pairing link could not be read. Run memnox pair again and paste the new link."
        case .unsupportedVersion: return "That server runs a newer Memnox than this app. Update the app, then pair again."
        case .expired: return "That link ran out. Run memnox pair again and paste the new link."
        }
    }

    public static func failed(_ why: PairingFailure) -> String {
        switch why {
        case .wrongMac: return "The machine that answered is not the one in the link, so this Mac stopped. Run memnox pair again."
        case .declined: return "The server did not pair this Mac."
        case .cancelled: return "Touch ID was cancelled, so this Mac did not pair."
        case .broken: return unreachable
        }
    }

    public static let unreachable = "The relay could not be reached, or the server stopped answering. Check the connection and try again."
    public static let notKept = "Paired, but this Mac could not keep the server in its keychain, so pair again."
    /// What the Touch ID sheet says while the proof that this Mac holds its key is signed.
    public static let proofReason = "pair this Mac with your server"
    public static let thisMac = "This Mac"
}
