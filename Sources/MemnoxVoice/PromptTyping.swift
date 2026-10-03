import AppKit
import ApplicationServices
import MemnoxVoiceCore

/// Types a confirmed instruction into an agent's prompt the way a person would, a key at a time,
/// so the person watches the words go in and can take the keyboard back mid sentence. It types
/// only into the app it was given while that app stays in front, so it can never land elsewhere.
@MainActor
enum PromptTyping {
    private static let returnKey: CGKeyCode = 36

    /// Whether Memnox may press keys for the person. The system sheet is shown at most once per
    /// launch: shown on every instruction it reads as a bug, and a person who said no meant it.
    static func allowed() -> Bool {
        if AXIsProcessTrusted() { return true }
        guard !asked else { return false }
        asked = true
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        if AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary) { return true }
        // A grant left over from an earlier build shows as on and does nothing, and then no sheet appears,
        // so the page it is switched on in is opened as well.
        if let page = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(page)
        }
        return false
    }

    private static var asked = false

    /// Types the words into whatever has focus in the app, then presses Return. Stops, and leaves
    /// the words on the clipboard, the moment the app is no longer in front.
    static func type(_ text: String, into app: NSRunningApplication) async -> Typed {
        let words = Array(oneLine(text))
        let pause = keyPause(for: words.count)
        for (index, character) in words.enumerated() {
            // Checked every few keys rather than every key: a click away takes longer than that to matter.
            if index % 4 == 0, !inFront(app) {
                leaveOnClipboard(text)
                return Typed(.clipboard, "the person moved to another app while it was typing")
            }
            press(character)
            try? await Task.sleep(nanoseconds: pause(character))
        }
        // A beat before Return, since an agent reads text and Return arriving together as a paste.
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard inFront(app) else {
            leaveOnClipboard(text)
            return Typed(.clipboard, "the person moved to another app before it was sent")
        }
        press(returnKey)
        return .landed
    }

    /// Brings the conversation's message box into focus in the editor in front, then types into it.
    static func typeIntoEditor(_ text: String, inAppAt path: String?) async -> Typed {
        guard allowed() else { return Typed(.notAllowed, "Memnox is not allowed to type yet") }
        guard let app = running(path) else { return Typed(.clipboard, "the editor is not running") }
        app.activate()
        let element = AXUIElementCreateApplication(app.processIdentifier)
        // Electron only builds its web content's accessibility tree when something asks for it.
        AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        // A moment for the conversation the link brought forward to settle and take focus.
        try? await Task.sleep(nanoseconds: 700_000_000)
        guard let input = messageBox(in: element) else {
            return Typed(.clipboard, "no Claude message box was in focus")
        }
        AXUIElementSetAttributeValue(input, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        try? await Task.sleep(nanoseconds: 120_000_000)
        guard isMessageBox(focused(in: element)) else {
            return Typed(.clipboard, "the message box would not take focus")
        }
        return await type(text, into: app)
    }

    /// The words left on the clipboard, for when they cannot be typed safely.
    static func leaveOnClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// One line, since a newline typed into an agent's prompt sends half the instruction.
    static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }

    /// Quick enough that a few sentences go in within about three seconds, slow enough to be watched,
    /// with a little unevenness and a breath after punctuation, the way somebody types.
    private static func keyPause(for count: Int) -> (Character) -> UInt64 {
        let base = min(0.045, max(0.010, 3.0 / Double(max(count, 1))))
        return { character in
            let jitter = Double.random(in: 0.7...1.3)
            let breath = ",.?!;:".contains(character) ? 0.06 : 0
            return UInt64((base * jitter + breath) * 1_000_000_000)
        }
    }

    private static func inFront(_ app: NSRunningApplication) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
    }

    /// One character as its own key press, with no modifier the person may be holding carried onto it.
    private static func press(_ character: Character) {
        let units = Array(String(character).utf16)
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
            event?.flags = []
            event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            event?.post(tap: .cghidEventTap)
        }
    }

    private static func press(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            event?.flags = []
            event?.post(tap: .cghidEventTap)
        }
    }

    private static func running(_ path: String?) -> NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications
        if let path, let found = apps.first(where: { $0.bundleURL?.path == path }) { return found }
        let editors = ["com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf"]
        return apps.first { editors.contains($0.bundleIdentifier ?? "") }
    }

    /// What Claude Code's message box calls itself to accessibility.
    private static let messageInput = "message input"

    /// The message box in focus, or the only one on screen, since several open conversations would be a guess.
    private static func messageBox(in app: AXUIElement) -> AXUIElement? {
        if let current = focused(in: app), isMessageBox(current) { return current }
        guard let window = attribute(app, kAXFocusedWindowAttribute) else { return nil }
        let found = boxes(under: window as! AXUIElement, depth: 0) // A window attribute is always an element.
        return found.count == 1 ? found.first : nil
    }

    private static func boxes(under element: AXUIElement, depth: Int) -> [AXUIElement] {
        if isMessageBox(element) { return [element] }
        guard depth < 40, let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return [] }
        return children.flatMap { boxes(under: $0, depth: depth + 1) }
    }

    private static func focused(in app: AXUIElement) -> AXUIElement? {
        guard let value = attribute(app, kAXFocusedUIElementAttribute) else { return nil }
        return (value as! AXUIElement) // The focused element attribute is always an element.
    }

    private static func isMessageBox(_ element: AXUIElement?) -> Bool {
        guard let element else { return false }
        let names = [kAXDescriptionAttribute, kAXTitleAttribute, "AXPlaceholderValue"]
            .compactMap { attribute(element, $0) as? String }
        return names.contains { $0.lowercased().contains(messageInput) }
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
}
