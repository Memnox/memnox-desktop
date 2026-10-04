import AVFoundation
import MemnoxVoiceCore
import Speech

/// The fallback when no better English voice or recognizer locale is on this Mac.
private let fallbackLanguage = "en-US"
private let nanosecondsPerSecond: TimeInterval = 1_000_000_000

/// The microphone, and only while a conversation runs, so the microphone light means something.
/// Speech goes out through the system synthesizer instead, which is the one path macOS never
/// ducks or silences, since echo cancellation on an engine turns every other sound down.
final class AudioIO {
    let engine = AVAudioEngine()
    private(set) var micLevel: Float = 0
    /// Loud enough to be somebody talking rather than a room, on the same scale as `micLevel`.
    static let voiceLevel: Float = 0.45
    /// Every microphone buffer while listening, for the recognizer.
    var onMicrophone: ((AVAudioPCMBuffer) -> Void)?
    private var running = false
    /// Frames per microphone tap, about twenty milliseconds at 48 kHz.
    private static let tapBufferFrames: AVAudioFrameCount = 1024

    func start() throws {
        guard !running else { return }
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: Self.tapBufferFrames, format: input.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            self?.micLevel = loudness(of: buffer)
            self?.onMicrophone?(buffer)
        }
        engine.prepare()
        try engine.start()
        running = true
        diary.note("microphone on: \(input.outputFormat(forBus: 0))")
    }

    func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
        micLevel = 0
    }
}

/// Amplitude to decibels is twenty times the base ten log.
private let decibelsPerDecade: Float = 20
/// The quietest amplitude counted, so silence is a finite number of decibels.
private let silenceFloor: Float = 0.000_01
/// The decibels shown as zero, and the span above them shown as one.
private let quietestDecibels: Float = -55
private let decibelSpan: Float = 45

/// Loudness from zero to one, on a decibel scale, because that is how a voice sounds.
func loudness(of buffer: AVAudioPCMBuffer) -> Float {
    guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
    var sum: Float = 0
    for index in 0..<Int(buffer.frameLength) { sum += channel[index] * channel[index] }
    let rms = (sum / Float(buffer.frameLength)).squareRoot()
    let decibels = decibelsPerDecade * log10(max(rms, silenceFloor))
    return min(max((decibels - quietestDecibels) / decibelSpan, 0), 1)
}

