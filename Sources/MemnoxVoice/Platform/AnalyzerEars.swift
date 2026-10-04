import AVFoundation
import MemnoxVoiceCore
import Speech

/// How one listen ended: words, nothing said in time, or a recognizer that could not start.
enum Listened {
    case heard(String)
    case silence
    /// With what the microphone caught, so a voice the analyzer missed can still be heard by another.
    case unavailable([AVAudioPCMBuffer])
}

/// Apple's SpeechAnalyzer, on macOS 26 and later: on this Mac, streaming, and better at the
/// words people use about their agents. Its language model downloads the first time, once.
@available(macOS 26, *)
final class AnalyzerEars {
    var hearing: ((String) -> Void)?
    /// The words so far at a pause, so the answer can start before the pause ends what they said.
    var guessing: ((String) -> Void)?
    /// When the last word changed, which is when the person stopped talking.
    private(set) var lastWordAt: Date?

    /// Fetches the speech model ahead of time, at launch, so the first question is not spent downloading.
    static func prepare() async -> Bool {
        let transcriber = SpeechTranscriber(
            locale: await locale(),
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        let ready = await installed([transcriber])
        diary.note("speech model \(ready ? "ready" : "unavailable")")
        return ready
    }

    private static func locale() async -> Locale {
        await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) ?? Locale(identifier: fallbackLocale)
    }

    /// The transcriber's language when the Mac's own is not one it supports.
    private static let fallbackLocale = "en-US"
    /// How often the words and the level are looked at.
    private static let pollSeconds: TimeInterval = 0.15
    private static let nanosecondsPerSecond: TimeInterval = 1_000_000_000

    /// The kinds of transcriber whose model is known to be on this Mac, so later listens skip asking the asset inventory again.
    nonisolated(unsafe) private static var modelsReady: Set<String> = []

    /// The next thing said, nothing when the wait ran out, or unavailable when it could not start.
    /// With `holding`, it listens for exactly as long as that says the keys are down, and no pause ends it.
    func listen(through audio: AudioIO, waiting: TimeInterval, holding: (() -> Bool)? = nil, cut: Flag? = nil) async -> Listened {
        // Heard from the first buffer, before the analyzer has loaded, so the first word is never lost to a cold start.
        let recording = Recording()
        let early = Feeder()
        audio.onMicrophone = { buffer in
            recording.keep(buffer)
            early.take(buffer)
        }
        let transcriber = await Self.transcriber()
        let kind = String(describing: type(of: transcriber.module))
        let ready = Self.modelsReady.contains(kind) ? true : await Self.installed([transcriber.module])
        guard ready,
              let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber.module])
        else {
            // The older recognizer listens afresh, since a fraction of a second recorded holds nothing worth reading.
            audio.onMicrophone = nil
            return .unavailable([])
        }
        Self.modelsReady.insert(kind)

        let analyzer = SpeechAnalyzer(modules: [transcriber.module])
        // Loaded before the first word, rather than while the person is already speaking.
        try? await analyzer.prepareToAnalyze(in: format)
        let context = AnalysisContext()
        context.contextualStrings[.general] = recognizerHints
        try? await analyzer.setContext(context)

        let (input, feed) = AsyncStream<AnalyzerInput>.makeStream()
        var converter: AVAudioConverter?
        let counts = Counts()
        let send: (AVAudioPCMBuffer) -> Void = { buffer in
            if converter == nil || converter?.inputFormat != buffer.format {
                converter = AVAudioConverter(from: buffer.format, to: format)
            }
            guard let converter, let converted = convert(buffer, with: converter, to: format) else {
                counts.dropped()
                return
            }
            counts.fed()
            feed.yield(AnalyzerInput(buffer: converted))
        }
        // What was said while the analyzer loaded goes first, then every buffer straight through.
        early.open(send)

        let heard = Heard()
        let reading = Task { [weak self] in
            do {
                for try await (text, final) in transcriber.results {
                    let words = heard.take(text, final: final)
                    self?.hearing?(words)
                }
            } catch {
                // The analyzer finishing or failing both end the listening; the words so far stand.
            }
        }
        do {
            try await analyzer.start(inputSequence: input)
        } catch {
            audio.onMicrophone = nil
            feed.finish()
            reading.cancel()
            diary.note("SpeechAnalyzer would not start: \(error)")
            return .unavailable([])
        }

        let began = Date()
        var loudest: Float = 0
        var lastVoice: Date?
        var guessed = ""
        while true {
            try? await Task.sleep(nanoseconds: UInt64(Self.pollSeconds * Self.nanosecondsPerSecond))
            loudest = max(loudest, audio.micLevel)
            if audio.micLevel > AudioIO.voiceLevel { lastVoice = Date() }
            let (words, changed) = heard.read()
            // Cut short for a rule held down meanwhile: nothing of this listen is answered.
            if cut?.take() == true {
                audio.onMicrophone = nil
                feed.finish()
                reading.cancel()
                return .silence
            }
            if let holding {
                // Let go is the end of it, at once, which is what makes a held rule instant.
                if !holding() { break }
                continue
            }
            if words.isEmpty, Date().timeIntervalSince(began) > waiting { break }
            if !words.isEmpty, quietFor(now: Date(), lastWord: changed, lastVoice: lastVoice) > endOfSpeechPause(after: words) { break }
            if words != guessed, mayGuess(words, pausedFor: Date().timeIntervalSince(changed)) {
                guessed = words
                guessing?(words)
            }
        }
        audio.onMicrophone = nil
        feed.finish()
        lastWordAt = heard.read().1
        diary.note("microphone: \(counts.summary)")
        try? await analyzer.finalizeAndFinishThroughEndOfInput()
        await reading.value
        let words = heard.read().0.trimmingCharacters(in: .whitespacesAndNewlines)
        diary.note("SpeechAnalyzer heard \(words.isEmpty ? "nothing" : words)")
        if words.isEmpty, loudest > AudioIO.voiceLevel {
            // The microphone heard a voice and no word came back: the analyzer is not working here.
            diary.note("heard a voice at level \(loudest) and no words")
            return .unavailable(recording.buffers)
        }
        if !words.isEmpty, !soundedLikeSpeech(loudest: loudest) {
            diary.note("dropped words from a listen too quiet for speech: \(words)")
            return .silence
        }
        return words.isEmpty ? .silence : .heard(words)
    }

    /// The dictation model taught the agents' names once that model is built, since only dictation takes
    /// a trained model; the general transcriber until then, which only has the hints to go on.
    private static func transcriber() async -> Transcriber {
        if let trained = Vocabulary.trained {
            let dictation = DictationTranscriber(
                locale: Vocabulary.locale,
                contentHints: [.shortForm, .customizedLanguage(modelConfiguration: trained)],
                transcriptionOptions: [.punctuation],
                reportingOptions: [.volatileResults, .frequentFinalization],
                attributeOptions: []
            )
            let results = AsyncThrowingStream<(String, Bool), Error> { continuation in
                let reading = Task {
                    do {
                        for try await result in dictation.results { continuation.yield((String(result.text.characters), result.isFinal)) }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in reading.cancel() }
            }
            return Transcriber(module: dictation, results: results)
        }
        // Fast results put each word on screen as it is spoken rather than once the recognizer is sure of it.
        let general = SpeechTranscriber(
            locale: await locale(),
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: []
        )
        let results = AsyncThrowingStream<(String, Bool), Error> { continuation in
            let reading = Task {
                do {
                    for try await result in general.results { continuation.yield((String(result.text.characters), result.isFinal)) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in reading.cancel() }
        }
        return Transcriber(module: general, results: results)
    }

    /// The model for this language, fetched the first time and kept by the system after that.
    private static func installed(_ modules: [any SpeechModule]) async -> Bool {
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                try await request.downloadAndInstall()
            }
            return true
        } catch {
            diary.note("speech model not installed: \(error)")
            return false
        }
    }
}

