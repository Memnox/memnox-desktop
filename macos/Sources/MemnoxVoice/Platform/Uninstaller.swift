import AppKit
import MemnoxVoiceCore
import Security

/// Takes everything Memnox put on this Mac off it again, then the app itself: the runtime asked to remove its own hooks,
/// wrapping, service and home first, then whatever it leaves or never knew of, each step on its own so one that fails
/// never stops the rest. Run from Settings, or when the person drags the app to the Trash and says yes.
@MainActor
enum Uninstaller {
    /// The Keychain services the app writes: the Secure Enclave key, the person's credential and the paired servers.
    private static let keychainServices = ["com.memnox.voice", "com.memnox.voice.person", "com.memnox.voice.servers"]
    /// The daemon's launch agent, which `memnox uninstall` removes and which is taken out again here in case it could not.
    private static let daemonLabel = "com.memnox.daemon"
    /// The profiles the app's own PATH lines and the runtime's can be in.
    private static let profiles = [".zshrc", ".bashrc", ".bash_profile", ".config/fish/config.fish"]
    /// Every agent file the runtime puts its hook in, as `memnox uninstall` takes it out of them.
    private static let hookFiles = [".claude/settings.json", ".claude/settings.local.json", ".codex/hooks.json",
                                    ".gemini/settings.json", ".cursor/hooks.json", ".codeium/windsurf/hooks.json"]
    /// Every agent MCP config the runtime writes its session and workspace servers into, JSON ones only.
    private static let serverFiles = [".claude.json", ".cursor/mcp.json", ".gemini/settings.json", ".codeium/windsurf/mcp_config.json"]
    private static let codexConfig = ".codex/config.toml"
    /// Where npm puts a global memnox when its own prefix cannot be asked: Homebrew's node on either chip, and ~/.local.
    private static let knownPrefixes = ["/opt/homebrew", "/usr/local"]
    private static let localPrefix = ".local"
    private static let packageName = "memnox"
    /// The suffix of the copy each rewritten agent file is kept as, so a person can put it back by hand.
    private static let backupSuffix = ".before-memnox-uninstall"
    /// The editor extension the daemon installs on every start, under each editor's own folder.
    private static let editorFolders = [".vscode/extensions", ".cursor/extensions", ".windsurf/extensions"]
    private static let extensionPrefix = "memnox.memnox-terminals-"
    private static let appSupport = "Library/Application Support/Memnox"

    private enum Tool {
        static let launchctl = "/bin/launchctl"
        static let tccutil = "/usr/bin/tccutil"
    }

