import AVFoundation
import MemnoxVoiceCore
import Speech

/// The fallback when no better English voice or recognizer locale is on this Mac.
private let fallbackLanguage = "en-US"
private let nanosecondsPerSecond: TimeInterval = 1_000_000_000

/// The microphone, and only while a conversation runs, so the microphone light means something.
/// Apple's echo cancellation runs on it, and only takes back out what this same engine plays, so
/// while it is on the voice is played here too; other apps keep their volume, since ducking is held at its least.
final class AudioIO {
    /// Replaced after a failed start, since an engine whose output unit would not initialize keeps failing.
    private(set) var engine = AVAudioEngine() {
        didSet { watchConfiguration(of: engine) }
    }
    /// Engines set aside rather than freed, since CoreAudio still calls a replaced engine's unit about a device change
    /// moments later, and an engine freed under that call crashes the app; a handful kept is a few megabytes.
    private var retired: [AVAudioEngine] = []
    private static let retiredKept = 4
    private var configurationWatch: (any NSObjectProtocol)?
    private(set) var micLevel: Float = 0
    /// Loud enough to be somebody talking rather than a room, on the same scale as `micLevel`.
    static let voiceLevel: Float = 0.45
    /// Every microphone buffer while listening, for the recognizer.
    var onMicrophone: ((AVAudioPCMBuffer) -> Void)?
    private var running = false
    /// Frames per microphone tap, about twenty milliseconds at 48 kHz.
    private static let tapBufferFrames: AVAudioFrameCount = 1024
    /// Every node here has one bus, the first.
    private static let bus: AVAudioNodeBus = 0
    /// The voice is one voice, so one channel.
    private static let voiceChannels: AVAudioChannelCount = 1
    /// Turned off only by hand, for a headset whose own microphone misbehaves under voice processing.
    static let echoCancellationKey = "echoCancellation"
    /// The voice's sentences while the microphone is open, played here so echo cancellation knows what to remove.
    private let speech = AVAudioPlayerNode()
    private var speechFormat: AVAudioFormat?
    private let speechLock = NSLock()
    private var speechLoudness: Float = 0
    /// Whether echo cancellation is running now, which is when the voice is played through this engine.
    private(set) var cancelsEcho = false

    private static var wantsEchoCancellation: Bool {
        UserDefaults.standard.object(forKey: echoCancellationKey) as? Bool ?? true
    }

    /// The microphone and speakers voice processing would not start on, so it is tried again once either changes.
    private static var failedOn: AudioRoute?
    /// Set by the first buffer after a start, read by the watchdog that catches a start which delivers none.
    private let heardLock = NSLock()
    private var heardSinceStart = false
    private var silentStartWatch: DispatchWorkItem?
    /// Long enough for the first buffer of any microphone, and short enough that nobody notices the restart.
    private static let silentStartAfter: TimeInterval = 2.5

    init() {
        watchConfiguration(of: engine)
    }

