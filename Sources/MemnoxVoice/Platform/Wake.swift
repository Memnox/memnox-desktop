import AVFoundation
import MemnoxVoiceCore
import Speech

/// The recognizer's language when the Mac's own has none.
private let fallbackLocale = "en-US"

/// Listens for its own name while nothing else is happening, so saying "Memnox" opens the orb
/// the way Option Space does. Recognition stays on this Mac, and a Mac that cannot recognise on
/// device never listens at all, since a microphone streaming all day to a server is not a door.
@MainActor
final class WakeEars {
    private let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: fallbackLocale))
    /// Bumped on every start and stop, so a round that was stopped never touches the microphone again.
    private var generation = 0
    private var listening: Task<Void, Never>?
    private var audio: AudioIO?
    /// Well inside the minute the recognizer allows one request.
    private static let roundSeconds: TimeInterval = 50
    /// How long after the name alone before the orb opens, in case a question follows it.
    private static let afterNameSeconds: TimeInterval = 1.0
    /// The name it listens for, given to the recognizer as a hint only.
    private static let name = "Memnox"
    /// A short rest between rounds, so a round that ends at once does not spin.
    private static let betweenRoundsSeconds: TimeInterval = 0.3
    /// How long to wait before trying again while the recognizer is unavailable.
    private static let unavailableSeconds: TimeInterval = 2.0
    /// How often the latest words are looked at.
    private static let pollSeconds: TimeInterval = 0.15
    private static let nanosecondsPerSecond: TimeInterval = 1_000_000_000

    /// Called with whatever followed the name, empty when it was said alone.
    var woke: ((String) -> Void)?
    /// What the voice said lately, so its own sentence with its name in it never wakes it.
    var spoken: () -> String = { "" }

    var canListen: Bool {
        guard let recognizer else { return false }
        return recognizer.supportsOnDeviceRecognition
            && SFSpeechRecognizer.authorizationStatus() == .authorized
            && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func start(through audio: AudioIO) {
        stop()
        guard canListen else {
            diary.note("not listening for my name: no on-device recognition, or no permission yet")
            return
        }
        do { try audio.start() } catch {
            diary.note("not listening for my name: \(error)")
            return
        }
        self.audio = audio
        let mine = generation
        diary.note("listening for my name")
        listening = Task { [weak self] in
            while true {
                guard let self, self.generation == mine else { return }
                if let after = await self.round(through: audio, generation: mine) {
                    guard self.generation == mine else { return }
                    diary.note("heard my name\(after.isEmpty ? "" : ", then: \(after)")")
                    self.woke?(after)
                    return
                }
                try? await Task.sleep(nanoseconds: UInt64(WakeEars.betweenRoundsSeconds * WakeEars.nanosecondsPerSecond))
            }
        }
    }

    /// Lets go of the microphone at once, so whatever runs next has it to itself.
    func stop() {
        generation += 1
        listening?.cancel()
        listening = nil
        audio?.onMicrophone = nil
        audio?.stop()
        audio = nil
    }

    /// One recognizer request: the words after the name once they pause, or nil when the round ran out.
    private func round(through audio: AudioIO, generation mine: Int) async -> String? {
        guard let recognizer, recognizer.isAvailable else {
            try? await Task.sleep(nanoseconds: UInt64(Self.unavailableSeconds * Self.nanosecondsPerSecond))
            return nil
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.contextualStrings = [Self.name]
        audio.onMicrophone = { request.append($0) }
        let latest = Latest()
        let task = recognizer.recognitionTask(with: request) { result, error in
            if let result {
                latest.update(result.bestTranscription.formattedString, final: result.isFinal)
            } else if error != nil {
                latest.update(latest.read().0, final: true)
            }
        }
        defer {
            if generation == mine { audio.onMicrophone = nil }
            request.endAudio()
            task.cancel()
        }
        let began = Date()
        while generation == mine {
            try? await Task.sleep(nanoseconds: UInt64(Self.pollSeconds * Self.nanosecondsPerSecond))
            let (words, changed, final) = latest.read()
            if let after = afterWakeWord(words, spoken: spoken()) {
                let pause = after.isEmpty ? Self.afterNameSeconds : endOfSpeechPause(after: after)
                if final || Date().timeIntervalSince(changed) > pause { return after }
                continue
            }
            if final || Date().timeIntervalSince(began) > Self.roundSeconds { return nil }
        }
        return nil
    }
}
