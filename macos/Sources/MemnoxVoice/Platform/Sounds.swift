import AppKit
import AVFoundation
import MemnoxVoiceCore

/// Memnox's own cue sounds, from scripts/make-sounds.py, quiet so a cue sits under the voice rather than over it.
/// Each is loaded once and kept ready, so it starts the moment it is asked for and a second can overlap the first.
final class CueChimes: Chimes, @unchecked Sendable {
    /// On unless the person turns it off in the menu bar panel.
    static let key = "chimes"
    /// How loud a cue plays, set by the slider under Sounds in Settings.
    static let volumeKey = "chimeVolume"
    /// Low enough that the barge ear and the recognizer never take a cue for the person talking.
    static let defaultVolume = 0.35
    /// Never silent, since Sounds off is the way to silence them and a slider at nothing would be a second switch.
    static let quietest = 0.05

    private static var volume: Float {
        let set = UserDefaults.standard.double(forKey: volumeKey)
        return Float(set == 0 ? defaultVolume : min(1, max(quietest, set)))
    }
    /// Two of each, so a cue asked for again while it still rings starts over it rather than cutting it off.
    private static let copies = 2
    /// Where bundle.sh puts the sounds inside the app.
    private static let folder = "Sounds"
    private static let fileType = "wav"

    /// Touched only on the main queue, which is where every cue plays.
    private var players: [Cue: [AVAudioPlayer]] = [:]
    private var next: [Cue: Int] = [:]

    init() {
        for cue in Cue.allCases {
            guard let url = Bundle.main.url(forResource: cue.rawValue, withExtension: Self.fileType, subdirectory: Self.folder) else { continue }
            let ready = (0..<Self.copies).compactMap { _ -> AVAudioPlayer? in
                guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
                player.prepareToPlay()
                return player
            }
            if !ready.isEmpty { players[cue] = ready }
        }
    }

    func play(_ cue: Cue) {
        guard UserDefaults.standard.bool(forKey: Self.key) else { return }
        DispatchQueue.main.async { [self] in
            guard let ready = players[cue] else {
                Self.playSystem(cue)
                return
            }
            let index = next[cue, default: 0]
            next[cue] = (index + 1) % ready.count
            let player = ready[index]
            player.volume = Self.volume
            player.currentTime = 0
            player.play()
        }
    }

    /// The Mac's own sound for a cue, for a build that carries none of ours.
    private static func playSystem(_ cue: Cue) {
        // A fresh copy each time, since the shared one stays silent when asked again mid play.
        guard let sound = NSSound(named: systemSound(for: cue))?.copy() as? NSSound else { return }
        sound.volume = volume
        sound.play()
    }

    /// Every cue has a sound, so a new cue is a compile error here until it is given one.
    private static func systemSound(for cue: Cue) -> NSSound.Name {
        switch cue {
        case .listening: "Tink"
        case .sent: "Pop"
        case .held: "Glass"
        case .allowed: "Hero"
        case .declined: "Bottle"
        case .done: "Ping"
        case .finished: "Submarine"
        case .failed: "Basso"
        case .settled: "Purr"
        case .closed: "Blow"
        }
    }
}
