import AppKit
import MemnoxVoiceCore

/// Puts a newer Memnox in place of this one, as `scripts/install.sh` does: the image is downloaded, refused unless it
/// matches the checksum published beside it, and its app copied out; once this copy quits, a small script swaps the
/// two and opens the new one. Nothing is replaced until the new app is whole on disk.
@MainActor
enum AppUpdater {
    /// The bundle every release carries, so an image holding anything else is refused.
    private static let bundleId = "com.memnox.voice"
    private static let appName = "Memnox.app"

    private enum Tool {
        static let hdiutil = "/usr/bin/hdiutil"
        static let ditto = "/usr/bin/ditto"
        static let sh = "/bin/sh"
    }

    /// The version this app is, from its Info.plist.
    static var running: String? { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String }

    /// Whether this copy may replace itself: a build from a checkout is the developer's own and is never swapped.
    static var canUpdate: Bool {
        guard case .npm = RuntimeSource.ofThisApp() else { return false }
        return FileManager.default.isWritableFile(atPath: Bundle.main.bundleURL.deletingLastPathComponent().path)
    }

    /// Readies the release and quits so the swap can run; returns why it could not when it stops short.
    static func install(_ release: AppRelease) async -> String? {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("memnox-update-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let staged = try await stage(release, in: work)
            try swapAfterQuit(staged: staged, work: work)
        } catch let failure as Failure {
            try? FileManager.default.removeItem(at: work)
            diary.note("the update to \(release.version) stopped: \(failure.why)")
            return failure.why
        } catch {
            try? FileManager.default.removeItem(at: work)
            diary.note("the update to \(release.version) stopped: \(error.localizedDescription)")
            return Failure.download.why
        }
        diary.note("updating Memnox to \(release.version)")
        NSApp.terminate(nil)
        return nil
    }

    private enum Failure: Error {
        case download, checksum, image, notMemnox

        var why: String {
            switch self {
            case .download: return "The download did not finish. Try again in a moment."
            case .checksum: return "The download does not match its published checksum, so nothing was installed."
            case .image: return "The disk image would not open, so nothing was installed."
            case .notMemnox: return "The disk image does not hold Memnox, so nothing was installed."
            }
        }
    }

    /// The new app, copied out of its verified image into `work`.
    private static func stage(_ release: AppRelease, in work: URL) async throws -> URL {
        let image = work.appendingPathComponent(AppRelease.Asset.image)
        let (downloaded, response) = try await URLSession.shared.download(from: release.image)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.download }
        try FileManager.default.moveItem(at: downloaded, to: image)
        let (sum, sumResponse) = try await URLSession.shared.data(from: release.checksum)
        guard (sumResponse as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.download }
        // Hashed off the main actor, since the image carries the runtime and the voice.
        let published = String(decoding: sum, as: UTF8.self)
        let matches = await Task.detached { ImageChecksum.matches(image, published: published) }.value
        guard matches else { throw Failure.checksum }

        let mount = work.appendingPathComponent("mount", isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        guard await run(Tool.hdiutil, ["attach", image.path, "-mountpoint", mount.path, "-nobrowse", "-readonly", "-quiet"]) else {
            throw Failure.image
        }
        let inside = mount.appendingPathComponent(appName)
        let staged = work.appendingPathComponent(appName)
        let isMemnox = Bundle(url: inside)?.bundleIdentifier == bundleId
        let copied = isMemnox ? await run(Tool.ditto, [inside.path, staged.path]) : false
        // Detached before anything else, since this app quits right after and would leave the image mounted.
        _ = await run(Tool.hdiutil, ["detach", mount.path, "-quiet"])
        guard isMemnox else { throw Failure.notMemnox }
        guard copied else { throw Failure.image }
        return staged
    }

    /// Starts the script that waits for this copy to quit, swaps the new app in, and opens it. The old app is kept
    /// until the new one is in place, and put back if the move fails, so a failed swap never leaves no Memnox at all.
    /// Every path goes in as an argument, never into the script's words.
    private static func swapAfterQuit(staged: URL, work: URL) throws {
        let script = """
        pid="$1"; staged="$2"; target="$3"; work="$4"
        while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
        old="$target.old"
        rm -rf "$old"
        if mv "$target" "$old" && mv "$staged" "$target"; then
          rm -rf "$old"
        else
          [ -d "$target" ] || mv "$old" "$target"
        fi
        xattr -dr com.apple.quarantine "$target" 2>/dev/null
        rm -rf "$work"
        open "$target"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Tool.sh)
        process.arguments = ["-c", script, "memnox-update", String(ProcessInfo.processInfo.processIdentifier), staged.path, Bundle.main.bundleURL.path, work.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    /// True when the tool exited cleanly.
    private static func run(_ tool: String, _ arguments: [String]) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus == 0) }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
}