    /// The engine stops itself when the microphone or speakers change, and a player started on a stopped engine
    /// raises an Objective C exception that corrupts the main actor, so it is started again here instead.
    private func watchConfiguration(of engine: AVAudioEngine) {
        if let configurationWatch { NotificationCenter.default.removeObserver(configurationWatch) }
        configurationWatch = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.configurationChanged()
        }
    }

    private func configurationChanged() {
        guard running, !engine.isRunning else { return }
        let withEcho = cancelsEcho
        diary.note("the audio devices changed, so the microphone is opened again")
        tearDown(keepingVoiceProcessing: withEcho)
        do {
            try begin(cancellingEcho: withEcho)
        } catch {
            diary.note("the microphone would not start again after the devices changed: \(error)")
            running = false
        }
    }

    /// The microphone on, with echo cancellation where this Mac's audio allows it and without where it does not,
    /// since a microphone that never starts is far worse than one that hears the voice's own echo.
    func start() throws {
        guard !running else { return }
        let route = AudioRoute.current()
        do {
            try begin(cancellingEcho: Self.wantsEchoCancellation && Self.failedOn != route)
        } catch where cancelsEcho {
            // Once more on a fresh engine, which is what clears a voice processing unit left half set up.
            fresh()
            do {
                try begin(cancellingEcho: true)
            } catch where cancelsEcho {
                diary.note("echo cancellation would not start on \(route.described), so the microphone runs without it until the microphone or speakers change: \(error)")
                Self.failedOn = route
                fresh()
                try begin(cancellingEcho: false)
            }
        }
        running = true
        diary.note("microphone on\(cancelsEcho ? " with echo cancellation" : ""): \(engine.inputNode.outputFormat(forBus: Self.bus))")
        if cancelsEcho { watchForSilentStart(on: route) }
    }

    /// Voice processing on some devices starts without error and then never delivers a buffer, so a start that
    /// stays silent is taken as failed on this route and the microphone is opened again plainly.
    private func watchForSilentStart(on route: AudioRoute) {
        silentStartWatch?.cancel()
        let watch = DispatchWorkItem { [weak self] in
            guard let self, self.running, self.cancelsEcho, !self.heard else { return }
            diary.note("echo cancellation started on \(route.described) but the microphone delivered nothing, so it runs without it until the microphone or speakers change")
            Self.failedOn = route
            self.fresh()
            do {
                try self.begin(cancellingEcho: false)
                diary.note("microphone on: \(self.engine.inputNode.outputFormat(forBus: Self.bus))")
            } catch {
                diary.note("the microphone would not start without echo cancellation either: \(error)")
                self.running = false
            }
        }
        silentStartWatch = watch
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.silentStartAfter, execute: watch)
    }

    private var heard: Bool {
        heardLock.lock()
        defer { heardLock.unlock() }
        return heardSinceStart
    }

    private func begin(cancellingEcho: Bool) throws {
        let input = engine.inputNode
        // Left on by a start that failed, it fails every start after, so a plain start switches it off first.
        if !cancellingEcho, input.isVoiceProcessingEnabled { try? input.setVoiceProcessingEnabled(false) }
        // Before the tap, since voice processing changes the format the microphone delivers.
        cancelsEcho = cancellingEcho && voiceProcessing(on: input)
        input.removeTap(onBus: Self.bus)
        heardLock.lock()
        heardSinceStart = false
        heardLock.unlock()
        input.installTap(onBus: Self.bus, bufferSize: Self.tapBufferFrames, format: input.outputFormat(forBus: Self.bus)) { [weak self] buffer, _ in
            guard let self else { return }
            self.heardLock.lock()
            self.heardSinceStart = true
            self.heardLock.unlock()
            let heard = AudioIO.oneChannel(of: buffer)
            self.micLevel = loudness(of: heard)
            self.onMicrophone?(heard)
        }
        if cancelsEcho {
            outputForVoiceProcessing()
            attachSpeech()
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        guard running else { return }
        silentStartWatch?.cancel()
        silentStartWatch = nil
        // Voice processing is left on for the next start, since switching it off and on rebuilds the audio unit
        // every time the orb closes, and each rebuild is another chance for CoreAudio to call a unit that is gone.
        tearDown(keepingVoiceProcessing: cancelsEcho)
        running = false
        micLevel = 0
    }

    /// Everything begin set up taken down, so the next start begins clean.
    private func tearDown(keepingVoiceProcessing: Bool = false) {
        // A node never attached to the engine throws on stop and removeTap, and a throw through Swift
        // leaves the main actor's bookkeeping broken, so the app crashes at its next main-thread check.
        if speech.engine != nil {
            speech.stop()
            speech.removeTap(onBus: Self.bus)
        }
        engine.inputNode.removeTap(onBus: Self.bus)
        engine.stop()
        if speech.engine != nil { engine.detach(speech) }
        if !keepingVoiceProcessing, engine.inputNode.isVoiceProcessingEnabled {
            try? engine.inputNode.setVoiceProcessingEnabled(false)
        }
        cancelsEcho = false
    }

    /// Everything torn down and a new engine in its place, the old one kept a while for CoreAudio's late calls.
    private func fresh() {
        tearDown()
        retired.append(engine)
        if retired.count > Self.retiredKept { retired.removeFirst() }
        engine = AVAudioEngine()
    }

    /// The mixer joined to the speakers in the format voice processing gives them, since a join made in the
    /// format from before it was on is what fails the output unit's start with -10875.
    private func outputForVoiceProcessing() {
        let output = engine.outputNode
        let format = output.inputFormat(forBus: Self.bus)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }
        engine.connect(engine.mainMixerNode, to: output, format: format)
    }

    private func voiceProcessing(on input: AVAudioInputNode) -> Bool {
        do {
            if !input.isVoiceProcessingEnabled { try input.setVoiceProcessingEnabled(true) }
            // Without this macOS turns every other app down while the microphone is open.
            input.voiceProcessingOtherAudioDuckingConfiguration = AVAudioVoiceProcessingOtherAudioDuckingConfiguration(
                enableAdvancedDucking: false, duckingLevel: .min)
            return true
        } catch {
            diary.note("echo cancellation could not start, so its own voice is told apart by words: \(error.localizedDescription)")
            return false
        }
    }

    private func attachSpeech() {
        if speech.engine == nil { engine.attach(speech) }
        let rate = engine.mainMixerNode.outputFormat(forBus: Self.bus).sampleRate
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: Self.voiceChannels) else { return }
        engine.connect(speech, to: engine.mainMixerNode, format: format)
        speechFormat = format
        speech.removeTap(onBus: Self.bus)
        speech.installTap(onBus: Self.bus, bufferSize: Self.tapBufferFrames, format: format) { [weak self] buffer, _ in
            self?.setSpeechLoudness(loudness(of: buffer))
        }
    }

    /// One sentence played through this engine, `done` once it has been heard or stopped; false when it cannot be.
    func play(_ buffers: [AVAudioPCMBuffer], start: Bool, done: @escaping () -> Void) -> Bool {
        // Scheduling on a detached player or starting one on a stopped engine raises an exception, not an error.
        guard running, cancelsEcho, engine.isRunning, speech.engine != nil, let format = speechFormat, !buffers.isEmpty
        else { return false }
        let ready = buffers.compactMap { Self.fitted($0, to: format) }
        guard ready.count == buffers.count, let last = ready.last else { return false }
        for buffer in ready.dropLast() { speech.scheduleBuffer(buffer) }
        speech.scheduleBuffer(last, completionCallbackType: .dataPlayedBack) { _ in done() }
        if start, !speech.isPlaying { speech.play() }
        return true
    }

    func pauseSpeech() {
        if speech.engine != nil { speech.pause() }
    }

    func resumeSpeech() {
        if running, cancelsEcho, engine.isRunning, speech.engine != nil { speech.play() }
    }

    /// Everything scheduled dropped, which calls each sentence's `done`.
    func stopSpeech() {
        if speech.engine != nil { speech.stop() }
    }

    /// How loud the voice is playing through this engine, on the microphone's scale.
    var speechLevel: Float {
        speechLock.lock()
        defer { speechLock.unlock() }
        return speechLoudness
    }

    private func setSpeechLoudness(_ level: Float) {
        speechLock.lock()
        speechLoudness = level
        speechLock.unlock()
    }

    /// The microphone as one channel: voice processing hands several to some Macs, and the recognizers that
    /// take its buffers as they come hear nothing in a format they do not expect.
    static func oneChannel(of buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        let format = buffer.format
        guard format.channelCount > voiceChannels, !format.isInterleaved,
              let single = AVAudioFormat(commonFormat: format.commonFormat, sampleRate: format.sampleRate,
                                         channels: voiceChannels, interleaved: false),
              let out = AVAudioPCMBuffer(pcmFormat: single, frameCapacity: buffer.frameLength),
              let source = buffer.floatChannelData, let target = out.floatChannelData
        else { return buffer }
        out.frameLength = buffer.frameLength
        target[firstChannel].update(from: source[firstChannel], count: Int(buffer.frameLength))
        return out
    }

    /// The channel the voice is on when there are several: the built-in microphone's own.
    private static let firstChannel = 0

    private static func fitted(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else { return nil }
        return convert(buffer, with: converter, to: format)
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
    /// The microphone's engine, which plays the voice while it is open so echo cancellation can take it back out.
    weak var route: AudioIO?
    /// Set while a sentence plays through that engine, numbered so a stopped one's late callback ends nothing newer.
    private var routed: Int?
    private var routedCount = 0
    /// Renders the system voice into audio rather than speaking it, so it can be played through that engine.
    private let writer = AVSpeechSynthesizer()
    /// Held quiet while the person may be cutting in, so a sentence that comes up meanwhile waits too.
    private var paused = false
    /// Every second ever spent paused, and when the pause under way began, so a sentence's deadline moves by its pauses.
    private var pausedTotal: TimeInterval = 0
    private var pausedSince: Date?
    /// A breath between sentences, long enough that one never runs into the next.
    private static let breath: TimeInterval = 0.26
    /// This long past a sentence's own length, a finish that never came is taken as done, so a turn never hangs speaking.
    private static let playbackGrace: TimeInterval = 3
    /// Pauses shorter than this are inside the grace already, and the least a held sentence waits before it is looked at again.
    private static let pauseSlack: TimeInterval = 0.5

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
        // A novelty voice saved by an earlier version is dropped, so Zarvox never stands in for Kokoro.
        voice = chosen.flatMap(AVSpeechSynthesisVoice.init(identifier:)).flatMap { $0.isNovelty ? nil : $0 } ?? Voice.bestVoice()
        super.init()
        synthesizer.delegate = self
    }

    var identifier: String? { voice?.identifier }

    /// How loud the orb should look while speaking: a pulse on each word, easing away between words.
    var level: Float {
        lock.lock()
        defer { lock.unlock() }
        if paused { return 0 }
        if routed != nil { return max(route?.speechLevel ?? 0, Meter.speakingFloor) }
        if let player, player.isPlaying {
            player.updateMeters()
            return min(max((player.averagePower(forChannel: 0) - Meter.quietestPower) / Meter.powerSpan, Meter.speakingFloor), 1)
        }
        let since = Float(Date().timeIntervalSince(lastWord))
        return synthesizer.isSpeaking ? max(Meter.speakingFloor, Meter.wordPeak - since * Meter.easePerSecond) : 0
    }

    /// How loud its own voice is playing right now on the microphone's scale, zero in the hush between words,
    /// so the person talking over it can be told from its echo. The system voice reports no level, so it reads as loud.
    var playingLevel: Float {
        lock.lock()
        defer { lock.unlock() }
        if paused { return 0 }
        if routed != nil { return route?.speechLevel ?? 0 }
        if let player, player.isPlaying {
            player.updateMeters()
            return min(max((player.averagePower(forChannel: 0) - quietestDecibels) / decibelSpan, 0), 1)
        }
        return synthesizer.isSpeaking ? Meter.wordPeak : 0
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

    /// Set by the person through `VoiceMute` to keep Memnox quiet everywhere; what it would have said still shows.
    static let mutedKey = "voiceMuted"
    static var muted: Bool { UserDefaults.standard.bool(forKey: mutedKey) }

    /// Main queue order is call order, so sentences are said in the order they were given.
    private func enqueue(_ written: String, said: @escaping () -> Void) {
        // Muted, the sentence counts as said at once, so a turn waiting on it moves on as if it had been spoken.
        if Self.muted {
            diary.note("muted, not saying: \(written)")
            DispatchQueue.main.async(execute: said)
            return
        }
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

    private func utterance(_ sentence: String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: sentence)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Pacing.rateScale
        utterance.pitchMultiplier = Pacing.pitch
        utterance.postUtteranceDelay = Pacing.afterSentence
        utterance.prefersAssistiveTechnologySettings = false
        return utterance
    }

    /// The system voice through the microphone's engine while echo cancellation runs, else straight out.
    private func enqueueSystem(_ sentence: String, said: @escaping () -> Void) {
        if route?.cancelsEcho == true {
            enqueueClip(sentence, said: said) { [weak self] in
                guard let buffers = await self?.rendered(sentence) else { return nil }
                return .buffers(buffers)
            }
            return
        }
        speakDirectly(sentence, said: said)
    }

    private func speakDirectly(_ sentence: String, said: @escaping () -> Void) {
        let utterance = utterance(sentence)
        lock.lock()
        waiting[ObjectIdentifier(utterance)] = said
        lock.unlock()
        DispatchQueue.main.async { [self] in synthesizer.speak(utterance) }
    }

    /// Quiet at once, mid word, without letting go of what is left to say.
    func hush() {
        DispatchQueue.main.async { [self] in
            lock.lock()
            paused = true
            if pausedSince == nil { pausedSince = Date() }
            let playing = player
            let throughEngine = routed != nil
            lock.unlock()
            playing?.pause()
            if throughEngine { route?.pauseSpeech() }
            synthesizer.pauseSpeaking(at: .immediate)
        }
    }

    /// Carries on from the word it paused on.
    func carryOn() {
        DispatchQueue.main.async { [self] in
            lock.lock()
            let wasHushed = paused
            paused = false
            endPause()
            let playing = player
            let throughEngine = routed != nil
            lock.unlock()
            guard wasHushed else { return }
            if let playing, !playing.play() { finishPlayer() }
            if throughEngine { route?.resumeSpeech() }
            synthesizer.continueSpeaking()
        }
    }

    func stop() {
        DispatchQueue.main.async { [self] in
            synthesizer.stopSpeaking(at: .immediate)
            lock.lock()
            paused = false
            endPause()
            engineGeneration += 1
            let playing = player
            lock.unlock()
            playing?.stop()
            route?.stopSpeech()
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

    /// One sentence's sound: a file from a voice engine, or the system voice rendered for the microphone's engine.
    private enum Clip {
        case data(Data)
        case buffers([AVAudioPCMBuffer])
    }

    private func enqueueEngine(_ sentence: String, with engine: VoiceEngine, said: @escaping () -> Void) {
        enqueueClip(sentence, said: said) {
            do { return .data(try await engine.audio(for: sentence)) } catch {
                // Cancelled means somebody talked over it, which is not a failure worth noting.
                if (error as? URLError)?.code != .cancelled, !(error is CancellationError) {
                    diary.note("\(engine.name) did not voice it, so the system voice does: \(error.localizedDescription)")
                }
                return nil
            }
        }
    }

    /// Fetched at once, so the next sentence is ready while this one plays, and played in order.
    private func enqueueClip(_ sentence: String, said: @escaping () -> Void, sound: @escaping () async -> Clip?) {
        let token = NSObject()
        let fetch = Task { await sound() }
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
            if let clip = await fetch.value, await self.play(clip, generation: generation) {
                try? await Task.sleep(nanoseconds: UInt64(Self.breath * nanosecondsPerSecond))
            } else if self.inGeneration(generation) {
                // Said here rather than queued, since a queued sentence would wait behind this one forever.
                await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                    self.speakDirectly(sentence) { done.resume() }
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

    /// Through the microphone's engine while echo cancellation runs, else straight out; false when it could not be played.
    private func play(_ clip: Clip, generation: Int) async -> Bool {
        if route?.cancelsEcho == true {
            let buffers: [AVAudioPCMBuffer]?
            switch clip {
            case .data(let data): buffers = Self.pcm(data).map { [$0] }
            case .buffers(let rendered): buffers = rendered
            }
            if let buffers, await playThroughEngine(buffers, generation: generation) { return true }
        }
        guard case .data(let data) = clip else { return false }
        await play(data, generation: generation)
        return true
    }

    private func playThroughEngine(_ buffers: [AVAudioPCMBuffer], generation: Int) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            DispatchQueue.main.async { [self] in
                guard inGeneration(generation), let route else {
                    continuation.resume(returning: inGeneration(generation) ? false : true)
                    return
                }
                lock.lock()
                routedCount += 1
                let mine = routedCount
                routed = mine
                playerDone = { continuation.resume(returning: true) }
                // A sentence that comes up while paused is left ready, and resume starts it.
                let held = paused
                lock.unlock()
                let scheduled = route.play(buffers, start: !held) { [weak self] in
                    DispatchQueue.main.async { self?.finishRouted(mine) }
                }
                if !scheduled {
                    lock.lock()
                    routed = nil
                    playerDone = nil
                    lock.unlock()
                    continuation.resume(returning: false)
                    return
                }
                let length = buffers.reduce(0) { $0 + Double($1.frameLength) / $1.format.sampleRate }
                finishAt(length) { [weak self] in self?.routed == mine }
            }
        }
    }

    /// Ends the sentence playing through the engine, unless a newer one has started since.
    private func finishRouted(_ which: Int) {
        lock.lock()
        let current = routed == which
        lock.unlock()
        if current { finishPlayer() }
    }

    /// A voice engine's file as audio the microphone's engine can play, read through a file since that is what reads every format.
    private static func pcm(_ data: Data) -> AVAudioPCMBuffer? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("memnox-voice-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        guard (try? data.write(to: url)) != nil,
              let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil
        else { return nil }
        return buffer
    }

    /// The system voice's sentence as audio, gathered until it says it is done; nil when it rendered nothing.
    private func rendered(_ sentence: String) async -> [AVAudioPCMBuffer]? {
        let utterance = utterance(sentence)
        let gathered = Gathered()
        return await withCheckedContinuation { (continuation: CheckedContinuation<[AVAudioPCMBuffer]?, Never>) in
            DispatchQueue.main.async { [self] in
                writer.write(utterance) { buffer in
                    guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                    if let all = gathered.add(pcm) { continuation.resume(returning: all.isEmpty ? nil : all) }
                }
            }
        }
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
                let held = paused
                lock.unlock()
                finishAt(player.duration) { [weak self] in self?.player === player }
                // A sentence that comes up while paused is left ready, and resume starts it.
                if held { return }
                if !player.play() { finishPlayer() }
            }
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        finishPlayer()
    }

    /// Called with the lock held.
    private func endPause() {
        if let since = pausedSince { pausedTotal += Date().timeIntervalSince(since) }
        pausedSince = nil
    }

    /// Called with the lock held: all the time spent paused so far, the pause under way included.
    private func heldSoFar() -> TimeInterval {
        pausedTotal + (pausedSince.map { Date().timeIntervalSince($0) } ?? 0)
    }

    /// Ends the sentence once it should long have finished, unless a newer one took its place. Time spent paused
    /// is added to the wait, since a pause that already ended still left that much of the sentence to play.
    private func finishAt(_ length: TimeInterval, isCurrent: @escaping () -> Bool) {
        lock.lock()
        let heldAtStart = heldSoFar()
        lock.unlock()
        finishAt(after: length + Self.playbackGrace, heldAtStart: heldAtStart, isCurrent: isCurrent)
    }

    private func finishAt(after wait: TimeInterval, heldAtStart: TimeInterval, isCurrent: @escaping () -> Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self else { return }
            lock.lock()
            let current = isCurrent()
            let held = paused
            let heldSince = heldSoFar() - heldAtStart
            lock.unlock()
            guard current else { return }
            if held || heldSince > Self.pauseSlack {
                finishAt(after: max(heldSince, Self.pauseSlack), heldAtStart: heldAtStart + heldSince, isCurrent: isCurrent)
                return
            }
            diary.note("a sentence never said it finished, so it was ended to keep the conversation going")
            finishPlayer()
        }
    }

    private func finishPlayer() {
        lock.lock()
        let done = playerDone
        playerDone = nil
        player = nil
        routed = nil
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

    /// Installed English voices, best first and then by name, since Premium and Enhanced sound the
    /// most like a person; novelty voices such as Zarvox and Bells are left out because they cannot hold a conversation.
    static func englishVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(englishPrefix) && !$0.isNovelty }
            .sorted { $0.quality.rawValue != $1.quality.rawValue ? $0.quality.rawValue > $1.quality.rawValue : $0.name < $1.name }
    }

    /// The best English voice installed; a person picks a Premium or Personal Voice in System Settings.
    private static func bestVoice() -> AVSpeechSynthesisVoice? {
        englishVoices().first ?? AVSpeechSynthesisVoice(language: fallbackLanguage)
    }
}

