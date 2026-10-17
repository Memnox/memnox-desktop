import AppKit

// Top-level code runs on the main thread, which is where AppKit and the delegate live.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    // A menu bar voice, never a Dock icon or a window of its own.
    application.setActivationPolicy(.accessory)
    application.run()
}
