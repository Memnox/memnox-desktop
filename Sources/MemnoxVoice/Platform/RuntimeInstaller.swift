import Foundation
import MemnoxVoiceCore

/// Puts the Memnox runtime under the app with no terminal: finds `memnox` or installs it, wires the
/// machine the first time, starts the daemon, and brings one too old for this app up to date. Every
/// step runs what a person would have typed, through their own login shell, so it lands where they
/// would have. Where `memnox` comes from is fixed when the app is built: a local build runs the
/// runtime checkout it was built beside, a release installs the published package from npm.
@MainActor
final class RuntimeInstaller: ObservableObject {
    /// What it is doing now, in a few words for the setup row; nil when it is not working.
    @Published private(set) var doing: String?
    /// Why the daemon is still not there after it tried, in words the person can act on.
    @Published private(set) var failed: String?
    private var running: Task<DaemonVoice, Never>?
    private let source = RuntimeSource.ofThisApp()

    /// The daemon ready for this app, or as close as it could get; one run at a time, shared by every caller.
    func ensure(_ conversation: Conversation) async -> DaemonVoice {
        if let running { return await running.value }
        let task = Task { await self.bringUp(conversation) }
        running = task
        let state = await task.value
        running = nil
        doing = nil
        return state
    }

    private func bringUp(_ conversation: Conversation) async -> DaemonVoice {
        var state = await conversation.daemonVoice()
        if state == .ready {
            failed = nil
            return state
        }
        guard let memnox = await memnoxCommand() else { return state }
        if state == .unreachable {
            let wired = FileManager.default.fileExists(atPath: Self.home(Self.keptFile))
            // The first time it wires every agent in observe, which records and enforces nothing until the person says.
            doing = wired ? "Starting the Memnox service" : "Setting Memnox up on this Mac"
            _ = await Self.shell(wired ? "\(memnox) daemon --install" : "\(memnox) setup --yes --no-probe")
            state = await settle(conversation)
        }
        if state == .tooOld { state = await update(memnox, conversation) }
        failed = why(state)
        return state
    }

    /// Updates and restarts the daemon whatever it answered, for a method the app needs that its version predates,
    /// which the version alone does not show while the runtime is built from a checkout.
    func updateNow(_ conversation: Conversation) async {
        guard doing == nil, let memnox = await memnoxCommand() else { return }
        let state = await update(memnox, conversation)
        failed = why(state)
        doing = nil
    }

    /// Puts the agents found here under Memnox with the same `memnox setup --yes` the first run uses: it asks nothing,
    /// takes nothing on its line but fixed words, and hooks every agent installed. Nil when it went through, else why.
    func protectAgents() async -> String? {
        // Two runs of the CLI at once would race over the same agent configs, and doing is set while any runs.
        guard doing == nil else { return "Memnox is still starting up. Try again in a moment." }
        doing = "Putting your agents under Memnox"
        defer { doing = nil }
        guard let memnox = await memnoxCommand() else { return failed ?? Self.notProtected }
        doing = "Putting your agents under Memnox"
        guard await Self.shell("\(memnox) setup --yes --no-probe") else { return Self.notProtected }
        return nil
    }

    private static let notProtected = "Memnox could not put them under it. In a terminal: memnox setup"

    /// A daemon older than the app: a local build restarts it on the checkout's code, which the build
    /// just made; a release updates from npm. Neither ever swaps a local checkout for the published one.
    private func update(_ memnox: String, _ conversation: Conversation) async -> DaemonVoice {
        doing = "Updating Memnox"
        if case .local = source {
            _ = await Self.shell("\(memnox) daemon --install")
            return await settle(conversation)
        }
        _ = await Self.shell("\(memnox) update --yes")
        // The daemon restarts itself on its new code; one that never ran as a service is started now.
        var state = await settle(conversation)
        if state == .unreachable {
            _ = await Self.shell("\(memnox) daemon --install")
            state = await settle(conversation)
        }
        return state
    }

