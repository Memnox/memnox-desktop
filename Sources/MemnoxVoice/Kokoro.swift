import Foundation
import MemnoxVoiceCore

/// Somewhere other than the system synthesizer that turns a sentence into audio.
protocol VoiceEngine: Sendable {
    /// Said in the diary when it fails and the system voice takes the sentence.
    var name: String { get }
    func audio(for text: String) async throws -> Data
}

/// Kokoro, run on this Mac by its own small server: free, natural, and nothing leaves the machine.
struct KokoroVoice: VoiceEngine {
    let voice: String
    var name: String { "Kokoro" }

    /// George, a calm British voice; `defaults write com.memnox.voice kokoroVoice bm_lewis` picks another.
    static let defaultVoice = "bm_george"
    static let voiceKey = "kokoroVoice"

    static let speedKey = "voiceSpeed"

    /// The speeds a set voiceSpeed is held between, and the one used when none is set.
    private enum Speed {
        static let unhurried = 0.85
        static let normal = 1.0
        static let half = 0.5
    }

    /// The server's speech route and how it is asked.
    private enum Request {
        static let path = "speak"
        /// Long enough for a long sentence to synthesize on a slow Mac.
        static let timeout: TimeInterval = 10
        static let method = "POST"
        static let contentTypeHeader = "Content-Type"
        static let json = "application/json"
    }

    private static let errorDomain = "Kokoro"
    private static let rejectedCode = 1

    /// Slow enough to hear every word without dragging, kept between half speed and normal.
    static func speed() -> Double {
        let set = UserDefaults.standard.double(forKey: speedKey)
        return set == 0 ? Speed.unhurried : min(Speed.normal, max(Speed.half, set))
    }

    static func chosen() -> KokoroVoice {
        KokoroVoice(voice: UserDefaults.standard.string(forKey: voiceKey) ?? defaultVoice)
    }

    func audio(for text: String) async throws -> Data {
        var request = URLRequest(url: KokoroServer.url.appendingPathComponent(Request.path), timeoutInterval: Request.timeout)
        request.httpMethod = Request.method
        request.setValue(Request.json, forHTTPHeaderField: Request.contentTypeHeader)
        // Unhurried, so every word lands clearly the way a butler speaks; the voiceSpeed default changes it.
        request.httpBody = try JSONEncoder().encode(SpeakBody(text: text, voice: voice, speed: Self.speed()))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == httpOK else {
            throw NSError(domain: Self.errorDomain, code: Self.rejectedCode, userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "no body"])
        }
        return data
    }
}

/// What the server's speech route reads, encoded with its field names as the JSON keys.
private struct SpeakBody: Encodable {
    let text: String
    let voice: String
    let speed: Double
}

/// The status the server answers with when it did what was asked.
private let httpOK = 200

/// Where the installer puts Kokoro and the files it needs, relative to the home folder and to each other.
private enum KokoroFile {
    static let home = ".memnox/voice/kokoro"
    static let python = "venv/bin/python"
    static let server = "server.py"
    static let model = "kokoro-v1.0.onnx"
    static let voices = "voices-v1.0.bin"
    static let serverLog = "server.log"
    static let installLog = "install.log"
    static let health = "health"
    static let portFlag = "--port"
    /// The installer script as the app bundles it, at `kokoro/kokoro-setup.sh`.
    static let setupScript = "kokoro-setup"
    static let setupExtension = "sh"
    static let setupFolder = "kokoro"
    static let shell = "/bin/sh"
    /// The installer prints each step it starts on a line of its own after this.
    static let stepPrefix = "STEP "
}

/// Starts the Kokoro server that `KokoroInstaller` put in place, and stops it when Memnox quits.
@MainActor
final class KokoroServer {
    nonisolated static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(KokoroFile.home)
    /// The port the server listens on, and the one passed to it when Memnox starts it.
    private nonisolated static let port = 8723
    /// Loopback only, so nothing off this Mac can reach it.
    /// Force unwrapped because a fixed loopback address with a number for a port always parses.
    nonisolated static let url = URL(string: "http://127.0.0.1:\(port)")!
    /// The model loads in about a second; a slow disk gets a little longer, up to ten seconds in all.
    private static let startupPolls = 40
    private static let pollInterval: TimeInterval = 0.25
    /// Short, because a server on this Mac that is up answers at once.
    private nonisolated static let healthTimeout: TimeInterval = 1
    private var process: Process?

    var installed: Bool { Self.isInstalled }

