import AppKit
import ApplicationServices

/// An editor's windows, brought to the front one at a time, since a link to an editor reaches only the window in
/// front and the terminal a session runs in may be in any of them.
@MainActor
enum EditorWindows {
    /// Enough windows to find the one holding a terminal, few enough that a person is never kept waiting long.
    private static let mostWindows = 8

    /// The editor's windows other than the one in front, which was asked already; empty without leave to read them.
    static func others(of app: NSRunningApplication) -> [AXUIElement] {
        let windows = AXTree.elements(AXUIElementCreateApplication(app.processIdentifier), kAXWindowsAttribute) ?? []
        let front = AXTree.frontWindow(of: app)
        return Array(windows.filter { window in front.map { !CFEqual($0, window) } ?? true }.prefix(mostWindows))
    }

    /// One window made the editor's main window and raised, with the editor in front, so the next link reaches it.
    static func raise(_ window: AXUIElement, of app: NSRunningApplication) -> Bool {
        if #available(macOS 14, *) { NSApp.yieldActivation(to: app) }
        app.activate()
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        return AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success
    }
}
