import AppKit
import ApplicationServices

/// Reads another app's controls through Accessibility: one attribute at a time for typing and
/// reading back, or a whole window as an outline for the brain to read when it looks.
@MainActor
enum AXTree {
    /// Electron's switch for building its accessibility tree, which has no kAX constant.
    static let manualAccessibilityAttribute = "AXManualAccessibility"

    private enum Outline {
        /// Deep enough for an editor's web content, shallow enough that a runaway tree ends.
        static let depth = 25
        /// Enough controls to say what a window holds, few enough that the brain reads it in one go.
        static let lines = 300
        /// Text longer than this is cut, since a whole document in one value drowns everything else.
        static let valueLength = 160
        /// Two spaces a level, so the outline reads as nesting.
        static let indent = "  "
    }

    private enum Words {
        /// A chat app's messages sit far deeper in its web content than any control the outline needs.
        static let depth = 80
        /// Enough elements for a long conversation, few enough that a huge page still answers in a moment.
        static let elements = 6_000
    }

    /// Roles that only hold other controls, left out of the outline unless they carry a title.
    private static let containers: Set<String> = [kAXGroupRole, kAXScrollAreaRole, kAXSplitGroupRole, kAXLayoutAreaRole, "AXUnknown"]

    /// The title of the window in front of the app with this process, read from any thread, since
    /// Accessibility answers off the main one and the question is asked while the person speaks.
    nonisolated static func frontWindowTitle(of pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        guard let window = element(app, kAXFocusedWindowAttribute) ?? element(app, kAXMainWindowAttribute) else { return nil }
        return string(window, kAXTitleAttribute).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The window in front of an app, or nil when it has none or Memnox may not read it.
    static func frontWindow(of app: NSRunningApplication) -> AXUIElement? {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        // Electron only builds its web content's accessibility tree when something asks for it.
        AXUIElementSetAttributeValue(element, manualAccessibilityAttribute as CFString, kCFBooleanTrue)
        return self.element(element, kAXFocusedWindowAttribute) ?? self.element(element, kAXMainWindowAttribute)
    }

    /// One control a line: its role, then its title or label, then its value, indented by depth.
    static func outline(of window: AXUIElement) -> String {
        var lines: [String] = []
        walk(window, depth: 0, into: &lines)
        return lines.joined(separator: "\n")
    }

    /// Every piece of text a window shows, joined in reading order, for reading back what an action left there
    /// and for reading a window when Memnox may not record the screen.
    static func text(of window: AXUIElement) -> String {
        var found: [String] = []
        var visited = 0
        collectText(window, depth: 0, visited: &visited, into: &found)
        return found.joined(separator: "\n")
    }

    private static func walk(_ element: AXUIElement, depth: Int, into lines: inout [String]) {
        guard lines.count < Outline.lines, depth < Outline.depth else { return }
        let role = string(element, kAXRoleAttribute) ?? ""
        let label = [kAXTitleAttribute, kAXDescriptionAttribute].lazy.compactMap { string(element, $0) }.first { !$0.isEmpty }
        let value = string(element, kAXValueAttribute).map { String($0.prefix(Outline.valueLength)) }
        let shown = !containers.contains(role) || label != nil
        if shown {
            let parts = [role.replacingOccurrences(of: "AX", with: ""), label.map { "\"\($0)\"" }, value.flatMap { $0.isEmpty ? nil : "= \($0)" }]
            lines.append(String(repeating: Outline.indent, count: depth) + parts.compactMap { $0 }.joined(separator: " "))
        }
        for child in elements(element, kAXChildrenAttribute) ?? [] {
            walk(child, depth: shown ? depth + 1 : depth, into: &lines)
        }
    }

    private static func collectText(_ element: AXUIElement, depth: Int, visited: inout Int, into found: inout [String]) {
        guard depth < Words.depth, visited < Words.elements else { return }
        visited += 1
        if let value = string(element, kAXValueAttribute), !value.isEmpty {
            found.append(value)
        } else if string(element, kAXRoleAttribute) == kAXStaticTextRole,
                  let label = [kAXTitleAttribute, kAXDescriptionAttribute].lazy.compactMap({ string(element, $0) }).first(where: { !$0.isEmpty }) {
            // Web content often puts a line of text in its label rather than its value.
            found.append(label)
        }
        for child in elements(element, kAXChildrenAttribute) ?? [] {
            collectText(child, depth: depth + 1, visited: &visited, into: &found)
        }
    }

    /// Accessibility hands every attribute back untyped, so this is the one place one is read raw.
    nonisolated private static func copyValue(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    /// An attribute that names another element, or nil when it holds anything else.
    nonisolated static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = copyValue(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    nonisolated static func elements(_ element: AXUIElement, _ name: String) -> [AXUIElement]? {
        copyValue(element, name) as? [AXUIElement]
    }

    nonisolated static func string(_ element: AXUIElement, _ name: String) -> String? {
        copyValue(element, name) as? String
    }
}
