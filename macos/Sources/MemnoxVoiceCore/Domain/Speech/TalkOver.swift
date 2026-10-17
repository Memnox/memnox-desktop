import Foundation

/// Telling the person starting to talk from the voice's own sound coming back through the microphone,
/// by loudness alone, so the voice goes quiet on their first syllable rather than on their second word.
/// Levels are on the zero to one decibel scale the microphone is read on.
public enum TalkOver {
    /// How far over its own echo the room has to get, about four decibels, so a loud syllable of its own does not count.
    public static let margin: Float = 0.09
    /// Of the latest buffers, how many must be that loud: about a tenth of a second of a voice, not a click.
    public static let recentBuffers = 5
    public static let loudBuffers = 4
    /// Enough of its own speech heard to know how loud it comes back, about half a second.
    public static let enoughEcho = 24
    /// What its echo is taken to be before any has been heard: a voice from the speakers at a normal volume.
    public static let unheardEcho: Float = 0.5
    /// The share of its own loudest moments ignored, since one peak is not how loud it usually comes back.
    public static let echoQuantile: Float = 0.95

    /// How loud its own voice comes back, from the levels heard while it spoke, or what it was last time when too few.
    public static func echoCeiling(_ heardWhileSpeaking: [Float], lastTime: Float?) -> Float {
        guard heardWhileSpeaking.count >= enoughEcho else {
            return max(lastTime ?? unheardEcho, heardWhileSpeaking.max() ?? 0)
        }
        let sorted = heardWhileSpeaking.sorted()
        let at = min(sorted.count - 1, Int(Float(sorted.count - 1) * echoQuantile))
        return sorted[at]
    }

    /// Whether the latest buffers are somebody talking over it, louder than its own echo for long enough.
    public static func isTalkingOver(_ recent: [Float], echo ceiling: Float) -> Bool {
        let latest = recent.suffix(recentBuffers)
        return latest.filter { $0 >= ceiling + margin }.count >= loudBuffers
    }

    // MARK: Trusting loudness

    /// After its voice starts or comes back, how long loudness alone is not trusted: the player's meter reads
    /// near silence for a moment while its echo is already loud, which paused it on itself after every resume.
    public static let onsetGrace: TimeInterval = 0.5
    /// Looks in a row loudness alone must agree for with echo cancellation, where the room is the person.
    public static let loudLooksCancelling = 1
    /// The same without it, about a third of a second, since its own echo is loud then and one look is a syllable.
    public static let loudLooksUncancelled = 3

    /// Whether loudness alone may pause the voice now: not just after it came on, and only once it has held.
    public static func mayPauseOnLoudness(voiceOnFor: TimeInterval, loudLooks: Int, cancellingEcho: Bool) -> Bool {
        voiceOnFor >= onsetGrace && loudLooks >= (cancellingEcho ? loudLooksCancelling : loudLooksUncancelled)
    }

    // MARK: While held quiet

    /// Held at least this long, so the recognizer can still write words the person already said.
    public static let shortestHold: TimeInterval = 1
    /// After its own sound has died away, the room this long below a voice means nobody is talking.
    public static let quietToCarryOn: TimeInterval = 0.6
    /// The longest a loud room with no words in it keeps it quiet, so a television cannot silence it for good.
    public static let longestHold: TimeInterval = 4

    /// Whether to carry on talking after a pause: never while the room is loud as a voice, since that is the
    /// person and carrying on over them is the one thing a pause exists to prevent.
    public static func mayCarryOn(pausedFor: TimeInterval, quietFor: TimeInterval) -> Bool {
        pausedFor >= longestHold || (pausedFor >= shortestHold && quietFor >= quietToCarryOn)
    }

    // MARK: Against what it is playing

    /// One look at the room: how loud the microphone heard it, and how loud its own voice was playing then.
    public struct Heard: Sendable, Equatable {
        public let heard: Float
        public let playing: Float

        public init(heard: Float, playing: Float) {
            self.heard = heard
            self.playing = playing
        }
    }

    /// Loud enough playing to learn from how much of it comes back, rather than the hush between words.
    public static let playingFloor: Float = 0.2
    /// Looks at its own voice playing needed before how loud it comes back is trusted, about a second.
    public static let enoughLooks = 8
    /// How much louder than its own echo the room must be, about seven decibels on the loudness scale.
    public static let overOwnMargin: Float = 0.15
    /// Looks in a row that must agree, about a quarter of a second, so the tail of one of its words is not a person.
    public static let overOwnLooks = 2

    /// How much louder or quieter its voice comes back than it plays, from looks while it played, or last time's
    /// when too few; nil when nothing is known yet, since a guess here would pause it on its own echo.
    public static func ownVoiceGap(_ looks: [Heard], lastTime: Float?) -> Float? {
        let gaps = looks.filter { $0.playing >= playingFloor }.map { $0.heard - $0.playing }.sorted()
        guard gaps.count >= enoughLooks else { return lastTime }
        return gaps[gaps.count / 2]
    }

    /// Whether the latest looks are somebody talking over it: the room loud as a voice, and louder than its own
    /// echo of what was playing then or a moment before, which is how the person is told from it without echo
    /// cancellation, and in the hush between its words at once.
    public static func isOverOwnVoice(_ looks: [Heard], gap: Float, talking: Float) -> Bool {
        guard looks.count > overOwnLooks else { return false }
        let indices = looks.indices.suffix(overOwnLooks)
        return indices.allSatisfy { index in
            let playing = max(looks[index].playing, looks[index - 1].playing)
            return looks[index].heard >= talking && looks[index].heard - playing >= gap + overOwnMargin
        }
    }
}
