import AVFoundation
import Foundation

/// The calm bed under setup, from scripts/make-sounds.py: faded in when setup opens, out when it closes, low enough
/// that Memnox's voice is always heard over it, and off for good once the person turns it off.
@MainActor
final class SetupAmbience: ObservableObject {
    static let shared = SetupAmbience()

    /// On unless the person turns it off from setup's own footer.
    static let key = "setupAmbience"
    @Published private(set) var on: Bool

    private var player: AVAudioPlayer?

    private enum Level {
        /// Under the voice and the chimes, a room tone rather than music somebody listens to.
        static let playing: Float = 0.18
        static let fadeIn: TimeInterval = 3
        static let fadeOut: TimeInterval = 1.5
    }

    /// The AAC bed where the build could encode one, else the WAV make-sounds.py writes instead.
    private static let names = [("setup-ambience", "m4a"), ("setup-ambience", "wav")]
    private static let folder = "Sounds"

    private init() {
        UserDefaults.standard.register(defaults: [Self.key: true])
        on = UserDefaults.standard.bool(forKey: Self.key)
    }

    func start() {
        guard on, player?.isPlaying != true else { return }
        guard let url = Self.names.lazy.compactMap({ Bundle.main.url(forResource: $0.0, withExtension: $0.1, subdirectory: Self.folder) }).first,
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.numberOfLoops = -1
        player.volume = 0
        player.prepareToPlay()
        player.play()
        player.setVolume(Level.playing, fadeDuration: Level.fadeIn)
        self.player = player
    }

    func stop() {
        guard let player else { return }
        self.player = nil
        player.setVolume(0, fadeDuration: Level.fadeOut)
        // Stopped once it has faded, rather than cut, which would be heard as a click.
        DispatchQueue.main.asyncAfter(deadline: .now() + Level.fadeOut) { player.stop() }
    }

    func toggle() {
        on.toggle()
        UserDefaults.standard.set(on, forKey: Self.key)
        if on { start() } else { stop() }
    }
}
