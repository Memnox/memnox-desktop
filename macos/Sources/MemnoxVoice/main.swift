import AppKit

// Top-level code runs on the main thread, which is where AppKit and the delegate live.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    // In the Dock like any app the person installed, so it is found, kept and quit where they look for apps.
    application.setActivationPolicy(.regular)
    application.run()
}
