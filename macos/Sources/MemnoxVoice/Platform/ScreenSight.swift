import AppKit
import Carbon.HIToolbox
import ImageIO
import MemnoxVoiceCore
import ScreenCaptureKit
import UniformTypeIdentifiers
import Vision

/// Memnox's eyes: one window captured as the person sees it, with the outline of its controls, so
/// the brain can read the screen and an action can be shown to have landed. It captures only when
/// asked, never on a timer, and keeps what it took for a day.
@MainActor
enum ScreenSight {
    private enum Folder {
        /// What the brain asked to see.
        static let sight = ".memnox/sight"
        /// What an action left behind, kept as its evidence.
        static let proof = ".memnox/proof"
    }

    /// A day, long enough to look back at what happened today and short enough that screens never pile up.
    private static let keptFor: TimeInterval = 24 * 60 * 60
    /// Wide enough for every label to be read, small enough to send to the brain quickly.
    private static let widest: CGFloat = 1600
    /// The layer ordinary app windows sit on; menus and the dock sit above it.
    private static let normalLayer = 0
    /// The most of a window's words handed on as evidence, from its end, where a chat or a terminal says what just happened.
    private static let mostEvidenceCharacters = 2000
    /// Apps whose windows hold secrets, never captured whatever was asked.
    private static let neverCaptured: Set<String> = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop", "com.apple.keychainaccess",
        "com.apple.Passwords", "com.lastpass.LastPass", "com.dashlane.Dashlane",
    ]

    /// Whether this window may be captured at all: never a password manager, and nothing while a password
    /// field anywhere has the keyboard, which macOS marks as secure input.
    static func mayCapture(_ app: NSRunningApplication) -> Bool {
        guard allowed, !IsSecureEventInputEnabled() else { return false }
        return !neverCaptured.contains(app.bundleIdentifier ?? "")
    }

    /// Whether macOS lets Memnox record the screen; asking is the setup checklist's job.
    static var allowed: Bool { liveGrant || CGPreflightScreenCaptureAccess() }

    /// Set once ScreenCaptureKit answered, since the preflight keeps saying no until the app restarts even after the
    /// switch was turned on, and ScreenCaptureKit reads the grant as it stands now.
    nonisolated(unsafe) private static var liveGrant = false

    /// Asks ScreenCaptureKit whether the grant holds now, so a switch just turned on counts without reopening Memnox.
    /// Only after the person pressed Allow, since asking before then is what puts macOS's own sheet up.
    static func confirmGrant() async -> Bool {
        if allowed { return true }
        guard (try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)) != nil else {
            return false
        }
        liveGrant = true
        return true
    }

    /// The app by the name the brain gave, or the app the person was last in.
    static func app(named name: String?, otherwise front: String?) -> NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier != Bundle.main.bundleIdentifier }
        if let name, let found = apps.first(where: { $0.localizedName?.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            return found
        }
        if let front, let found = apps.first(where: { $0.localizedName == front }) { return found }
        return NSWorkspace.shared.frontmostApplication.flatMap { $0.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : $0 }
    }

    /// The app's front window as a capture and an outline; when Memnox may not record, the words come from the
    /// window's accessibility tree instead, so a chat app's answer is still read without Screen Recording.
    static func look(at app: NSRunningApplication) async -> Sight {
        let window = AXTree.frontWindow(of: app)
        let title = window.flatMap { AXTree.string($0, kAXTitleAttribute) }
        let outline = window.map(AXTree.outline(of:))
        let image = await image(of: app, title: title)
        let path = image.flatMap { write($0, into: Folder.sight, named: UUID().uuidString) }
        var text: String?
        if let image {
            text = await read(image, level: .accurate)
        } else if let window {
            text = await accessibleText(of: window)
        }
        let how = image != nil ? "" : text == nil ? ", outline only" : ", words read through Accessibility"
        diary.note("looked at \(app.localizedName ?? "an app")\(how)")
        return Sight(app: app.localizedName ?? "", window: title, image: path, outline: outline, text: text)
    }

    /// The most of a window's accessible words handed on, from its end, where a chat's latest answer is.
    private static let mostAccessibleCharacters = 6_000
    /// Electron builds its web content's tree only once asked, so an empty first read waits this long and reads again.
    private static let treeBuildWait: Duration = .milliseconds(400)

    /// The window's words read through Accessibility, or nil when it shows none, such as before Accessibility is granted.
    private static func accessibleText(of window: AXUIElement) async -> String? {
        var words = AXTree.text(of: window).trimmingCharacters(in: .whitespacesAndNewlines)
        if words.isEmpty {
            try? await Task.sleep(for: treeBuildWait)
            words = AXTree.text(of: window).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return words.isEmpty ? nil : String(words.suffix(mostAccessibleCharacters))
    }

    /// The target window right after an action, kept under the request's name as its evidence.
    static func proof(of app: NSRunningApplication, request: String) async -> String? {
        await image(of: app, title: nil).flatMap { write($0, into: Folder.proof, named: request) }
    }

    /// The target's window just before or just after an action, kept beside the request, with the words on
    /// the after one read here, quickly, since the brain is waiting on it.
    static func evidence(of app: NSRunningApplication, request: String, at moment: WitnessMoment) async -> Witness? {
        guard let image = await image(of: app, title: nil),
              let path = write(image, into: Folder.proof, named: "\(request)-\(moment.rawValue)")
        else { return nil }
        let name = app.localizedName ?? ""
        guard moment == .after else { return Witness(app: name, before: path) }
        let text = await read(image, level: .fast)
        return Witness(app: name, after: path, text: String(text.suffix(mostEvidenceCharacters)))
    }

    /// The words read away from the main thread, since reading a whole window keeps the app from speaking while it runs.
    private static func read(_ image: CGImage, level: VNRequestTextRecognitionLevel) async -> String {
        await Task.detached(priority: .userInitiated) { words(in: image, level: level) }.value
    }

    /// The words in a capture, read by the Mac itself, so they never leave it to be read.
    nonisolated private static func words(in image: CGImage, level: VNRequestTextRecognitionLevel) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    /// The window of the app that best matches, captured whether or not it is in front.
    private static func image(of app: NSRunningApplication, title: String?) async -> CGImage? {
        guard mayCapture(app) else { return nil }
        do {
            // Every window, covered or on another Space, since an action often happens behind the person.
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            let windows = content.windows.filter {
                $0.owningApplication?.processID == app.processIdentifier && $0.windowLayer == normalLayer && $0.frame.width > 1
            }
            let chosen = windows.first { title != nil && $0.title == title }
                ?? windows.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
            guard let chosen else { return nil }
            let configuration = SCStreamConfiguration()
            let scale = min(1, widest / chosen.frame.width) * (NSScreen.main?.backingScaleFactor ?? 1)
            configuration.width = Int(chosen.frame.width * scale)
            configuration.height = Int(chosen.frame.height * scale)
            configuration.showsCursor = false
            return try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: chosen), configuration: configuration
            )
        } catch {
            diary.note("could not capture \(app.localizedName ?? "the window"): \(error.localizedDescription)")
            return nil
        }
    }

    private static func write(_ image: CGImage, into folder: String, named name: String) -> String? {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        forgetOld(in: directory)
        let file = directory.appendingPathComponent(name).appendingPathExtension(UTType.png.preferredFilenameExtension ?? "png")
        guard let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? file.path : nil
    }

    /// Captures older than a day go, so the screen is never kept longer than it is useful.
    private static func forgetOld(in directory: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let cutoff = Date().addingTimeInterval(-keptFor)
        for file in files {
            let changed = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let changed, changed < cutoff { try? FileManager.default.removeItem(at: file) }
        }
    }
}
