import AppKit
import MemnoxVoiceCore

/// The Mac's own system sounds, quiet, so a cue sits under the voice rather than over it and
/// nothing has to ship or be licensed.
final class SystemChimes: Chimes, @unchecked Sendable {
    /// On unless the person turns it off in the menu bar panel.
    static let key = "chimes"
    /// Low enough that the barge ear and the recognizer never take a cue for the person talking.
    private static let volume: Float = 0.35

    private static let sounds: [Cue: NSSound.Name] = [
        .listening: "Tink",
        .sent: "Pop",
        .held: "Glass",
        .allowed: "Hero",
        .declined: "Bottle",
        .done: "Ping",
        .failed: "Basso",
        .settled: "Purr",
        .closed: "Blow",
    ]

    func play(_ cue: Cue) {
        guard UserDefaults.standard.bool(forKey: Self.key), let name = Self.sounds[cue] else { return }
        DispatchQueue.main.async {
            // A fresh copy each time, since the shared one stays silent when asked again mid play.
            guard let sound = NSSound(named: name)?.copy() as? NSSound else { return }
            sound.volume = Self.volume
            sound.play()
        }
    }
}
