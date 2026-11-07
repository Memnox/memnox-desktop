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
        /// What a password field shows in place of its value, so a secret never leaves in the words.
        static let masked = "[password field]"
    }

    /// How long a read of a window's words may run and how much of them is kept.
    struct WordBudget: Sendable {
        /// The walk stops here once it holds `least` characters, since a look is waited on.
        var soft: Duration = .milliseconds(400)
        /// And here whatever it holds, so a huge or hung tree never stalls the look.
        var hard: Duration = .seconds(1)
        var least = 1_500
        /// Kept from the end, where a chat's latest answer and a terminal's last lines are.
        var most = 8_000
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

    /// Every piece of text the app's front window shows, joined in reading order and bounded by the budget, read by
    /// process from any thread so a long tree never holds up the main one; password fields are masked.
    nonisolated static func text(ofFrontWindowOf pid: pid_t, budget: WordBudget = WordBudget()) -> String {
        let app = AXUIElementCreateApplication(pid)
        guard let window = element(app, kAXFocusedWindowAttribute) ?? element(app, kAXMainWindowAttribute) else { return "" }
        var walk = WordWalk(budget: budget, started: .now)
        collectText(window, depth: 0, walk: &walk)
        return String(walk.found.joined(separator: "\n").suffix(budget.most))
    }

    /// Where a walk for words stands: what it found, how many elements it opened, and when it began.
    private struct WordWalk {
        let budget: WordBudget
        let started: ContinuousClock.Instant
        var found: [String] = []
        var characters = 0
        var visited = 0

        var spent: Bool {
            let took = ContinuousClock.now - started
            return visited >= Words.elements || took >= budget.hard || (took >= budget.soft && characters >= budget.least)
        }

        mutating func add(_ line: String) {
            found.append(line)
            characters += line.count
        }
    }

    private static func walk(_ element: AXUIElement, depth: Int, into lines: inout [String]) {
        guard lines.count < Outline.lines, depth < Outline.depth else { return }
        let role = string(element, kAXRoleAttribute) ?? ""
        let label = [kAXTitleAttribute, kAXDescriptionAttribute].lazy.compactMap { string(element, $0) }.first { !$0.isEmpty }
        // A password field's value is never put in the outline, whatever it holds.
        let secure = string(element, kAXSubroleAttribute) == kAXSecureTextFieldSubrole
        let value = secure ? Words.masked : string(element, kAXValueAttribute).map { String($0.prefix(Outline.valueLength)) }
        let shown = !containers.contains(role) || label != nil
        if shown {
            let parts = [role.replacingOccurrences(of: "AX", with: ""), label.map { "\"\($0)\"" }, value.flatMap { $0.isEmpty ? nil : "= \($0)" }]
            lines.append(String(repeating: Outline.indent, count: depth) + parts.compactMap { $0 }.joined(separator: " "))
        }
        for child in elements(element, kAXChildrenAttribute) ?? [] {
            walk(child, depth: shown ? depth + 1 : depth, into: &lines)
        }
    }

    nonisolated private static func collectText(_ element: AXUIElement, depth: Int, walk: inout WordWalk) {
        guard depth < Words.depth, !walk.spent else { return }
        walk.visited += 1
        if string(element, kAXSubroleAttribute) == kAXSecureTextFieldSubrole {
            walk.add(Words.masked)
            return
        }
        if let value = string(element, kAXValueAttribute), !value.isEmpty {
            walk.add(value)
        } else if string(element, kAXRoleAttribute) == kAXStaticTextRole,
                  let label = [kAXTitleAttribute, kAXDescriptionAttribute].lazy.compactMap({ string(element, $0) }).first(where: { !$0.isEmpty }) {
            // Web content often puts a line of text in its label rather than its value.
            walk.add(label)
        }
        for child in elements(element, kAXChildrenAttribute) ?? [] {
            collectText(child, depth: depth + 1, walk: &walk)
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