/// Speech out, through the system synthesizer, with the orb moving on every word it says.
// Unchecked because its shared state is behind `lock` and synthesizer work hops to the main queue.
final class Voice: NSObject, Speaker, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    private var voice: AVSpeechSynthesisVoice?
    private static let voiceKey = "voiceIdentifier"
    private let lock = NSLock()
    /// One waiting sentence per utterance, since the synthesizer queues them and a filler may join the queue.
    private var waiting: [ObjectIdentifier: () -> Void] = [:]
    /// Everyone waiting for the queue to empty.
    private var drainers: [() -> Void] = []
    private var lastWord = Date.distantPast
    /// What it said lately, so its own voice coming back through the microphone is not taken for the person.
    private var history: [(at: Date, text: String)] = []
    /// Counted from when a sentence is queued, so it has to outlast the longest reply being spoken
    /// and the echo of its last words; a long answer from Kokoro runs half a minute or more.
    private static let rememberFor: TimeInterval = 120
    /// Kokoro when chosen and running; the system voice when nil, and for any sentence it fails.
    var engine: VoiceEngine?
    /// Each engine sentence's own token, kept alive so its identifier is never reused while waiting.
    private var tokens: [ObjectIdentifier: NSObject] = [:]
    private var engineTail: Task<Void, Never>?
    /// Bumped by stop, so a sentence fetched before somebody talked over it is never played.
    private var engineGeneration = 0
    private var player: AVAudioPlayer?
    private var playerDone: (() -> Void)?
    /// A breath between sentences, long enough that one never runs into the next.
    private static let breath: TimeInterval = 0.26

    /// How the orb's level follows the voice.
    private enum Meter {
        /// The engine's power in decibels shown as zero, and the span above it shown as one.
        static let quietestPower: Float = -45
        static let powerSpan: Float = 40
        /// The least the orb shows while speaking, so it never looks silent mid sentence.
        static let speakingFloor: Float = 0.25
        /// The pulse on each word and how fast it eases away, per second.
        static let wordPeak: Float = 0.9
        static let easePerSecond: Float = 2.5
    }

    /// How the system voice is paced.
    private enum Pacing {
        /// Well under the default and a little lower, so every word lands clearly with no rush.
        static let rateScale: Float = 0.8
        static let pitch: Float = 0.96
        /// A breath after each sentence, since a reply run together with no gaps sounds rushed.
        static let afterSentence: TimeInterval = 0.28
    }

    /// The language code prefix every English voice shares.
    private static let englishPrefix = "en"

    /// What it has said since a moment, which is all its own echo could be while it answers now.
    func spoken(since moment: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        return history.filter { $0.at >= moment }.map(\.text).joined(separator: " ")
    }

    var spokenRecently: String {
        lock.lock()
        defer { lock.unlock() }
        let since = Date().addingTimeInterval(-Self.rememberFor)
        return history.filter { $0.at > since }.map(\.text).joined(separator: " ")
    }

    override init() {
        let chosen = UserDefaults.standard.string(forKey: Self.voiceKey)
        voice = chosen.flatMap(AVSpeechSynthesisVoice.init(identifier:)) ?? Voice.bestVoice()
        super.init()
        synthesizer.delegate = self
    }

    var identifier: String? { voice?.identifier }

    /// How loud the orb should look while speaking: a pulse on each word, easing away between words.
    var level: Float {
        lock.lock()
        defer { lock.unlock() }
        if let player, player.isPlaying {
            player.updateMeters()
            return min(max((player.averagePower(forChannel: 0) - Meter.quietestPower) / Meter.powerSpan, Meter.speakingFloor), 1)
        }
        let since = Float(Date().timeIntervalSince(lastWord))
        return synthesizer.isSpeaking ? max(Meter.speakingFloor, Meter.wordPeak - since * Meter.easePerSecond) : 0
    }

    /// The voice the person picked in setup, kept for next time.
    func choose(_ identifier: String) {
        guard let picked = AVSpeechSynthesisVoice(identifier: identifier) else { return }
        voice = picked
        UserDefaults.standard.set(identifier, forKey: Self.voiceKey)
    }

    func preview(_ sentence: String) async {
        await speak(sentence)
    }

    func speak(_ sentence: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            enqueue(sentence) { continuation.resume() }
        }
    }

    func queue(_ sentence: String) {
        enqueue(sentence) {}
    }

    /// Waits until nothing queued is left to say.
    func drained() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if waiting.isEmpty {
                lock.unlock()
                continuation.resume()
                return
            }
            drainers.append { continuation.resume() }
            lock.unlock()
        }
    }

    /// Main queue order is call order, so sentences are said in the order they were given.
    private func enqueue(_ written: String, said: @escaping () -> Void) {
        // Kept as written for the echo check, since the recognizer hears the words and not their spelling out.
        let sentence = pronounced(written)
        diary.note("saying: \(sentence)")
        lock.lock()
        history.removeAll { Date().timeIntervalSince($0.at) > Self.rememberFor }
        history.append((Date(), written))
        let engine = self.engine
        lock.unlock()
        if let engine {
            enqueueEngine(sentence, with: engine, said: said)
            return
        }
        enqueueSystem(sentence, said: said)
    }

    private func enqueueSystem(_ sentence: String, said: @escaping () -> Void) {
        let utterance = AVSpeechUtterance(string: sentence)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Pacing.rateScale
        utterance.pitchMultiplier = Pacing.pitch
        utterance.postUtteranceDelay = Pacing.afterSentence
        utterance.prefersAssistiveTechnologySettings = false
        lock.lock()
        waiting[ObjectIdentifier(utterance)] = said
        lock.unlock()
        DispatchQueue.main.async { [self] in synthesizer.speak(utterance) }
    }

    func stop() {
        DispatchQueue.main.async { [self] in
            synthesizer.stopSpeaking(at: .immediate)
            lock.lock()
            engineGeneration += 1
            let playing = player
            lock.unlock()
            playing?.stop()
            finishPlayer()
            lock.lock()
            let all = Array(waiting.values) + drainers
            waiting.removeAll()
            tokens.removeAll()
            drainers.removeAll()
            lock.unlock()
            all.forEach { $0() }
        }
    }

    /// Fetched at once, so the next sentence is ready while this one plays, and played in order.
    private func enqueueEngine(_ sentence: String, with engine: VoiceEngine, said: @escaping () -> Void) {
        let token = NSObject()
        let fetch = Task { () -> Data? in
            do { return try await engine.audio(for: sentence) } catch {
                // Cancelled means somebody talked over it, which is not a failure worth noting.
                if (error as? URLError)?.code != .cancelled, !(error is CancellationError) {
                    diary.note("\(engine.name) did not voice it, so the system voice does: \(error.localizedDescription)")
                }
                return nil
            }
        }
        lock.lock()
        waiting[ObjectIdentifier(token)] = said
        tokens[ObjectIdentifier(token)] = token
        let generation = engineGeneration
        let previous = engineTail
        engineTail = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            guard self.inGeneration(generation) else {
                fetch.cancel()
                return
            }
            if let data = await fetch.value {
                await self.play(data, generation: generation)
                try? await Task.sleep(nanoseconds: UInt64(Self.breath * nanosecondsPerSecond))
            } else if self.inGeneration(generation) {
                await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                    self.enqueueSystem(sentence) { done.resume() }
                }
            }
            self.finish(token)
        }
        lock.unlock()
    }

    private func inGeneration(_ generation: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return engineGeneration == generation
    }

    private func play(_ data: Data, generation: Int) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { [self] in
                guard inGeneration(generation), let player = try? AVAudioPlayer(data: data) else {
                    continuation.resume()
                    return
                }
                player.delegate = self
                player.isMeteringEnabled = true
                lock.lock()
                self.player = player
                playerDone = { continuation.resume() }
                lock.unlock()
                if !player.play() { finishPlayer() }
            }
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        finishPlayer()
    }

    private func finishPlayer() {
        lock.lock()
        let done = playerDone
        playerDone = nil
        player = nil
        lock.unlock()
        done?()
    }

    /// Resumes an engine sentence once it has been said, or dropped by a stop.
    private func finish(_ token: NSObject) {
        lock.lock()
        let resume = waiting.removeValue(forKey: ObjectIdentifier(token))
        tokens.removeValue(forKey: ObjectIdentifier(token))
        let finished = waiting.isEmpty ? drainers : []
        if waiting.isEmpty { drainers.removeAll() }
        lock.unlock()
        resume?()
        finished.forEach { $0() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        lock.lock()
        lastWord = Date()
        lock.unlock()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        done(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        done(utterance)
    }

    /// Resumes the sentence this utterance carried, once, whichever of finish, cancel or stop comes first.
    private func done(_ utterance: AVSpeechUtterance) {
        lock.lock()
        let resume = waiting.removeValue(forKey: ObjectIdentifier(utterance))
        let finished = waiting.isEmpty ? drainers : []
        if waiting.isEmpty { drainers.removeAll() }
        lock.unlock()
        resume?()
        finished.forEach { $0() }
    }

    /// Installed English voices, best first, since Premium and Enhanced sound the most like a person.
    static func englishVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(englishPrefix) }
            .sorted { ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name) }
    }

    /// The best English voice installed; a person picks a Premium or Personal Voice in System Settings.
    private static func bestVoice() -> AVSpeechSynthesisVoice? {
        englishVoices().first ?? AVSpeechSynthesisVoice(language: fallbackLanguage)
    }
}

