import AVFoundation
import MemnoxVoiceCore
import Speech

/// The recognizer's language when the Mac's own has none.
private let fallbackLocale = "en-US"

/// Listens while Memnox is talking, so the person can cut in just by speaking. Its own voice
/// comes back through the microphone too, so only words it did not just say count as the person.
@MainActor
final class BargeEars {
    private let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: fallbackLocale))
    private var generation = 0
    private var listening: Task<String?, Never>?
    private var barged = false
    /// How often the latest words are looked at, quick so a cut in stops the voice at once.
    private static let pollSeconds: TimeInterval = 0.12
    private static let nanosecondsPerSecond: TimeInterval = 1_000_000_000

    /// Starts listening for the person over the voice; `cutIn` runs the moment they are heard.
    func watch(
        through audio: AudioIO,
        spoken: @escaping () -> String,
        speaking: @escaping () -> Bool,
        cutIn: @escaping () -> Void
    ) {
        stop(audio)
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { return }
        generation += 1
        barged = false
        let mine = generation
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.contextualStrings = recognizerHints
        audio.onMicrophone = { request.append($0) }
        let latest = Latest()
        let task = recognizer.recognitionTask(with: request) { result, _ in
            if let result { latest.update(result.bestTranscription.formattedString, final: result.isFinal) }
        }
        listening = Task { [weak self] in
            defer {
                if self?.generation == mine { audio.onMicrophone = nil }
                request.endAudio()
                task.cancel()
            }
            while self?.generation == mine {
                try? await Task.sleep(nanoseconds: UInt64(BargeEars.pollSeconds * BargeEars.nanosecondsPerSecond))
                guard let self else { return nil }
                let (words, changed, final) = latest.read()
                if !self.barged, isBargeIn(heard: words, spoken: spoken(), speaking: speaking()) {
                    self.barged = true
                    diary.note("talked over: \(words)")
                    cutIn()
                }
                // Once they have cut in, their whole sentence is kept until they pause.
                if self.barged, final || Date().timeIntervalSince(changed) > endOfSpeechPause(after: words) {
                    // The recognizer heard the voice too, so its words come off the front.
                    let mine = withoutEcho(words, spoken: spoken())
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
        generation += 1
        listening?.cancel()
        listening = nil
        audio.onMicrophone = nil
    }
}
