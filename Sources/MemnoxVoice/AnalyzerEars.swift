import AVFoundation
import MemnoxVoiceCore
import Speech

/// How one listen ended: words, nothing said in time, or a recognizer that could not start.
enum Listened {
    case heard(String)
    case silence
    case unavailable
}

/// Apple's SpeechAnalyzer, on macOS 26 and later: on this Mac, streaming, and better at the
/// words people use about their agents. Its language model downloads the first time, once.
@available(macOS 26, *)
final class AnalyzerEars {
    var hearing: ((String) -> Void)?

    /// The next thing said, nothing when the wait ran out, or unavailable when it could not start.
    func listen(through audio: AudioIO, waiting: TimeInterval) async -> Listened {
        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) ?? Locale(identifier: "en-US")
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        guard await installed(transcriber),
              let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        else { return .unavailable }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let context = AnalysisContext()
        context.contextualStrings[.general] = recognizerHints
        try? await analyzer.setContext(context)

        let (input, feed) = AsyncStream<AnalyzerInput>.makeStream()
        var converter: AVAudioConverter?
        let counts = Counts()
        audio.onMicrophone = { buffer in
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

        let heard = Heard()
        let reading = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let words = heard.take(String(result.text.characters), final: result.isFinal)
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
            voiceLog.error("SpeechAnalyzer would not start: \(String(describing: error), privacy: .public)")
            return .unavailable
        }

        let began = Date()
        while true {
            try? await Task.sleep(nanoseconds: 150_000_000)
            let (words, changed) = heard.read()
            if words.isEmpty, Date().timeIntervalSince(began) > waiting { break }
            if !words.isEmpty, Date().timeIntervalSince(changed) > 1.1 { break }
        }
        audio.onMicrophone = nil
        feed.finish()
        voiceLog.info("microphone: \(counts.summary, privacy: .public)")
        try? await analyzer.finalizeAndFinishThroughEndOfInput()
        await reading.value
        let words = heard.read().0.trimmingCharacters(in: .whitespacesAndNewlines)
        voiceLog.info("SpeechAnalyzer heard \(words.isEmpty ? "nothing" : "words", privacy: .public)")
        return words.isEmpty ? .silence : .heard(words)
    }

    /// The model for this language, fetched the first time and kept by the system after that.
    private func installed(_ transcriber: SpeechTranscriber) async -> Bool {
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
            return true
        } catch {
            voiceLog.error("speech model not installed: \(String(describing: error), privacy: .public)")
            return false
        }
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
            settled += text
            volatile = ""
        } else {
            volatile = text
        }
        changed = Date()
        return settled + volatile
    }

    func read() -> (String, Date) {
        lock.lock()
        defer { lock.unlock() }
        return (settled + volatile, changed)
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
