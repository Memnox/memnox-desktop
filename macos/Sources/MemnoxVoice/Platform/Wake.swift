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
    /// The recognizer's own errors, among them the one it ends a round with when nobody spoke.
    private static let recognizerErrors = "kAFAssistantErrorDomain"
    /// No speech in the round, which is a quiet room rather than a recognizer that failed.
    private static let noSpeechCode = 1110
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
            var rest = WakeRest()
            while true {
                guard let self, self.generation == mine else { return }
                let failed: Bool
                switch await self.round(through: audio, generation: mine) {
                case .heard(let after):
                    guard self.generation == mine else { return }
                    diary.note("heard my name\(after.isEmpty ? "" : ", then: \(after)")")
                    self.woke?(after)
                    return
                case .ranOut:
                    failed = false
                case .failed:
                    failed = true
                }
                let seconds = rest.after(failed: failed)
                if seconds > WakeRest.afterFirstFailure { diary.note("listening for my name keeps failing, so resting \(Int(seconds)) seconds") }
                try? await Task.sleep(nanoseconds: UInt64(seconds * WakeEars.nanosecondsPerSecond))
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

    /// How one recognizer request ended.
    private enum Round {
        /// The name was heard, with the words after it once they paused.
        case heard(String)
        /// The round ended with no name in it, as most do.
        case ranOut
        /// The recognizer was unavailable or ended on an error, so the next round waits longer.
        case failed
    }

    /// One recognizer request: the words after the name once they pause, or how it ended without them.
    private func round(through audio: AudioIO, generation mine: Int) async -> Round {
        guard let recognizer, recognizer.isAvailable else { return .failed }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.contextualStrings = [Self.name]
        audio.onMicrophone = { request.append($0) }
        let latest = Latest()
        let broke = Broke()
        let task = recognizer.recognitionTask(with: request) { result, error in
            if let result {
                latest.update(result.bestTranscription.formattedString, final: result.isFinal)
            } else if let error {
                let quiet = (error as NSError).domain == Self.recognizerErrors && (error as NSError).code == Self.noSpeechCode
                if !quiet { broke.mark() }
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
                if final || Date().timeIntervalSince(changed) > pause { return .heard(after) }
                continue
            }
            if final { return broke.happened ? .failed : .ranOut }
            if Date().timeIntervalSince(began) > Self.roundSeconds { return .ranOut }
        }
        return .ranOut
    }
}

/// Whether the recognizer ended a round on an error of its own, set from its thread and read on the main actor.
private final class Broke: @unchecked Sendable {
    private let lock = NSLock()
    private var broke = false

    func mark() {
        lock.lock()
        broke = true
        lock.unlock()
    }

    var happened: Bool {
        lock.lock()
        defer { lock.unlock() }
        return broke
    }
}