    /// `memnox` from where this build says it comes from, quoted and ready to start a shell line.
    private func memnoxCommand() async -> String? {
        switch source {
        case .local(let checkout): return await localMemnox(checkout).map(Self.quoted)
        case .npm:
            // The copy this app put in ~/.memnox/node is on the PATH too once a terminal has it, and is still this
            // app's to keep up to date, so only a memnox from anywhere else is taken as the person's own.
            if let found = await Self.found(Command.memnox),
               !Self.resolved(found).hasPrefix(Self.resolved(Self.home(Installed.home))) {
                return Self.quoted(found)
            }
            await unpackCarried()
            if let installed = installedMemnox() { return installed }
            return await publishedMemnox().map(Self.quoted)
        }
    }

    /// The runtime with its own Node that a downloaded build carries, put into `~/.memnox/node` by the script beside it,
    /// which returns at once when what is there is as new. A build without one, or a failed unpack, falls through to npm.
    private func unpackCarried() async {
        guard let script = Bundle.main.path(forResource: Carried.script, ofType: Carried.scriptType, inDirectory: Carried.folder) else { return }
        if installedMemnox() == nil { doing = "Putting Memnox on this Mac" }
        if !(await Self.shell("\(Command.sh) \(Self.quoted(script))")) {
            diary.note("the runtime this app carries would not unpack")
        }
    }

    /// The runtime in `~/.memnox/node`, run with its own Node first on its PATH, so it needs no Node on the Mac and
    /// `memnox update` updates it in place. Nil where nothing was ever unpacked there.
    private func installedMemnox() -> String? {
        let node = Self.home(Installed.home)
        let bin = (node as NSString).appendingPathComponent(Installed.bin)
        let memnox = (bin as NSString).appendingPathComponent(Command.memnox)
        guard FileManager.default.isExecutableFile(atPath: memnox) else { return nil }
        // The prefix keeps npm installing updates beside this Node, whatever prefix the person's own npmrc names.
        return "PATH=\(Self.quoted(bin)):\"$PATH\" NPM_CONFIG_PREFIX=\(Self.quoted(node)) \(Self.quoted(memnox))"
    }

    /// The checkout's own CLI, linked onto the PATH with `npm link` when `memnox` there is any other copy,
    /// so the daemon, the hooks and every terminal run the code this app was built against.
    private func localMemnox(_ checkout: String) async -> String? {
        let cli = (checkout as NSString).appendingPathComponent(Runtime.cliFolder)
        guard FileManager.default.fileExists(atPath: (cli as NSString).appendingPathComponent(Runtime.cliEntry)) else {
            failed = "The runtime in \(checkout) is not built. In a terminal there: pnpm build"
            return nil
        }
        if let found = await Self.found(Command.memnox), Self.resolved(found).hasPrefix(Self.resolved(checkout)) {
            return found
        }
        doing = "Linking the local Memnox runtime"
        guard await Self.shell("cd \(Self.quoted(cli)) && npm link"), let found = await Self.found(Command.memnox) else {
            failed = "The local runtime would not link. In a terminal: cd \(cli) && npm link"
            return nil
        }
        diary.note("linked memnox from \(checkout) at \(found)")
        return found
    }

    /// The published package installed with npm, for a Mac with no `memnox` and a build that carries none.
    private func publishedMemnox() async -> String? {
        doing = "Installing Memnox"
        var hasNpm = await Self.found(Command.npm) != nil
        if !hasNpm { hasNpm = await installNode() }
        guard hasNpm else {
            failed = "Memnox needs Node.js. Install it from nodejs.org, then check again"
            return nil
        }
        guard await Self.shell("npm install -g memnox@latest"), let found = await Self.found(Command.memnox) else {
            failed = "Memnox would not install. In a terminal: npm install -g memnox"
            return nil
        }
        diary.note("installed memnox at \(found)")
        return found
    }

    /// Node through Homebrew, the one installer a Mac may already have that needs no password.
    private func installNode() async -> Bool {
        guard await Self.found(Command.brew) != nil else { return false }
        doing = "Installing Node.js"
        return await Self.shell("brew install node")
    }

    /// Asks again for a while, since a daemon just started or restarted takes a moment to answer.
    private func settle(_ conversation: Conversation) async -> DaemonVoice {
        var state = DaemonVoice.unreachable
        for _ in 0..<Timing.attempts {
            state = await conversation.daemonVoice()
            if state == .ready { return state }
            try? await Task.sleep(nanoseconds: UInt64(Timing.pollSeconds * 1_000_000_000))
        }
        return state
    }

