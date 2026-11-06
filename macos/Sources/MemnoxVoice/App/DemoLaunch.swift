import AppKit
import MemnoxVoiceCore

/// Demo mode, for judging the design with every page full: off unless the app is opened with `MEMNOX_DEMO=1` in its
/// environment or `--demo` among its arguments, so nobody who just opens Memnox ever sees it.
enum DemoLaunch {
    static let environmentKey = "MEMNOX_DEMO"
    static let argument = "--demo"
    /// Where scripts/bundle.sh puts the fixture inside the app.
    private static let folder = "Demo"
    private static let name = "power-user"
    private static let kind = "json"

    static let isOn: Bool = {
        let process = ProcessInfo.processInfo
        return process.environment[environmentKey] == "1" || process.arguments.contains(argument)
    }()

    /// Turns the demo on or off and reopens the app, since every reader is wired to one daemon link when it starts.
    @MainActor
    static func switchTo(_ on: Bool) {
        let configuration = NSWorkspace.OpenConfiguration()
        // Carried as the argument rather than kept, so quitting a demo always opens on this Mac's own agents next time.
        configuration.arguments = on ? [argument] : []
        // A second copy rather than this one brought forward, and this one quits once it is up.
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error {
                    NSLog("Memnox: could not reopen for the demo: \(error)")
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }

    /// The demo daemon, or nil when demo mode is off or its fixture cannot be read.
    static let link: DemoLink? = {
        guard isOn else { return nil }
        guard let data = fixture() else {
            NSLog("Memnox: demo mode is on but shared/demo/power-user.json is not in the app, so the real daemon is used")
            return nil
        }
        do {
            return try DemoLink(fixture: data)
        } catch {
            NSLog("Memnox: the demo fixture does not read: \(error)")
            return nil
        }
    }()

    /// Inside the app as bundled, else, in a debug build, the checkout it was built from, for a run straight out of swift build.
    private static func fixture() -> Data? {
        if let bundled = Bundle.main.url(forResource: name, withExtension: kind, subdirectory: folder),
           let data = try? Data(contentsOf: bundled) {
            return data
        }
        #if DEBUG
        // Five folders up from this file is memnox-desktop, which holds shared/ beside macos/; a release build carries no source path.
        let checkout = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/demo/power-user.json")
        return try? Data(contentsOf: checkout)
        #else
        return nil
        #endif
    }
}