/// Slack past the length the rate ratio gives, so the output buffer is never short.
private let conversionHeadroomFrames: AVAudioFrameCount = 1_024

func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
    let ratio = format.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + conversionHeadroomFrames
    guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
    var fed = false
    var error: NSError?
    converter.convert(to: output, error: &error) { _, status in
        if fed {
            status.pointee = .noDataNow
            return nil
        }
        fed = true
        status.pointee = .haveData
        return buffer
    }
    return error == nil ? output : nil
}

/// Speech in, recognised on this Mac: Apple's SpeechAnalyzer where the system has it, the older
/// recognizer where it does not. It ends an utterance by the pause after it, and hands the
/// words on whole: nothing here looks for a keyword.
final class Ears {
    /// The words so far, for the pill.
    var hearing: ((String) -> Void)?
    /// The words so far at a pause, sent ahead so the answer can start before the pause ends.
    var guessing: ((String) -> Void)?
    /// When the person's last word was heard, where the recognizer can say; nil where it cannot.
    private(set) var lastWordAt: Date?
    /// Said when a voice was heard and no words came of it, so the person knows to say it again.
    var missed: (() -> Void)?
    private let legacy = LegacyEars()
    /// Set once the speech model is on this Mac, and cleared if it ever fails to hear a voice.
    /// Until then the older recognizer listens, so the first question never waits on a download.
    private var analyzerReady = false
    /// Empty results in a row: one is usually its own voice trailing off, not a recognizer that is broken.
    private var misses = 0
    /// When the better recognizer is tried again after it was set aside.
    private var retryAt: Date?
    private static let missesBeforeFallback = 3
    private static let retryAfter: TimeInterval = 10 * 60

