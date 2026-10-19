import AVFoundation
import MemnoxVoiceCore
import Speech

/// The recognizer's language when the Mac's own has none.
private let fallbackLocale = "en-US"

/// Listens while Memnox is thinking and talking, so the person can cut in just by speaking. Its own voice
/// comes back through the microphone too, so only words it did not just say count as the person.
/// Their voice louder than its own echo, or a first word of theirs, pauses it at once, whatever they say;
/// more of them stops it, and silence carries on. While it is still thinking there is nothing to pause,
/// so their words stop the turn outright.
@MainActor
final class BargeEars {
    private let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: fallbackLocale))
    private var generation = 0
    private var listening: Task<String?, Never>?
    private var barged = false
    /// Set while the voice is held quiet on a first word, until more of theirs comes or the wait runs out.
    private var pausedAt: Date?
    private var resume: (() -> Void)?
    /// What was heard when it last carried on, so the same stray word does not pause it again.
    private var resumedOn = ""
    /// What was heard when it paused, so only what comes after is taken for the person.
    private var pausedOn = ""
    /// Set when words of theirs came while the voice was quiet, so the start of their sentence is kept.
    private var spokeInQuiet = false
    /// When its voice last came on, a sentence starting or a pause ending, since loudness lies just after.
    private var voiceOnSince: Date?
    /// Looks in a row the room was louder than its own voice, so one loud syllable of its own pauses nothing.
    private var loudLooks = 0
    /// When it last paused for loudness and nobody was talking, as with a video playing nearby. For a while after,
    /// across replies too, only words pause it, so the room's own sound cannot stutter it sentence after sentence.
    private static var loudnessMisledAt: Date?
    /// Long enough to outlast the replies of one exchange, short enough that a door slamming once is soon forgotten.
    private static let misledFor: TimeInterval = 120
    private var loudnessMisled: Bool {
        BargeEars.loudnessMisledAt.map { Date().timeIntervalSince($0) < BargeEars.misledFor } ?? false
    }
    /// Whether the pause under way was for loudness alone rather than for words.
    private var pausedForLoudness = false
    /// How often the latest words are looked at, quick so a cut in stops the voice at once.
    private static let pollSeconds: TimeInterval = 0.12
    private static let nanosecondsPerSecond: TimeInterval = 1_000_000_000
    /// How long its own sound takes to die away in the room once it is hushed.
    private static let echoFadeSeconds: TimeInterval = 0.25
    /// Loud enough to be somebody talking near the Mac: speech reads about 0.4 to 0.6, a quiet room under 0.1.
    private static let talkingLevel: Float = 0.3
    /// About a third of a second of it, so a cough or a door is not taken for a sentence.
    private static let talkingBuffers = 3
    /// How loud its own voice came back last time, so the next reply knows the room from its first syllable.
    private static var lastEcho: Float?
    /// How much louder or quieter than it plays its voice came back last time, for the same reason.
    private static var lastGap: Float?
    /// About five seconds of looks at the room against what it played, so the gap follows a change of volume.
    private static let looksKept = 40
    /// The newest microphone buffers averaged for one look, about a fifth of a second.
    private static let buffersPerLook = 2

    /// Starts listening for the person over the voice; `cutIn` runs the moment they are heard.
    func watch(
        through audio: AudioIO,
        spoken: @escaping () -> String,
        speaking: @escaping () -> Bool,
        playing: @escaping () -> Float,
        pause: @escaping () -> Void,
        resume: @escaping () -> Void,
        cutIn: @escaping () -> Void
    ) {
        stop(audio)
        self.resume = resume
        // Without a recognizer on this Mac, loudness against what it plays still hears them over it.
        let recognizer = self.recognizer.flatMap { $0.isAvailable && $0.supportsOnDeviceRecognition ? $0 : nil }
        generation += 1
        barged = false
        resumedOn = ""
        pausedOn = ""
        spokeInQuiet = false
        voiceOnSince = nil
        loudLooks = 0
        pausedForLoudness = false
        let mine = generation
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.contextualStrings = recognizerHints
        let room = Loudness()
        room.count(from: Date())
        let talkingLevel = BargeEars.talkingLevel
        let recognizing = recognizer != nil
        audio.onMicrophone = { buffer in
            if recognizing { request.append(buffer) }
            room.hear(loudness(of: buffer), atLeast: talkingLevel)
        }
        let latest = Latest()
        let task = recognizer?.recognitionTask(with: request) { result, _ in
            if let result { latest.update(result.bestTranscription.formattedString, final: result.isFinal) }
        }
        listening = Task { [weak self] in
            defer {
                if self?.generation == mine { audio.onMicrophone = nil }
                request.endAudio()
                task?.cancel()
            }
            var looks: [TalkOver.Heard] = []
            while self?.generation == mine {
                try? await Task.sleep(nanoseconds: UInt64(BargeEars.pollSeconds * BargeEars.nanosecondsPerSecond))
                guard let self else { return nil }
                let (words, changed, final) = latest.read()
                let voiceOn = speaking()
                room.mark(speaking: voiceOn)
                if !voiceOn {
                    self.voiceOnSince = nil
                    self.loudLooks = 0
                } else if self.voiceOnSince == nil {
                    self.voiceOnSince = Date()
                }
                if room.echoLevels.count >= TalkOver.enoughEcho {
                    BargeEars.lastEcho = TalkOver.echoCeiling(room.echoLevels, lastTime: nil)
                }
                let recent = room.recentLevels.suffix(BargeEars.buffersPerLook)
                if voiceOn, !recent.isEmpty {
                    looks.append(TalkOver.Heard(heard: recent.reduce(0, +) / Float(recent.count), playing: playing()))
                    if looks.count > BargeEars.looksKept { looks.removeFirst(looks.count - BargeEars.looksKept) }
                }
                let gap = TalkOver.ownVoiceGap(looks, lastTime: BargeEars.lastGap)
                if looks.count >= TalkOver.enoughLooks, let gap { BargeEars.lastGap = gap }
                if !self.barged {
                    if let pausedAt = self.pausedAt {
                        // The voice is quiet now, so what comes in after the pause is them.
                        // Its echo was heard before the hush, so sound loud enough to be speech after it is them,
                        // even saying words it said too, like "close it" over its own "shall I close it".
                        // Loud alone is them only with no recognizer here; with one, a word of theirs must come too,
                        // since its own echo dying away is loud and says its own words, like "investment advisor".
                        let theirs = withoutEcho(sincePause(words, pausedOn: self.pausedOn), spoken: spoken())
                        let talking = room.loud >= BargeEars.talkingBuffers && (!recognizing || !theirs.isEmpty)
                        if talking || isPersonAfterPause(sincePause(words, pausedOn: self.pausedOn), spoken: spoken()) {
                            self.barged = true
                            self.pausedAt = nil
                            diary.note("talked over: \(sincePause(words, pausedOn: self.pausedOn))")
                            cutIn()
                        } else if TalkOver.mayCarryOn(
                            pausedFor: Date().timeIntervalSince(pausedAt),
                            quietFor: Date().timeIntervalSince(max(room.lastLoud ?? .distantPast, pausedAt.addingTimeInterval(BargeEars.echoFadeSeconds)))
                        ) {
                            self.pausedAt = nil
                            self.resumedOn = words
                            if self.pausedForLoudness { BargeEars.loudnessMisledAt = Date() }
                            diary.note("carried on, nobody was talking: \(words)")
                            resume()
                        }
                    } else if voiceOn {
                        // Its own sound is loud too, so only what comes once it has died away is counted as them.
                        room.count(from: Date().addingTimeInterval(BargeEars.echoFadeSeconds))
                        let echo = TalkOver.echoCeiling(room.echoLevels, lastTime: BargeEars.lastEcho)
                        let loudNow = TalkOver.isTalkingOver(room.recentLevels, echo: echo)
                            || gap.map { TalkOver.isOverOwnVoice(looks, gap: $0, talking: talkingLevel) } == true
                        self.loudLooks = loudNow ? self.loudLooks + 1 : 0
                        let louder = !self.loudnessMisled && TalkOver.mayPauseOnLoudness(
                            voiceOnFor: Date().timeIntervalSince(self.voiceOnSince ?? Date()),
                            loudLooks: self.loudLooks,
                            cancellingEcho: audio.cancelsEcho
                        )
                        if louder || (words != self.resumedOn && mayBeCuttingIn(heard: words, spoken: spoken())) {
                            // Paused rather than stopped, since a sound or a word of its own misheard looks the
                            // same at first, and only what comes once it is quiet tells the two apart.
                            self.pausedAt = Date()
                            self.pausedOn = words
                            self.pausedForLoudness = louder
                            diary.note(louder ? "paused for a voice over mine" : "paused for: \(words)")
                            pause()
                        }
                    } else if words != self.resumedOn, !nameAlone(words), mayBeCuttingIn(heard: words, spoken: spoken()) {
                        // Never on its name alone, which while it thinks is them checking it heard, and cutting in threw the answer away.
                        self.spokeInQuiet = true
                        // Talking while it thinks is the question changing, so the old answer is dropped
                        // and their words go with the earlier ones as one question, rather than after a stale reply.
                        if room.loud >= BargeEars.talkingBuffers {
                            self.barged = true
                            diary.note("talked while it was thinking: \(words)")
                            cutIn()
                        }
                    }
                }
                // Once they have cut in, their whole sentence is kept until they pause.
                if self.barged, final || Date().timeIntervalSince(changed) > endOfSpeechPause(after: words) {
                    let mine = cutInWords(words, pausedOn: self.pausedOn, spoken: spoken(), spokeInQuiet: self.spokeInQuiet)
                    return mine.isEmpty ? nil : mine
                }
            }
            return nil
        }
    }

    /// What the person said over the voice, waited for until they pause, or nil when nobody cut in.
    func finish(_ audio: AudioIO) async -> String? {
        guard barged, let listening else {
            stop(audio)
            return nil
        }
        let words = await listening.value
        self.listening = nil
        return words?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stop(_ audio: AudioIO) {
        // Never left paused when the ear closes, or the voice would stay quiet with nobody to wake it.
        if pausedAt != nil { resume?() }
        pausedAt = nil
        resume = nil
        generation += 1
        listening?.cancel()
        listening = nil
        audio.onMicrophone = nil
    }
}