    private func why(_ state: DaemonVoice) -> String? {
        switch (state, source) {
        case (.ready, _): return nil
        case (.tooOld, .local(let checkout)):
            return "The runtime in \(checkout) is older than this app. Pull it, run pnpm build there, then check again"
        case (.tooOld, .npm): return "This Memnox is older than the app and would not update. In a terminal: memnox update"
        case (.refused(let error), _): return "Memnox answered: \(error). Check again, or in a terminal: memnox doctor"
        case (.unreachable, _): return "The Memnox service would not start. Press Check again to try once more"
        }
    }

    /// A path with every link followed, so a global bin is compared by the folder it really lives in.
    private static func resolved(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    /// The full path of a command as the person's login shell finds it, which knows nvm, Homebrew and npm's own folder.
    private static func found(_ command: String) async -> String? {
        let (ok, output) = await run("command -v \(command)")
        let path = output.split(whereSeparator: \.isNewline).last.map(String.init)?.trimmingCharacters(in: .whitespaces)
        guard ok, let path, path.hasPrefix("/") else { return nil }
        return path
    }

    /// macOS's own reset of one privacy grant for one app, which needs no password for the app asking about itself.
    /// Both words are fixed by the caller, so nothing typed by anybody reaches the shell.
    static func forgetGrant(_ service: String, of bundle: String) async {
        _ = await shell("/usr/bin/tccutil reset \(quoted(service)) \(quoted(bundle))")
    }

    /// True when the line ran cleanly; what it printed goes to the diary when it did not.
    private static func shell(_ line: String) async -> Bool {
        diary.note("running: \(line)")
        let (ok, output) = await run(line)
        if !ok { diary.note("\(line) failed: \(output.suffix(Timing.keptOutput))") }
        return ok
    }

    /// One line through an interactive login shell, since that is where the person's PATH is set up.
    /// Only fixed words and paths the shell itself returned or the build wrote are ever put in it.
    private static func run(_ line: String) async -> (Bool, String) {
        // A file rather than a pipe, since npm or Homebrew printing more than a pipe holds would never finish.
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("memnox-runtime-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        guard let output = try? FileHandle(forWritingTo: log) else { return (false, "no log file") }
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? Command.zsh)
            process.arguments = ["-lic", line]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = output
            process.standardError = output
            process.terminationHandler = { finished in
                try? output.close()
                let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
                try? FileManager.default.removeItem(at: log)
                continuation.resume(returning: (finished.terminationStatus == 0, text))
            }
            do {
                try process.run()
            } catch {
                try? output.close()
                continuation.resume(returning: (false, error.localizedDescription))
            }
        }
    }

    /// Single quoted for the shell, with each quote inside closed, escaped and reopened.
    private static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func home(_ path: String) -> String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(path).path
    }

    /// Written by setup once it has wired the machine, so its absence is a machine never set up.
    private static let keptFile = ".memnox/kept.json"

    private enum Command {
        static let memnox = "memnox"
        static let npm = "npm"
        static let brew = "brew"
        static let zsh = "/bin/zsh"
        static let sh = "/bin/sh"
    }

    /// Where the runtime and its Node are unpacked, which `Support/runtime/unpack.sh` agrees on.
    private enum Installed {
        static let home = ".memnox/node"
        static let bin = "bin"
    }

    /// The unpacking script a downloaded build carries beside the runtime, put there by scripts/bundle.sh.
    private enum Carried {
        static let folder = "runtime"
        static let script = "unpack"
        static let scriptType = "sh"
    }

    /// Where the CLI sits in a runtime checkout, and the file a build leaves there.
    private enum Runtime {
        static let cliFolder = "packages/cli"
        static let cliEntry = "dist/index.js"
    }

    private enum Timing {
        /// Long enough for a daemon on a cold Mac to load its rules and answer.
        static let attempts = 30
        static let pollSeconds: TimeInterval = 1
        /// The end of what a failed step printed, which is where the reason is.
        static let keptOutput = 600
    }
}