private extension AVSpeechSynthesisVoice {
    /// The robots and sound effects macOS ships beside its real voices.
    var isNovelty: Bool { voiceTraits.contains(.isNoveltyVoice) }
}

/// The buffers the system voice renders a sentence into, handed on once, when its empty last buffer arrives.
private final class Gathered: @unchecked Sendable {
    private let lock = NSLock()
    private var buffers: [AVAudioPCMBuffer] = []
    private var finished = false
    /// The system voice ends a sentence with an empty buffer.
    private static let endOfSentence: AVAudioFrameCount = 0

    /// Every buffer so far once the sentence is over, nil until then and after.
    func add(_ buffer: AVAudioPCMBuffer) -> [AVAudioPCMBuffer]? {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return nil }
        if buffer.frameLength > Self.endOfSentence {
            buffers.append(buffer)
            return nil
        }
        finished = true
        return buffers
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
    /// How long the older recognizer waits for a first word after the analyzer missed one: they were just talking,
    /// so a repeat comes at once, and waiting the whole turn's wait left them in silence for twenty seconds.
    private static let sayAgainSeconds: TimeInterval = 5

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

    /// Set to end the listen now with nothing heard, for a rule held down while it was listening.
    let cut = Flag()

    /// Each change in the words while one listen runs, for dictation typed as it is spoken; nil otherwise.
    var revising: ((String) -> Void)?

