import AppKit
import ApplicationServices

/// The lines of static text an app's window shows, read off the main thread, so a sent message can be seen arriving
/// in the conversation without the orb stalling while a long chat is walked.
enum WindowText {
    /// Few enough elements that a read before Return costs a moment, enough to reach a chat's newest lines.
    private static let mostElements = 2_000
    /// Deep enough for a chat app's messages, which Electron nests far below its window.
    private static let deepest = 80

    /// Every static text line in the app's window in front, bounded so a huge window still answers quickly.
    static func lines(inFrontWindowOf pid: pid_t) async -> [String] {
        await Task.detached(priority: .userInitiated) { read(pid) }.value
    }

    private static func read(_ pid: pid_t) -> [String] {
        let app = AXUIElementCreateApplication(pid)
        guard let window = AXTree.element(app, kAXFocusedWindowAttribute) ?? AXTree.element(app, kAXMainWindowAttribute) else { return [] }
        var found: [String] = []
        var visited = 0
        collect(window, depth: 0, visited: &visited, into: &found)
        return found
    }

    private static func collect(_ element: AXUIElement, depth: Int, visited: inout Int, into found: inout [String]) {
        guard depth < deepest, visited < mostElements else { return }
        visited += 1
        if AXTree.string(element, kAXRoleAttribute) == kAXStaticTextRole {
            // Web content often puts a line in its label rather than its value.
            let line = AXTree.string(element, kAXValueAttribute).flatMap { $0.isEmpty ? nil : $0 }
                ?? AXTree.string(element, kAXDescriptionAttribute)
            if let line, !line.isEmpty { found.append(line) }
            return
        }
        for child in AXTree.elements(element, kAXChildrenAttribute) ?? [] {
            collect(child, depth: depth + 1, visited: &visited, into: &found)
        }
    }
}
