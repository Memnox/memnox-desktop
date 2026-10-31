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
    /// A picture the brain is handed, in pixels: what the runtime tells it a screen picture is at most, so a point lands.
    private static let pictureWidest: CGFloat = 1280
    /// Small enough to send quickly with every label still legible.
    private static let pictureQuality = 0.7
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

    /// The app's front window as its words and an outline, read through Accessibility first since that takes a
    /// fraction of a capture and reading it; a picture is taken only when asked for, or when the window had no words.
    static func look(at app: NSRunningApplication, picture: LookPicture? = nil) async -> Sight {
        let started = ContinuousClock.now
        let window = AXTree.frontWindow(of: app)
        let title = window.flatMap { AXTree.string($0, kAXTitleAttribute) }
        let outline = window.map(AXTree.outline(of:))
        var text = window == nil ? nil : await accessibleText(of: app.processIdentifier)
        let screens = picture == .screens ? await screenPictures(around: app) : nil
        let image = picture == .window || (picture == nil && text == nil)
            ? await image(of: app, title: title, mostPixels: pictureWidest) : nil
        let path = image.flatMap { write($0, into: Folder.sight, named: UUID().uuidString, as: .jpeg) }
        let readOff = text == nil && image != nil
        // Only a window with no words is read off its picture, which is the slow part a words first look skips.
        if readOff, let image { text = await read(image, level: .accurate) }
        let how = text == nil ? "outline only" : readOff ? "words read off the picture" : "words through Accessibility"
        let took = (ContinuousClock.now - started).formatted(.units(allowed: [.milliseconds]))
        diary.note("looked at \(app.localizedName ?? "an app"): \(how)\(path == nil ? "" : ", with a picture")\(screens.map { ", \($0.count) screens" } ?? "") in \(took)")
        return Sight(app: app.localizedName ?? "", window: title, image: path, outline: outline, text: text, screens: screens)
    }

    /// Electron builds its web content's tree only once asked, so an empty first read waits this long and reads again.
    private static let treeBuildWait: Duration = .milliseconds(400)

    /// The window's words read through Accessibility away from the main thread, or nil when it shows none, such as
    /// before Accessibility is granted.
    private static func accessibleText(of pid: pid_t) async -> String? {
        let read = { await Task.detached(priority: .userInitiated) { AXTree.text(ofFrontWindowOf: pid) }.value }
        var words = await read().trimmingCharacters(in: .whitespacesAndNewlines)
        if words.isEmpty {
            try? await Task.sleep(for: treeBuildWait)
            words = await read().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return words.isEmpty ? nil : words
    }

    /// Every display as a picture, captured side by side and in `NSScreen.screens` order, which a point names by index;
    /// Memnox's own windows and every password manager are left out of them.
    private static func screenPictures(around app: NSRunningApplication) async -> [ScreenPicture]? {
        guard mayCapture(app) else { return nil }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else { return nil }
        let own = ProcessInfo.processInfo.processIdentifier
        let hidden = content.applications.filter { $0.processID == own || neverCaptured.contains($0.bundleIdentifier) }
        let batch = UUID().uuidString
        let screens = NSScreen.screens
        return await withTaskGroup(of: (Int, ScreenPicture?).self) { group in
            for (index, screen) in screens.enumerated() {
                guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else { continue }
                let filter = SCContentFilter(display: display, excludingApplications: hidden, exceptingWindows: [])
                let pixels = min(pictureWidest, screen.frame.width * screen.backingScaleFactor)
                let size = (width: Int(pixels.rounded()), height: Int((screen.frame.height * pixels / screen.frame.width).rounded()))
                let name = screen.localizedName
                group.addTask { @MainActor in
                    (index, await capture(filter, size: size, named: "\(batch)-screen-\(index)", called: name))
                }
            }
            var pictures: [(Int, ScreenPicture?)] = []
            for await each in group { pictures.append(each) }
            return pictures.sorted { $0.0 < $1.0 }.compactMap(\.1)
        }
    }

    /// One display captured at the size its picture is said to be, and written where the brain's pictures go.
    private static func capture(_ filter: SCContentFilter, size: (width: Int, height: Int), named name: String,
                                called displayName: String) async -> ScreenPicture? {
        let configuration = SCStreamConfiguration()
        configuration.width = size.width
        configuration.height = size.height
        configuration.showsCursor = false
        do {
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            guard let path = write(image, into: Folder.sight, named: name, as: .jpeg) else { return nil }
            return ScreenPicture(image: path, width: image.width, height: image.height, name: displayName)
        } catch {
            diary.note("could not capture a screen: \(error.localizedDescription)")
            return nil
        }
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

    /// The window of the app that best matches, captured whether or not it is in front; `mostPixels` caps its width in
    /// pixels for a picture the brain is handed, and evidence keeps its sharper size for reading.
    private static func image(of app: NSRunningApplication, title: String?, mostPixels: CGFloat? = nil) async -> CGImage? {
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
            let backing = NSScreen.main?.backingScaleFactor ?? 1
            let scale = mostPixels.map { min(backing, $0 / chosen.frame.width) } ?? min(1, widest / chosen.frame.width) * backing
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

    /// PNG keeps evidence exact; a JPEG at `pictureQuality` is what the brain is sent, a fraction of the bytes.
    private static func write(_ image: CGImage, into folder: String, named name: String, as type: UTType = .png) -> String? {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        forgetOld(in: directory)
        let file = directory.appendingPathComponent(name).appendingPathExtension(type.preferredFilenameExtension ?? "png")
        guard let destination = CGImageDestinationCreateWithURL(file as CFURL, type.identifier as CFString, 1, nil) else { return nil }
        let options = type == .jpeg ? [kCGImageDestinationLossyCompressionQuality: pictureQuality] as CFDictionary : nil
        CGImageDestinationAddImage(destination, image, options)
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

extension NSScreen {
    /// The display's id, which is how ScreenCaptureKit names the same screen.
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