    /// Everything, then the app to the Trash unless it is there already, then quits.
    static func run(runtime: RuntimeInstaller, signOut: () -> Void) async {
        diary.note("uninstalling Memnox")
        // First, so the cloud forgets this Mac while it still holds the credential to say so.
        signOut()
        if !(await runtime.uninstallRuntime()) { diary.note("no memnox to ask, so its pieces are removed here") }
        // Always, since a memnox older than this app leaves its hooks, servers and package behind, and each step only
        // ever takes what names Memnox, so after a runtime that did it all they find nothing.
        removeAgentHooks()
        removeAgentServers()
        await removeGlobalCli()
        await removeDaemonService()
        removeProfileLines()
        removeEditorExtensions()
        removeKeychainItems()
        let home = FileManager.default.homeDirectoryForCurrentUser
        try? FileManager.default.removeItem(at: home.appendingPathComponent(".memnox"))
        try? FileManager.default.removeItem(at: home.appendingPathComponent(appSupport))
        if let bundle = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundle)
            _ = await run(Tool.tccutil, ["reset", "All", bundle])
        }
        let app = Bundle.main.bundleURL
        if !app.path.contains("/.Trash/") {
            _ = try? await NSWorkspace.shared.recycle([app])
        }
        NSApp.terminate(nil)
    }

    private static func removeDaemonService() async {
        _ = await run(Tool.launchctl, ["bootout", "gui/\(getuid())/\(daemonLabel)"])
        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(daemonLabel).plist")
        try? FileManager.default.removeItem(at: plist)
    }

    /// Only the lines between the app's own markers and the runtime's, so anything the person wrote around them stays
    /// exactly as it was.
    private static func removeProfileLines() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        for name in profiles {
            let file = home.appendingPathComponent(name)
            guard var text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            var changed = false
            if let kept = ProfileBlock.without(text) { text = kept; changed = true }
            if let kept = ProfileBlock.without(text, between: RuntimeLeftovers.pathBegin, and: RuntimeLeftovers.pathEnd) {
                text = kept
                changed = true
            }
            if changed { try? text.write(to: file, atomically: true, encoding: .utf8) }
        }
    }

    /// The hook out of each agent's settings, because a hook left once its binary is gone fails on every tool call.
    private static func removeAgentHooks() {
        for name in hookFiles { rewrite(name) { RuntimeLeftovers.withoutHooks($0) } }
    }

    /// The session and workspace servers out of each agent's MCP config, which would otherwise start a missing binary.
    private static func removeAgentServers() {
        for name in serverFiles { rewrite(name) { RuntimeLeftovers.withoutServers($0) } }
        rewrite(codexConfig) { data in
            String(data: data, encoding: .utf8).flatMap(RuntimeLeftovers.withoutTomlServers).map { Data($0.utf8) }
        }
    }

    /// One agent file, rewritten only where the change found something of ours, its old bytes kept beside it first.
    private static func rewrite(_ name: String, _ change: (Data) -> Data?) {
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: file), let next = change(data) else { return }
        let backup = file.deletingLastPathComponent().appendingPathComponent(file.lastPathComponent + backupSuffix)
        guard (try? data.write(to: backup, options: .atomic)) != nil else { return }
        if (try? next.write(to: file, options: .atomic)) != nil { diary.note("took Memnox out of \(name)") }
    }

    /// The memnox package under every npm prefix it could be in: a link loses only itself and the bins leading into it,
    /// so the checkout it points at stays, and an install loses its own folder and those bins.
    private static func removeGlobalCli() async {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var prefixes = knownPrefixes + [home.appendingPathComponent(localPrefix).path]
        if let asked = await RuntimeInstaller.npmPrefix() { prefixes.insert(asked, at: 0) }
        let files = FileManager.default
        for prefix in Set(prefixes) {
            let entry = URL(fileURLWithPath: prefix).appendingPathComponent("lib/node_modules/\(packageName)")
            guard (try? files.attributesOfItem(atPath: entry.path)) != nil else { continue }
            let package = entry.resolvingSymlinksInPath().path
            let bin = URL(fileURLWithPath: prefix).appendingPathComponent("bin")
            let names = (try? files.contentsOfDirectory(atPath: bin.path)) ?? []
            let links = names.compactMap { name -> (name: String, resolved: String)? in
                let link = bin.appendingPathComponent(name)
                guard (try? files.destinationOfSymbolicLink(atPath: link.path)) != nil else { return nil }
                return (name, link.resolvingSymlinksInPath().path)
            }
            for name in RuntimeLeftovers.binsInto(package, among: links) {
                try? files.removeItem(at: bin.appendingPathComponent(name))
            }
            // removeItem on a link takes the link and never what it points at.
            if (try? files.removeItem(at: entry)) != nil { diary.note("removed the memnox package at \(entry.path)") }
        }
    }

    private static func removeEditorExtensions() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        for folder in editorFolders {
            let dir = home.appendingPathComponent(folder)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            for name in names where name.hasPrefix(extensionPrefix) {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
            }
        }
    }

    private static func removeKeychainItems() {
        for service in keychainServices {
            for dataProtection in [true, false] {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecUseDataProtectionKeychain as String: dataProtection,
                ]
                SecItemDelete(query as CFDictionary)
            }
        }
    }

    private static func run(_ tool: String, _ arguments: [String]) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus == 0) }
            do { try process.run() } catch { continuation.resume(returning: false) }
        }
    }
}

/// Notices the app being dragged to the Trash while it runs, which macOS tells no app about, by watching its own bundle
/// for a rename and reading where it went.
@MainActor
final class TrashWatch {
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: Int32 = -1
    private let trashed: () -> Void

    init(trashed: @escaping () -> Void) {
        self.trashed = trashed
        descriptor = open(Bundle.main.bundleURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in self?.moved() }
        source.setCancelHandler { [descriptor] in close(descriptor) }
        source.resume()
        self.source = source
    }

    /// Where the bundle is now, read from the open descriptor, since the path the app started from no longer names it.
    private func moved() {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(descriptor, F_GETPATH, &buffer) != -1 else { return }
        let now = String(cString: buffer)
        guard now.contains("/.Trash/") else { return }
        source?.cancel()
        source = nil
        trashed()
    }
}
