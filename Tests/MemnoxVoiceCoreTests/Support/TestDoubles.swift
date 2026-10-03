import Foundation
import XCTest

@testable import MemnoxVoiceCore

// Fakes for the ports, so every test runs with no socket, no audio and no Secure Enclave.

/// A daemon that answers each method from a script and remembers every request it was sent.
final class ScriptedLink: DaemonLink {
    var sent: [DaemonRequest] = []
    var answers: [String: [DaemonResponse]] = [:]
    var unreachable = false

    func stream(_ request: DaemonRequest) -> AsyncThrowingStream<DaemonResponse, Error> {
        sent.append(request)
        let scripted = answers[request.method] ?? []
        let unreachable = self.unreachable
        return AsyncThrowingStream { continuation in
            if unreachable {
                continuation.finish(throwing: ProtocolError.disconnected)
                return
            }
            for response in scripted { continuation.yield(response) }
            continuation.finish()
        }
    }
}

/// A daemon that answers line by line with pauses between, the way a streaming answer arrives.
final class StepLink: DaemonLink {
    let steps: [(Double, DaemonResponse)]
    var sent: [DaemonRequest] = []
    init(steps: [(Double, DaemonResponse)]) { self.steps = steps }
    func stream(_ request: DaemonRequest) -> AsyncThrowingStream<DaemonResponse, Error> {
        sent.append(request)
        let steps = self.steps
        let answering = request.method == "ask"
        return AsyncThrowingStream { continuation in
            Task {
                if answering {
                    for (delay, response) in steps {
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        continuation.yield(response)
                    }
                }
                continuation.finish()
            }
        }
    }
}

/// A daemon that takes its time before the first word, the way a cold brain does.
final class SlowLink: DaemonLink {
    let delay: UInt64
    let answer: [DaemonResponse]
    init(seconds: Double, answer: [DaemonResponse]) {
        delay = UInt64(seconds * 1_000_000_000)
        self.answer = answer
    }
    func stream(_ request: DaemonRequest) -> AsyncThrowingStream<DaemonResponse, Error> {
        let delay = self.delay
        let answer = self.answer
        return AsyncThrowingStream { continuation in
            Task {
                try? await Task.sleep(nanoseconds: delay)
                for response in answer { continuation.yield(response) }
                continuation.finish()
            }
        }
    }
}

final class RecordingSpeaker: Speaker {
    var said: [String] = []
    var stopped = 0
    var onSpeak: (() -> Void)?
    func speak(_ sentence: String) async {
        said.append(sentence)
        onSpeak?()
        onSpeak = nil
        // Long enough for an interruption raised while speaking to land before the next sentence.
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    var onQueue: (() -> Void)?
    func queue(_ sentence: String) {
        said.append(sentence)
        onQueue?()
        onQueue = nil
    }
    func drained() async {}
    func stop() { stopped += 1 }
}

final class RecordingFace: Face {
    var shown: [(VoiceState, String)] = []
    func show(_ state: VoiceState, caption: String) { shown.append((state, caption)) }
    var states: [VoiceState] { shown.map(\.0) }
}

/// A person who either touches the sensor or cancels.
final class RecordingChimes: Chimes {
    var played: [Cue] = []
    func play(_ cue: Cue) { played.append(cue) }
}

final class PersonKey: ConfirmKey {
    let inner = SoftwareConfirmKey()
    var touches = true
    var signed: [String] = []
    var publicPoint: String { inner.publicPoint }
    func sign(_ message: String, reason: String) async throws -> String? {
        signed.append(message)
        return touches ? try await inner.sign(message, reason: reason) : nil
    }
}

final class MemoryOwner: OwnerStore {
    var name: String?
    init(_ name: String?) { self.name = name }
}
