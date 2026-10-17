import Foundation
import MemnoxVoiceCore

/// The one switch that keeps Memnox from speaking, shared by the menu bar, Settings and the first run so all three
/// show the same thing. The words still show in the notch, so muting loses nothing but the sound.
@MainActor
final class VoiceMute: ObservableObject {
    static let shared = VoiceMute()

    @Published private(set) var on = Voice.muted
    /// The voice to cut off mid sentence when muted, since a mute that waits for the end is no mute.
    weak var voice: Voice?

    private init() {}

    func set(_ muted: Bool) {
        on = muted
        UserDefaults.standard.set(muted, forKey: Voice.mutedKey)
        diary.note(muted ? "voice muted" : "voice unmuted")
        if muted { voice?.stop() }
    }

    func toggle() { set(!on) }
}