    static func askPermission() async -> Bool {
        await LegacyEars.askPermission()
    }

    /// Whether the person has let Memnox hear them, asked for on the first question if not yet.
    static func mayHear() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized,
           AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            return true
        }
        return await askPermission()
    }

    /// Fetches the speech model in the background; SpeechAnalyzer takes over once it is there.
    func prepare() async {
        if #available(macOS 26, *) { analyzerReady = await AnalyzerEars.prepare() }
    }

    func listen(through audio: AudioIO, waiting: TimeInterval) async -> String? {
        if !analyzerReady, let retry = retryAt, Date() >= retry {
            analyzerReady = true
            retryAt = nil
            misses = 0
            diary.note("trying SpeechAnalyzer again")
        }
        if #available(macOS 26, *), analyzerReady {
            let ears = AnalyzerEars()
            ears.hearing = hearing
            ears.guessing = guessing
            lastWordAt = nil
            switch await ears.listen(through: audio, waiting: waiting) {
            case .heard(let words):
                misses = 0
                lastWordAt = ears.lastWordAt
                return words
            case .silence: return nil
            case .unavailable(let recorded):
                // The older recognizer hears this one; only a run of them sets the better one aside, for a while.
                misses += 1
                // What they already said is heard from the recording, so they never have to say it twice.
                if let words = await legacy.transcribe(recorded) {
                    diary.note("older recognizer heard the recording: \(words)")
                    return words
                }
                if misses >= Self.missesBeforeFallback {
                    diary.note("SpeechAnalyzer missed \(misses) in a row, using the older recognizer for now")
                    analyzerReady = false
                    retryAt = Date().addingTimeInterval(Self.retryAfter)
                } else {
                    diary.note("SpeechAnalyzer heard no words, the older recognizer listens this once")
                }
                missed?()
            }
        }
        legacy.hearing = hearing
        legacy.guessing = guessing
        let words = await legacy.listen(through: audio, waiting: waiting)
        diary.note("older recognizer heard \(words ?? "nothing")")
        return words
    }
}

/// Names this machine uses, as hints to the recognizer rather than words anything acts on.
/// Replaced by the daemon's own list at launch, since it knows the agents and CLIs actually here.
nonisolated(unsafe) var recognizerHints = ["Memnox", "Claude Code", "Codex", "Cursor", "kubectl", "Railway", "Vercel", "npm", "git push"]

