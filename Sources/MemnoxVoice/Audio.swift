import AVFoundation
import MemnoxVoiceCore
import Speech

/// The microphone, and only while a conversation runs, so the microphone light means something.
/// Speech goes out through the system synthesizer instead, which is the one path macOS never
/// ducks or silences, since echo cancellation on an engine turns every other sound down.
final class AudioIO {
    let engine = AVAudioEngine()
    private(set) var micLevel: Float = 0
    /// Every microphone buffer while listening, for the recognizer.
    var onMicrophone: ((AVAudioPCMBuffer) -> Void)?
    private var running = false

    func start() throws {
        guard !running else { return }
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak self] buffer, _ in
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

/// Loudness from zero to one, on a decibel scale, because that is how a voice sounds.
func loudness(of buffer: AVAudioPCMBuffer) -> Float {
    guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
    var sum: Float = 0
    for index in 0..<Int(buffer.frameLength) { sum += channel[index] * channel[index] }
    let rms = (sum / Float(buffer.frameLength)).squareRoot()
    let decibels = 20 * log10(max(rms, 0.000_01))
    return min(max((decibels + 55) / 45, 0), 1)
}

/// Speech out, through the system synthesizer, with the orb moving on every word it says.
// Unchecked because its shared state is behind `lock` and synthesizer work hops to the main queue.
final class Voice: NSObject, Speaker, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    private var voice: AVSpeechSynthesisVoice?
    private static let voiceKey = "voiceIdentifier"
    private let lock = NSLock()
    /// One waiting sentence per utterance, since the synthesizer queues them and a filler may join the queue.
    private var waiting: [ObjectIdentifier: () -> Void] = [:]
    /// Everyone waiting for the queue to empty.
    private var drainers: [() -> Void] = []
    private var lastWord = Date.distantPast

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
        let since = Float(Date().timeIntervalSince(lastWord))
        return synthesizer.isSpeaking ? max(0.25, 0.9 - since * 2.5) : 0
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
    private func enqueue(_ sentence: String, said: @escaping () -> Void) {
        diary.note("saying: \(sentence)")
        let utterance = AVSpeechUtterance(string: sentence)
        utterance.voice = voice
        // Slower than the default and a little lower, so it sounds like somebody relaxed talking rather than reading out.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.88
        utterance.pitchMultiplier = 0.96
        // A breath after each sentence, since a reply run together with no gaps sounds rushed.
        utterance.postUtteranceDelay = 0.35
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
            let all = Array(waiting.values) + drainers
            waiting.removeAll()
            drainers.removeAll()
            lock.unlock()
            all.forEach { $0() }
        }
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
            .filter { $0.language.hasPrefix("en") }
            .sorted { ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name) }
    }

    /// The best English voice installed; a person picks a Premium or Personal Voice in System Settings.
    private static func bestVoice() -> AVSpeechSynthesisVoice? {
        englishVoices().first ?? AVSpeechSynthesisVoice(language: "en-US")
    }
}

func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
    let ratio = format.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1_024
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
    /// Said when a voice was heard and no words came of it, so the person knows to say it again.
    var missed: (() -> Void)?
    private let legacy = LegacyEars()
    /// Set once the speech model is on this Mac, and cleared if it ever fails to hear a voice.
    /// Until then the older recognizer listens, so the first question never waits on a download.
    private var analyzerReady = false

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
        if #available(macOS 26, *), analyzerReady {
            let ears = AnalyzerEars()
            ears.hearing = hearing
            switch await ears.listen(through: audio, waiting: waiting) {
            case .heard(let words): return words
            case .silence: return nil
            case .unavailable:
                // Its model could not be fetched, it would not start, or it heard a voice and made no
                // words of it: the older recognizer still hears, and the person is asked once more.
                diary.note("SpeechAnalyzer unavailable, using the older recognizer")
                analyzerReady = false
                missed?()
            }
        }
        legacy.hearing = hearing
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
    private let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    /// The words so far, for the pill.
    var hearing: ((String) -> Void)?

    static func askPermission() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        let microphone = await AVCaptureDevice.requestAccess(for: .audio)
        return speech && microphone
    }

    /// The next thing said, or nil when nothing was said before the wait ran out.
    func listen(through audio: AudioIO, waiting: TimeInterval) async -> String? {
        guard let recognizer, recognizer.isAvailable else {
            diary.note("older recognizer not available: \(SFSpeechRecognizer.authorizationStatus().rawValue)")
            return nil
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        request.contextualStrings = recognizerHints
        audio.onMicrophone = { request.append($0) }

        let latest = Latest()
        let task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let result else { return }
            let words = result.bestTranscription.formattedString
            latest.update(words, final: result.isFinal)
            self?.hearing?(words)
        }
        let began = Date()
        while true {
            try? await Task.sleep(nanoseconds: 150_000_000)
            let (words, changed, final) = latest.read()
            if final { break }
            if words.isEmpty, Date().timeIntervalSince(began) > waiting { break }
            if !words.isEmpty, Date().timeIntervalSince(changed) > endOfSpeechPause(after: words) { break }
        }
        audio.onMicrophone = nil
        request.endAudio()
        task.cancel()
        let words = latest.read().0.trimmingCharacters(in: .whitespacesAndNewlines)
        return words.isEmpty ? nil : words
    }
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