    /// Whether the installer has put everything in place, for setup to say so.
    nonisolated static var isInstalled: Bool {
        [KokoroFile.python, KokoroFile.server, KokoroFile.model, KokoroFile.voices].allSatisfy {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
    }

    /// True once it answers, starting it first unless one from an earlier launch is still running.
    func ready() async -> Bool {
        if await Self.healthy() { return true }
        guard installed else {
            diary.note("Kokoro is not installed yet")
            return false
        }
        if process == nil, !start() { return false }
        for _ in 0..<Self.startupPolls {
            if await Self.healthy() { return true }
            try? await Task.sleep(nanoseconds: UInt64(Self.pollInterval * Double(NSEC_PER_SEC)))
        }
        diary.note("Kokoro did not answer; see \(Self.directory.path)/\(KokoroFile.serverLog)")
        return false
    }

    func stop() {
        process?.terminate()
        process = nil
    }

    private func start() -> Bool {
        let process = Process()
        process.executableURL = Self.directory.appendingPathComponent(KokoroFile.python)
        process.arguments = [KokoroFile.server, KokoroFile.portFlag, String(Self.url.port ?? Self.port)]
        process.currentDirectoryURL = Self.directory
        let log = Self.directory.appendingPathComponent(KokoroFile.serverLog)
        FileManager.default.createFile(atPath: log.path, contents: nil)
        if let handle = try? FileHandle(forWritingTo: log) {
            process.standardOutput = handle
            process.standardError = handle
        }
        do {
            try process.run()
            self.process = process
            diary.note("Kokoro starting")
            return true
        } catch {
            diary.note("Kokoro would not start: \(error)")
            return false
        }
    }

    private static func healthy() async -> Bool {
        let request = URLRequest(url: url.appendingPathComponent(KokoroFile.health), timeoutInterval: healthTimeout)
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == httpOK
    }
}

/// Where installing Kokoro stands, for the setup card to show while it happens.
enum KokoroInstall: Equatable {
    case idle
    case installing(String)
    case failed(String)
    case done
}

/// Installs Kokoro with the script inside the app, so the natural voice is the default without the
/// person running anything. About 340 MB, once; the Mac's own voice speaks until it is ready.
@MainActor
final class KokoroInstaller: ObservableObject {
    @Published private(set) var state: KokoroInstall = KokoroServer.isInstalled ? .done : .idle
    private var running: Task<Bool, Never>?

    /// Installs unless it already is, joining an install already under way rather than starting a second.
    func install() async -> Bool {
        if KokoroServer.isInstalled {
            state = .done
            return true
        }
        if let running { return await running.value }
        let task = Task { await self.run() }
        running = task
        let installed = await task.value
        running = nil
        return installed
    }

    private func run() async -> Bool {
        guard let script = Bundle.main.url(forResource: KokoroFile.setupScript, withExtension: KokoroFile.setupExtension, subdirectory: KokoroFile.setupFolder) else {
            state = .failed("This build has no Kokoro installer. Rebuild it with scripts/bundle.sh")
            return false
        }
        state = .installing("Getting ready")
        diary.note("installing Kokoro")
        let log = KokoroServer.directory.appendingPathComponent(KokoroFile.installLog)
        let outcome = await Self.execute(script) { [weak self] step in
            Task { @MainActor in self?.state = .installing(step) }
        }
        try? outcome.output.write(to: log, atomically: true, encoding: .utf8)
        if outcome.ok, KokoroServer.isInstalled {
            state = .done
            diary.note("Kokoro installed")
            return true
        }
        state = .failed("Kokoro could not install, usually for want of a connection. Details are in \(log.path)")
        diary.note("Kokoro did not install; see \(log.path)")
        return false
    }

    /// Runs the installer off the main thread, passing on each STEP line it prints as it goes.
    private nonisolated static func execute(_ script: URL, step: @escaping @Sendable (String) -> Void) async -> (ok: Bool, output: String) {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: KokoroFile.shell)
            process.arguments = [script.path]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            let output = Collected()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let text = String(decoding: handle.availableData, as: UTF8.self)
                output.append(text)
                for line in text.split(separator: "\n") where line.hasPrefix(KokoroFile.stepPrefix) {
                    step(String(line.dropFirst(KokoroFile.stepPrefix.count)))
                }
            }
            process.terminationHandler = { finished in
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: (finished.terminationStatus == 0, output.text))
            }
            do {
                try process.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: (false, "could not start the installer: \(error)"))
            }
        }
    }
}

/// The installer's output, written from the pipe's thread and read once it ends.
private final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var collected = ""

    func append(_ text: String) {
        lock.lock()
        collected += text
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return collected
    }
}