    /// The next thing said; with `holding`, everything said until it says the keys were let go, and `tail` after it,
    /// so the last word is not cut off as the key comes up. `hints` are words this listen in particular may hear.
    func listen(
        through audio: AudioIO, waiting: TimeInterval, holding: (() -> Bool)? = nil,
        tail: TimeInterval = 0, hints: [String] = []
    ) async -> String? {
        let hearing = self.hearing
        let revising = self.revising
        let heard: (String) -> Void = { words in
            hearing?(words)
            revising?(words)
        }
        // A held rule listens whatever was asked before it; any other listen honours a cut asked for already.
        if holding != nil { _ = cut.take() } else if cut.take() { return nil }
        if !analyzerReady, let retry = retryAt, Date() >= retry {
            analyzerReady = true
            retryAt = nil
            misses = 0
            diary.note("trying SpeechAnalyzer again")
        }
        var missedOne = false
        if #available(macOS 26, *), analyzerReady {
            let ears = AnalyzerEars()
            ears.hearing = heard
            ears.guessing = guessing
            lastWordAt = nil
            switch await ears.listen(through: audio, waiting: waiting, holding: holding, cut: holding == nil ? cut : nil,
                                     tail: tail, hints: hints) {
            case .heard(let words):
                misses = 0
                lastWordAt = ears.lastWordAt
                return words
            case .silence: return nil
            case .unavailable(let recorded):
                // The older recognizer hears this one; only a run of them sets the better one aside, for a while.
                misses += 1
                missedOne = true
                // What they already said is heard from the recording, so they never have to say it twice.
                if let words = await legacy.transcribe(recorded, hints: hints) {
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
        legacy.hearing = heard
        legacy.guessing = guessing
        let words = await legacy.listen(through: audio, waiting: missedOne ? min(waiting, Self.sayAgainSeconds) : waiting,
                                        holding: holding, cut: holding == nil ? cut : nil, tail: tail, hints: hints)
        diary.note("older recognizer heard \(words ?? "nothing")")
        return words
    }
}

/// The names in no dictionary that people say most, misheard as "Lenox", "vehicle code", "eye term" and "guitar push" without a hint.
let firstRecognizerHints = [
    "Memnox", "Claude Code", "Codex", "Cursor", "VS Code", "Visual Studio Code", "iTerm", "Hermes", "ChatGPT",
    "git status", "git push", "npm", "kubectl", "Railway", "Vercel",
    // The person's own tools, heard as "get up", "heat up" and "linen" when they come after the hundredth hint.
    "GitHub", "Linear", "Slack", "pull request", "repository", "ticket", "Jira", "Notion", "Gmail",
]

/// Names this machine uses, as hints to the recognizer rather than words anything acts on.
/// Joined by the daemon's own list at launch, since it knows the agents and CLIs actually here.
nonisolated(unsafe) var recognizerHints = firstRecognizerHints

/// The recognizer before macOS 26.
final class LegacyEars {
    private let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: fallbackLanguage))
    /// A recording of a few seconds is read on this Mac in about a second; past this the person is waiting.
    private static let transcribeTimeout: TimeInterval = 4
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
    func transcribe(_ buffers: [AVAudioPCMBuffer], hints: [String] = []) async -> String? {
        guard let recognizer, recognizer.isAvailable, !buffers.isEmpty else { return nil }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.contextualStrings = hints + recognizerHints
        useVocabulary(in: request, with: recognizer)
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
    func listen(
        through audio: AudioIO, waiting: TimeInterval, holding: (() -> Bool)? = nil, cut: Flag? = nil,
        tail: TimeInterval = 0, hints: [String] = []
    ) async -> String? {
        guard let recognizer, recognizer.isAvailable else {
            diary.note("older recognizer not available: \(SFSpeechRecognizer.authorizationStatus().rawValue)")
            return nil
        }
        let began = Date()
        var settled = ""
        var lastWord = began
        var lastVoice: Date?
        var meter = VoiceMeter()
        var guessed = ""
        var letGoAt: Date?
        while true {
            let round = startRound(with: recognizer, through: audio, hints: hints)
            var finished = false
            var final = false
            while !finished {
                try? await Task.sleep(nanoseconds: UInt64(Self.pollSeconds * nanosecondsPerSecond))
                let (words, changed, isFinal) = round.latest.read()
                if !words.isEmpty { lastWord = max(lastWord, changed) }
                if meter.hear(audio.micLevel) { lastVoice = Date() }
                let all = joinedSpeech(settled, words)
                hearing?(all)
                if cut?.take() == true {
                    audio.onMicrophone = nil
                    round.request.endAudio()
                    round.task.cancel()
                    return nil
                }
                if let holding {
                    // The tail after the key comes up catches the last word, and is none for a held rule.
                    if letGoAt == nil, !holding() { letGoAt = Date() }
                    finished = letGoAt.map { Date().timeIntervalSince($0) >= tail } ?? false
                } else {
                    if all.isEmpty, Date().timeIntervalSince(began) > waiting { finished = true }
                    if !all.isEmpty, quietFor(now: Date(), lastWord: lastWord, lastVoice: lastVoice) > endOfSpeechPause(after: all) { finished = true }
                }
                if !finished, holding == nil, all != guessed, mayGuess(all, pausedFor: Date().timeIntervalSince(lastWord)) {
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

    private func startRound(with recognizer: SFSpeechRecognizer, through audio: AudioIO, hints: [String]) -> Round {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        request.contextualStrings = hints + recognizerHints
        useVocabulary(in: request, with: recognizer)
        audio.onMicrophone = { request.append($0) }
        let latest = Latest()
        let task = recognizer.recognitionTask(with: request) { result, _ in
            guard let result else { return }
            latest.update(result.bestTranscription.formattedString, final: result.isFinal)
        }
        return Round(request: request, task: task, latest: latest)
    }
}

/// The model trained on the agents' names, when it is built in this recognizer's language; it only runs on this Mac.
private func useVocabulary(in request: SFSpeechAudioBufferRecognitionRequest, with recognizer: SFSpeechRecognizer) {
    guard let trained = Vocabulary.trained, recognizer.supportsOnDeviceRecognition,
          recognizer.locale.identifier == Vocabulary.locale.identifier else { return }
    request.requiresOnDeviceRecognition = true
    request.customizedLanguageModel = trained
}

/// Two stretches of what somebody said, run together as one.

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
