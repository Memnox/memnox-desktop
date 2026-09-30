import AVFoundation
import Speech

/// Apple's SpeechAnalyzer, on macOS 26 and later: on this Mac, streaming, and better at the
/// words people use about their agents. Its language model downloads the first time, once.
@available(macOS 26, *)
final class AnalyzerEars {
    var hearing: ((String) -> Void)?

    /// The next thing said, or nil when nothing was said before the wait ran out.
    func listen(through audio: AudioIO, waiting: TimeInterval) async -> String? {
        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) ?? Locale(identifier: "en-US")
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        guard await installed(transcriber),
              let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        else { return nil }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let context = AnalysisContext()
        context.contextualStrings[.general] = recognizerHints
        try? await analyzer.setContext(context)

        let (input, feed) = AsyncStream<AnalyzerInput>.makeStream()
        var converter: AVAudioConverter?
        audio.onMicrophone = { buffer in
            if converter == nil || converter?.inputFormat != buffer.format {
                converter = AVAudioConverter(from: buffer.format, to: format)
            }
            guard let converter, let converted = convert(buffer, with: converter, to: format) else { return }
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
            return nil
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
        try? await analyzer.finalizeAndFinishThroughEndOfInput()
        await reading.value
        let words = heard.read().0.trimmingCharacters(in: .whitespacesAndNewlines)
        return words.isEmpty ? nil : words
    }

    /// The model for this language, fetched the first time and kept by the system after that.
    private func installed(_ transcriber: SpeechTranscriber) async -> Bool {
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
            return true
        } catch {
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
