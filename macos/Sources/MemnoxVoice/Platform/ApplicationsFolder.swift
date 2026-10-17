import AppKit
import MemnoxVoiceCore

/// Puts Memnox in Applications when it was opened from its disk image or a download, as dragging it there would, and
/// opens that copy instead. macOS runs such a copy from a hidden read only folder and keeps no privacy grant for it, so
/// Screen Recording and Accessibility never list Memnox while it runs from there.
@MainActor
enum ApplicationsFolder {
    private static let folder = URL(fileURLWithPath: "/Applications", isDirectory: true)

    /// Where macOS runs a downloaded app it never saw moved, and where a disk image is mounted.
    private enum Outside {
        static let translocated = "/AppTranslocation/"
        static let volumes = "/Volumes/"
    }

    /// Cleared on the copy, since macOS would otherwise run it from the hidden folder again; the person already chose
    /// to open this Memnox, which is what the mark was there to ask.
    private enum Quarantine {
        static let tool = "/usr/bin/xattr"
        static let arguments = ["-dr", "com.apple.quarantine"]
    }

    /// True when the copy in Applications is opening, so this one quits rather than set anything up.
    static func moveIfOutside() -> Bool {
        let here = Bundle.main.bundleURL
        guard here.path.contains(Outside.translocated) || here.path.hasPrefix(Outside.volumes) else { return false }
        let target = folder.appendingPathComponent(here.lastPathComponent)
        do {
            // An earlier Memnox there is replaced, as dragging a new one over it would.
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.trashItem(at: target, resultingItemURL: nil)
            }
            try FileManager.default.copyItem(at: here, to: target)
        } catch {
            NSLog("Memnox: could not put Memnox in Applications, so it runs from where it was opened: \(error.localizedDescription)")
            return false
        }
        clearQuarantine(target)
        diary.note("moved Memnox from \(here.path) to \(target.path)")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: target, configuration: configuration) { _, error in
            if let error { NSLog("Memnox: the copy in Applications would not open: \(error.localizedDescription)") }
            Task { @MainActor in NSApp.terminate(nil) }
        }
        return true
    }

    private static func clearQuarantine(_ app: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Quarantine.tool)
        process.arguments = Quarantine.arguments + [app.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            diary.note("could not clear the download mark on \(app.path): \(error.localizedDescription)")
        }
    }
}
