import Foundation

/// What the voice and the setup row say as a phone pairing goes, kept apart from the screen so the words are tested.
public enum PairingLines {
    /// Said once a phone is paired: "Your iPhone is paired", or the name alone when it already says whose it is.
    public static func paired(_ phone: String) -> String {
        let name = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Your phone is paired." }
        let owned = possessives.contains { name.contains($0) }
        return owned ? "\(name) is paired." : "Your \(name) is paired."
    }

    public static let declined = "The phone was not paired."
    public static let expired = "The code ran out before a phone used it. Pair again when your phone is ready."
    public static let unreachable = "Memnox on this Mac is not answering, so a phone cannot pair yet."
    /// Said when the daemon refused without a reason of its own.
    public static let refused = "Memnox would not open a pairing just now."
    /// Said before the daemon is even asked, when this Mac has no workspace to carry the phone to it.
    public static let connectFirst = "This Mac is not connected to a workspace yet, which is what carries the phone to it. Connect it on the Account page, then pair again."

    /// A name like "Sam's iPhone" already says whose it is, with a straight or a curly apostrophe.
    private static let possessives = ["'s ", "\u{2019}s "]
}
