import Foundation

/// How long the full screen scan after setup stays up: until the voice has said all of it, then a moment more, so the
/// screen never goes while it is still being explained. Only a narration that never starts, such as a muted voice,
/// falls back to the fixed cap a silent screen needs to be read.
public enum ScanStay {
    /// Long enough to read every agent on the screen when nothing is said over it.
    public static let silentCap: TimeInterval = 25
    /// A breath after the last word, so the screen does not vanish on the word that tells them how to close it.
    public static let afterNarration: TimeInterval = 4
    /// How often the screen looks at the voice again, quick enough that the close never feels late.
    public static let checkEvery: TimeInterval = 0.25

    /// Whether the scan closes on its own now. `voiceStarted` is whether the narration was ever heard, and
    /// `narratedFor` is how long ago it finished, nil while it is still being said.
    public static func closes(shownFor: TimeInterval, voiceStarted: Bool, narratedFor: TimeInterval?) -> Bool {
        if voiceStarted {
            guard let narratedFor else { return false }
            return narratedFor >= afterNarration
        }
        return shownFor >= silentCap
    }
}
