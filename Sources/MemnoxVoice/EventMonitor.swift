import AppKit

/// A watch on keyboard or mouse events that a caller holds as a typed handle and stops when done.
/// AppKit hands back an untyped token for each monitor, so this is the one place that token is kept.
@MainActor
final class EventMonitor {
    /// AppKit's token, kept only to give back to `NSEvent.removeMonitor`.
    private var token: Any?

    private init(token: Any?) {
        self.token = token
    }

    /// Watches events sent to other apps, which is how a click outside a panel is seen.
    static func global(_ mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) -> EventMonitor {
        EventMonitor(token: NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler))
    }

    /// Watches events sent to this app; the handler returns nil to swallow one.
    static func local(_ mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> NSEvent?) -> EventMonitor {
        EventMonitor(token: NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler))
    }

    /// Stops watching, and is safe to call more than once.
    func stop() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }
}

/// The virtual key codes the app listens for, numbered as Carbon's kVK constants number them.
enum KeyCode {
    static let escape: UInt16 = 53
}