/// Loud microphone buffers counted from a moment on, and the levels lately and while the voice spoke,
/// heard on the audio thread and read on the main one.
private final class Loudness: @unchecked Sendable {
    private let lock = NSLock()
    private var since: Date?
    private var heard = 0
    private var lastLoudAt: Date?
    private var speaking = false
    private var recent: [Float] = []
    private var echo: [Float] = []
    /// A few more than the talk over check reads, so a late poll still sees the newest.
    private static let recentKept = TalkOver.recentBuffers * 2
    /// About five seconds of its own voice, so the echo follows a change of volume.
    private static let echoKept = 240

    func hear(_ level: Float, atLeast threshold: Float) {
        lock.lock()
        defer { lock.unlock() }
        if level >= threshold { lastLoudAt = Date() }
        if let since, Date() >= since, level >= threshold { heard += 1 }
        recent.append(level)
        if recent.count > Self.recentKept { recent.removeFirst(recent.count - Self.recentKept) }
        if speaking {
            echo.append(level)
            if echo.count > Self.echoKept { echo.removeFirst(echo.count - Self.echoKept) }
        }
    }

    /// Whether what comes in now is heard over its own voice, which is the only time its echo is learned.
    func mark(speaking: Bool) {
        lock.lock()
        defer { lock.unlock() }
        self.speaking = speaking
    }

    var recentLevels: [Float] {
        lock.lock()
        defer { lock.unlock() }
        return recent
    }

    var echoLevels: [Float] {
        lock.lock()
        defer { lock.unlock() }
        return echo
    }

    /// Starts counting again, from a moment that may still be ahead.
    func count(from moment: Date) {
        lock.lock()
        defer { lock.unlock() }
        since = moment
        heard = 0
    }

    /// When the room was last as loud as somebody talking, nil when it never has been.
    var lastLoud: Date? {
        lock.lock()
        defer { lock.unlock() }
        return lastLoudAt
    }

    var loud: Int {
        lock.lock()
        defer { lock.unlock() }
        return heard
    }
}