/// One of the two transcribers, with its words and whether each is final, read the same way whichever it is.
@available(macOS 26, *)
private struct Transcriber {
    let module: any SpeechModule
    let results: AsyncThrowingStream<(String, Bool), Error>
}

/// The microphone as it was heard, copied, since the engine reuses a tap's buffer once the block returns.
/// Capped at half a minute, which is longer than anybody talks to it in one breath.
private final class Recording: @unchecked Sendable {
    private let lock = NSLock()
    private var kept: [AVAudioPCMBuffer] = []
    private var frames: AVAudioFrameCount = 0
    private static let mostSeconds: Double = 30

    func keep(_ buffer: AVAudioPCMBuffer) {
        guard let copy = copied(buffer) else { return }
        lock.lock()
        defer { lock.unlock() }
        guard Double(frames) < buffer.format.sampleRate * Self.mostSeconds else { return }
        kept.append(copy)
        frames += copy.frameLength
    }

    var buffers: [AVAudioPCMBuffer] {
        lock.lock()
        defer { lock.unlock() }
        return kept
    }

}

/// A tap's buffer copied, since the engine reuses it once the tap block returns.
private func copied(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength),
          let from = buffer.floatChannelData, let to = copy.floatChannelData else { return nil }
    copy.frameLength = buffer.frameLength
    for channel in 0..<Int(buffer.format.channelCount) {
        to[channel].update(from: from[channel], count: Int(buffer.frameLength))
    }
    return copy
}

/// Holds the microphone while the analyzer loads, then hands every buffer on in the order it was heard.
private final class Feeder: @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [AVAudioPCMBuffer] = []
    private var send: ((AVAudioPCMBuffer) -> Void)?

    func take(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        if let send {
            send(buffer)
        } else if let copy = copied(buffer) {
            waiting.append(copy)
        }
    }

    /// Sends what waited, then lets every later buffer straight through; held under the lock so none jumps the queue.
    func open(_ send: @escaping (AVAudioPCMBuffer) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        waiting.forEach(send)
        waiting.removeAll()
        self.send = send
    }
}

/// Final text kept, volatile text replaced as it firms up, so the pill shows the whole sentence.
private final class Heard: @unchecked Sendable {
    private let lock = NSLock()
    private var settled = ""
    private var volatile = ""
    private var changed = Date()

    /// Takes one result and returns everything heard so far.
    func take(_ text: String, final: Bool) -> String {
        lock.lock()
        defer { lock.unlock() }
        if final {
            settled = joinedSpeech(settled, text)
            volatile = ""
        } else {
            volatile = text
        }
        changed = Date()
        return joinedSpeech(settled, volatile)
    }

    func read() -> (String, Date) {
        lock.lock()
        defer { lock.unlock() }
        return (joinedSpeech(settled, volatile), changed)
    }
}

/// How many microphone buffers reached the analyzer and how many could not be converted, for the log.
private final class Counts: @unchecked Sendable {
    private let lock = NSLock()
    private var good = 0
    private var bad = 0

    func fed() { lock.lock(); good += 1; lock.unlock() }
    func dropped() { lock.lock(); bad += 1; lock.unlock() }

    var summary: String {
        lock.lock()
        defer { lock.unlock() }
        return "\(good) buffers heard, \(bad) could not be converted"
    }
}
