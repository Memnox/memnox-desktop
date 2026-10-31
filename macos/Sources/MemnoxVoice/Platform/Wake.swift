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
    /// How often the room's loudness is read while nobody speaks, which is all waiting costs.
    private static let quietPollSeconds: TimeInterval = 0.1
    /// Loud enough to be somebody speaking near the Mac, below the level the orb treats as talking to it.
    private static let speakingLevel: Float = AudioIO.voiceLevel * 0.4
    /// The sound kept from just before the room got loud, about a second, so the start of the name is never cut off.
    private static let preRollBuffers = 48
    /// A round that has heard no new words this long goes back to waiting for the room to get loud, cheaply.
    private static let quietRoundSeconds: TimeInterval = 4
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
                // The recognizer runs only while somebody speaks, since running it on a quiet room was most of the app's idle CPU.
                guard let before = await self.untilSomeoneSpeaks(through: audio, generation: mine) else { return }
                let failed: Bool
                switch await self.round(through: audio, generation: mine, before: before) {
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

    /// Waits, reading only the microphone's level, until the room gets loud; the sound from just before, or nil once stopped.
    private func untilSomeoneSpeaks(through audio: AudioIO, generation mine: Int) async -> [AVAudioPCMBuffer]? {
        let kept = PreRoll(keeping: Self.preRollBuffers)
        audio.onMicrophone = { kept.add($0) }
        while generation == mine {
            if audio.micLevel >= Self.speakingLevel { return kept.taken() }
            try? await Task.sleep(nanoseconds: UInt64(Self.quietPollSeconds * Self.nanosecondsPerSecond))
        }
        return nil
    }

    /// One recognizer request: the words after the name once they pause, or how it ended without them.
    private func round(through audio: AudioIO, generation mine: Int, before: [AVAudioPCMBuffer]) async -> Round {
        guard let recognizer, recognizer.isAvailable else { return .failed }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.contextualStrings = [Self.name]
        for buffer in before { request.append(buffer) }
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
            if Date().timeIntervalSince(max(began, changed)) > Self.quietRoundSeconds, audio.micLevel < Self.speakingLevel { return .ranOut }
        }
        return .ranOut
    }
}

/// The last few microphone buffers, filled on the audio thread and taken on the main actor once the room gets loud.
private final class PreRoll: @unchecked Sendable {
    private let lock = NSLock()
    private var buffers: [AVAudioPCMBuffer] = []
    private let keeping: Int

    init(keeping: Int) { self.keeping = keeping }

    func add(_ buffer: AVAudioPCMBuffer) {
        // Copied, since a buffer the tap hands over may be filled again with the next twenty milliseconds.
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return }
        copy.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
        let target = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (from, to) in zip(source, target) where from.mData != nil && to.mData != nil {
            // Both checked to hold data just above, and the copy was made the same size in the same format.
            to.mData!.copyMemory(from: from.mData!, byteCount: Int(min(from.mDataByteSize, to.mDataByteSize)))
        }
        lock.lock()
        buffers.append(copy)
        if buffers.count > keeping { buffers.removeFirst(buffers.count - keeping) }
        lock.unlock()
    }

    func taken() -> [AVAudioPCMBuffer] {
        lock.lock()
        defer { lock.unlock() }
        return buffers
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
