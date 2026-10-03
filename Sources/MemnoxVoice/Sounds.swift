import AppKit
import MemnoxVoiceCore

/// The Mac's own system sounds, quiet, so a cue sits under the voice rather than over it and
/// nothing has to ship or be licensed.
final class SystemChimes: Chimes, @unchecked Sendable {
    /// On unless the person turns it off in the menu bar panel.
    static let key = "chimes"
    /// Low enough that the barge ear and the recognizer never take a cue for the person talking.
    private static let volume: Float = 0.35

    /// The system sounds by their file names in /System/Library/Sounds.
    private enum SystemSound: String {
        case tink = "Tink"
        case pop = "Pop"
        case glass = "Glass"
        case hero = "Hero"
        case bottle = "Bottle"
        case ping = "Ping"
        case basso = "Basso"
        case purr = "Purr"
        case blow = "Blow"
    }

    /// Every cue has a sound, so a new cue is a compile error here until it is given one.
    private static func sound(for cue: Cue) -> SystemSound {
        switch cue {
        case .listening: .tink
        case .sent: .pop
        case .held: .glass
        case .allowed: .hero
        case .declined: .bottle
        case .done: .ping
        case .failed: .basso
        case .settled: .purr
        case .closed: .blow
        }
    }

    func play(_ cue: Cue) {
        guard UserDefaults.standard.bool(forKey: Self.key) else { return }
        let name = NSSound.Name(Self.sound(for: cue).rawValue)
        DispatchQueue.main.async {
            // A fresh copy each time, since the shared one stays silent when asked again mid play.
            guard let sound = NSSound(named: name)?.copy() as? NSSound else { return }
            sound.volume = Self.volume
            sound.play()
        }
    }
}
