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
    /// The profiles the app's own PATH lines can be in, which `memnox uninstall` does not know of.
    private static let profiles = [".zshrc", ".bash_profile", ".config/fish/config.fish"]
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

    /// Only the lines between the app's own markers, so anything the person wrote around them stays exactly as it was.
    private static func removeProfileLines() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        for name in profiles {
            let file = home.appendingPathComponent(name)
            guard let text = try? String(contentsOf: file, encoding: .utf8), let kept = ProfileBlock.without(text) else { continue }
            try? kept.write(to: file, atomically: true, encoding: .utf8)
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
