import AVFoundation
import MemnoxVoiceCore
import Speech

/// One engine for both directions, with Apple's voice processing on so Memnox does not hear
/// itself. It runs only while a conversation does, so the microphone light means something.
final class AudioIO {
    let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    // A standard float format at a common rate, which AVFoundation always builds.
    let playFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    private(set) var micLevel: Float = 0
    private(set) var voiceLevel: Float = 0
    /// Every microphone buffer while listening, for the recognizer.
    var onMicrophone: ((AVAudioPCMBuffer) -> Void)?
    private var running = false

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playFormat)
    }

    func start() throws {
        guard !running else { return }
        let input = engine.inputNode
        // Echo cancellation where the hardware allows it; without it the orb still works.
        try? input.setVoiceProcessingEnabled(true)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            self?.micLevel = loudness(of: buffer)
            self?.onMicrophone?(buffer)
        }
        engine.mainMixerNode.removeTap(onBus: 0)
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            self?.voiceLevel = loudness(of: buffer)
        }
        engine.prepare()
        try engine.start()
        player.play()
        running = true
    }

    func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.mainMixerNode.removeTap(onBus: 0)
        player.stop()
        engine.stop()
        running = false
        micLevel = 0
        voiceLevel = 0
    }

    func schedule(_ buffer: AVAudioPCMBuffer, played: @escaping () -> Void) {
        if !player.isPlaying { player.play() }
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in played() }
    }

    func silence() {
        player.stop()
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

/// Speech out, through the same engine, so the orb moves with the voice it is hearing.
final class Voice: Speaker {
    private let audio: AudioIO
    private let synthesizer = AVSpeechSynthesizer()
    private var voice: AVSpeechSynthesisVoice?
    private static let voiceKey = "voiceIdentifier"
    private let lock = NSLock()
    private var outstanding = 0
    private var finished = false
    private var resume: (() -> Void)?

    init(audio: AudioIO) {
        self.audio = audio
        let chosen = UserDefaults.standard.string(forKey: Self.voiceKey)
        voice = chosen.flatMap(AVSpeechSynthesisVoice.init(identifier:)) ?? Voice.bestVoice()
    }

    var identifier: String? { voice?.identifier }

    /// The voice the person picked in setup, kept for next time.
    func choose(_ identifier: String) {
        guard let picked = AVSpeechSynthesisVoice(identifier: identifier) else { return }
        voice = picked
        UserDefaults.standard.set(identifier, forKey: Self.voiceKey)
    }

    /// One sentence in the chosen voice, with the engine started just for it.
    func preview(_ sentence: String) async {
        do { try audio.start() } catch { return }
        await speak(sentence)
        audio.stop()
    }

    /// Installed English voices, best first, since Premium and Enhanced sound the most like a person.
    static func englishVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name) }
    }

    func speak(_ sentence: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            outstanding = 0
            finished = false
            resume = { continuation.resume() }
            lock.unlock()
            DispatchQueue.main.async { [self] in
                let utterance = AVSpeechUtterance(string: sentence)
                utterance.voice = voice
                var converter: AVAudioConverter?
                synthesizer.write(utterance) { [weak self] raw in
                    guard let self, let buffer = raw as? AVAudioPCMBuffer else { return }
                    if buffer.frameLength == 0 {
                        self.markFinished()
                        return
                    }
                    if converter == nil || converter?.inputFormat != buffer.format {
                        converter = AVAudioConverter(from: buffer.format, to: self.audio.playFormat)
                    }
                    guard let converted = converter.flatMap({ convert(buffer, with: $0, to: self.audio.playFormat) }) else { return }
                    self.lock.lock()
                    self.outstanding += 1
                    self.lock.unlock()
                    self.audio.schedule(converted) { [weak self] in self?.markPlayed() }
                }
            }
        }
    }

    func stop() {
        DispatchQueue.main.async { [self] in
            synthesizer.stopSpeaking(at: .immediate)
            audio.silence()
            lock.lock()
            let done = resume
            resume = nil
            lock.unlock()
            done?()
        }
    }

    private func markFinished() {
        lock.lock()
        finished = true
        let done = outstanding == 0 ? takeResume() : nil
        lock.unlock()
        done?()
    }

    private func markPlayed() {
        lock.lock()
        outstanding -= 1
        let done = finished && outstanding == 0 ? takeResume() : nil
        lock.unlock()
        done?()
    }

    /// Called with the lock held; hands the continuation over once, so it is resumed once.
    private func takeResume() -> (() -> Void)? {
        let done = resume
        resume = nil
        return done
    }

    /// The best English voice installed; a person picks a Premium or Personal Voice in System Settings.
    private static func bestVoice() -> AVSpeechSynthesisVoice? {
        let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        return english.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: "en-US")
    }
}

private func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
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

/// Speech in, recognised on this Mac. It ends an utterance by the pause after it, and hands
/// the words on whole: nothing here looks for a keyword.
final class Ears {
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
        guard let recognizer, recognizer.isAvailable else { return nil }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        // Names this machine uses, as hints to the recognizer rather than words anything acts on.
        request.contextualStrings = ["Memnox", "Claude", "Codex", "Cursor", "kubectl", "Railway", "npm", "git push"]
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
            if !words.isEmpty, Date().timeIntervalSince(changed) > 1.1 { break }
        }
        audio.onMicrophone = nil
        request.endAudio()
        task.cancel()
        let words = latest.read().0.trimmingCharacters(in: .whitespacesAndNewlines)
        return words.isEmpty ? nil : words
    }
}

/// The recognizer's latest words, written from its thread and read from the listening loop.
private final class Latest {
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