/// The recognizer before macOS 26.
final class LegacyEars {
    private let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: fallbackLanguage))
    /// A recording of a few seconds is read in well under this; past it the person is waiting.
    private static let transcribeTimeout: TimeInterval = 6
    /// How often the latest words are looked at.
    private static let pollSeconds: TimeInterval = 0.15
    /// The words so far, for the pill.
    var hearing: ((String) -> Void)?
    /// The words so far at a pause, sent ahead so the answer can start before the pause ends.
    var guessing: ((String) -> Void)?

    static func askPermission() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        let microphone = await AVCaptureDevice.requestAccess(for: .audio)
        return speech && microphone
    }

    /// Words in audio already recorded, or nil when there are none or it takes too long.
    func transcribe(_ buffers: [AVAudioPCMBuffer]) async -> String? {
        guard let recognizer, recognizer.isAvailable, !buffers.isEmpty else { return nil }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.contextualStrings = recognizerHints
        for buffer in buffers { request.append(buffer) }
        request.endAudio()
        let once = Once()
        let running = RunningTask()
        return await withCheckedContinuation { continuation in
            running.task = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    let words = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                    once.run { continuation.resume(returning: words.isEmpty ? nil : words) }
                } else if error != nil {
                    once.run { continuation.resume(returning: nil) }
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + LegacyEars.transcribeTimeout) {
                once.run {
                    running.task?.cancel()
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// The next thing said, or nil when nothing was said before the wait ran out. The recognizer
    /// calls a result final on its own, often at a breath mid sentence, so a final result starts a
    /// fresh request and the words carry on: only the person pausing ends what they are saying.
    func listen(through audio: AudioIO, waiting: TimeInterval) async -> String? {
        guard let recognizer, recognizer.isAvailable else {
            diary.note("older recognizer not available: \(SFSpeechRecognizer.authorizationStatus().rawValue)")
            return nil
        }
        let began = Date()
        var settled = ""
        var lastWord = began
        var guessed = ""
        while true {
            let round = startRound(with: recognizer, through: audio)
            var finished = false
            var final = false
            while !finished {
                try? await Task.sleep(nanoseconds: UInt64(Self.pollSeconds * nanosecondsPerSecond))
                let (words, changed, isFinal) = round.latest.read()
                if !words.isEmpty { lastWord = max(lastWord, changed) }
                let all = joined(settled, words)
                hearing?(all)
                if all.isEmpty, Date().timeIntervalSince(began) > waiting { finished = true }
                if !all.isEmpty, Date().timeIntervalSince(lastWord) > endOfSpeechPause(after: all) { finished = true }
                if !finished, all != guessed, mayGuess(all, pausedFor: Date().timeIntervalSince(lastWord)) {
                    guessed = all
                    guessing?(all)
                }
                if isFinal, !finished {
                    final = true
                    settled = all
                    break
                }
                if finished { settled = all }
            }
            audio.onMicrophone = nil
            round.request.endAudio()
            round.task.cancel()
            if !final { break }
        }
        let words = settled.trimmingCharacters(in: .whitespacesAndNewlines)
        return words.isEmpty ? nil : words
    }

    private struct Round {
        let request: SFSpeechAudioBufferRecognitionRequest
        let task: SFSpeechRecognitionTask
        let latest: Latest
    }

    private func startRound(with recognizer: SFSpeechRecognizer, through audio: AudioIO) -> Round {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        request.contextualStrings = recognizerHints
        audio.onMicrophone = { request.append($0) }
        let latest = Latest()
        let task = recognizer.recognitionTask(with: request) { result, _ in
            guard let result else { return }
            latest.update(result.bestTranscription.formattedString, final: result.isFinal)
        }
        return Round(request: request, task: task, latest: latest)
    }
}

/// Two stretches of what somebody said, run together as one.
private func joined(_ first: String, _ second: String) -> String {
    [first, second].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
}

/// The recognizer's latest words, written from its thread and read from the listening loop.
final class Latest: @unchecked Sendable {
    private let lock = NSLock()
    private var words = ""
    private var changed = Date()
    private var final = false

    func update(_ text: String, final isFinal: Bool) {
        lock.lock()
        if text != words { changed = Date() }
        words = text
        final = isFinal
        lock.unlock()
    }

    func read() -> (String, Date, Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (words, changed, final)
    }
}

/// The recognition in flight, held where the timeout can reach it to cancel.
private final class RunningTask: @unchecked Sendable {
    var task: SFSpeechRecognitionTask?
}

/// Runs its work the first time only, since a recognizer can answer and time out both.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ work: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        work()
    }
}
