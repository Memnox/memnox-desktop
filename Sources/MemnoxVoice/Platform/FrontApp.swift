import AppKit
import os

/// The app the person is working in, by name, kept as they switch: Memnox's own windows never
/// count, so talking to the island still reads as the editor or terminal they came from. The brain
/// reads a misheard word against it, and nothing acts on it.
final class FrontApp: Sendable {
    private let latest = OSAllocatedUnfairLock<String?>(initialState: nil)

    @MainActor init() {
        note(NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            self?.note(notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        }
    }

    /// The last app they were in other than Memnox, or nil before any.
    var name: String? { latest.withLock { $0 } }

    private func note(_ app: NSRunningApplication?) {
        guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier, let name = app.localizedName, !name.isEmpty else { return }
        latest.withLock { $0 = name }
    }
}
