import AppKit
import os

/// The app the person is working in, by name, kept as they switch: Memnox's own windows never
/// count, so talking to the island still reads as the editor or terminal they came from. The brain
/// reads a misheard word against it, and nothing acts on it.
final class FrontApp: Sendable {
    private let latest = OSAllocatedUnfairLock<(name: String, pid: pid_t)?>(initialState: nil)

    @MainActor init() {
        note(NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            self?.note(notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        }
    }

    /// The last app they were in other than Memnox, or nil before any.
    var name: String? { latest.withLock { $0?.name } }

    /// That app's window in front right now, by its title, which in an editor names the open folder.
    var windowTitle: String? {
        guard let pid = latest.withLock({ $0?.pid }) else { return nil }
        return AXTree.frontWindowTitle(of: pid)
    }

    /// That app as it runs, for putting the person back in it after Memnox had to borrow the screen.
    var running: NSRunningApplication? {
        latest.withLock { $0?.pid }.flatMap(NSRunningApplication.init(processIdentifier:))
    }

    private func note(_ app: NSRunningApplication?) {
        guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier, let name = app.localizedName, !name.isEmpty else { return }
        let pid = app.processIdentifier
        latest.withLock { $0 = (name, pid) }
    }
}
