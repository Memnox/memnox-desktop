import AppKit
import ApplicationServices
import MemnoxVoiceCore

/// Types a confirmed instruction into an agent's prompt the way a person would, a key at a time,
/// so the person watches the words go in and can take the keyboard back mid sentence. It types
/// only into the app it was given while that app stays in front, so it can never land elsewhere.
@MainActor
enum PromptTyping {
    private static let returnKey: CGKeyCode = 36

    private enum Timing {
        /// How many keys go in between checks that the app is still in front.
        static let frontCheckInterval = 4
        static let nanosecondsPerSecond = 1_000_000_000.0
        /// A beat before Return, since an agent reads text and Return arriving together as a paste.
        static let beforeReturn: TimeInterval = 0.25
        /// A moment for the conversation the link brought forward to settle and take focus.
        static let editorSettle: TimeInterval = 0.7
        /// Long enough for the editor to move focus to the message box once asked.
        static let focusSettle: TimeInterval = 0.12
        /// The slowest and quickest a key may go, and the whole run the pace aims to fit within.
        static let slowestKey: TimeInterval = 0.045
        static let quickestKey: TimeInterval = 0.010
        static let targetRun: TimeInterval = 3.0
        /// How far one key may stray either way from the base pace.
        static let jitter: ClosedRange<Double> = 0.7...1.3
        /// The breath after punctuation.
        static let breath: TimeInterval = 0.06
        /// The marks a person pauses after.
        static let breathMarks = ",.?!;:"

        static func nanoseconds(_ seconds: TimeInterval) -> UInt64 {
            UInt64(seconds * nanosecondsPerSecond)
        }
    }

    /// The Privacy and Security pane, opened at Accessibility.
    private static let accessibilitySettings = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    /// Electron's switch for building its accessibility tree, which has no kAX constant.
    private static let manualAccessibilityAttribute = "AXManualAccessibility"
    /// The placeholder a text field shows while empty.
    private static let placeholderValueAttribute = "AXPlaceholderValue"
    /// Deep enough for an editor's web content, shallow enough that a runaway tree ends.
    private static let maxTreeDepth = 40
    /// The editors Claude Code runs in when no app path was given: VS Code, Cursor and Windsurf.
    private static let editorBundleIdentifiers = ["com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf"]

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
        if let page = URL(string: accessibilitySettings) {
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
            if index % Timing.frontCheckInterval == 0, !inFront(app) {
                leaveOnClipboard(text)
                return Typed(.clipboard, "the person moved to another app while it was typing")
            }
            press(character)
            try? await Task.sleep(nanoseconds: pause(character))
        }
        try? await Task.sleep(nanoseconds: Timing.nanoseconds(Timing.beforeReturn))
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
        AXUIElementSetAttributeValue(element, manualAccessibilityAttribute as CFString, kCFBooleanTrue)
        try? await Task.sleep(nanoseconds: Timing.nanoseconds(Timing.editorSettle))
        guard let input = messageBox(in: element) else {
            return Typed(.clipboard, "no Claude message box was in focus")
        }
        AXUIElementSetAttributeValue(input, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        try? await Task.sleep(nanoseconds: Timing.nanoseconds(Timing.focusSettle))
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
        let base = min(Timing.slowestKey, max(Timing.quickestKey, Timing.targetRun / Double(max(count, 1))))
        return { character in
            let jitter = Double.random(in: Timing.jitter)
            let breath = Timing.breathMarks.contains(character) ? Timing.breath : 0
            return Timing.nanoseconds(base * jitter + breath)
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
        return apps.first { editorBundleIdentifiers.contains($0.bundleIdentifier ?? "") }
    }

    /// What Claude Code's message box calls itself to accessibility.
    private static let messageInput = "message input"

    /// The message box in focus, or the only one on screen, since several open conversations would be a guess.
    private static func messageBox(in app: AXUIElement) -> AXUIElement? {
        if let current = focused(in: app), isMessageBox(current) { return current }
        guard let window = element(app, kAXFocusedWindowAttribute) else { return nil }
        let found = boxes(under: window, depth: 0)
        return found.count == 1 ? found.first : nil
    }

    private static func boxes(under element: AXUIElement, depth: Int) -> [AXUIElement] {
        if isMessageBox(element) { return [element] }
        guard depth < maxTreeDepth, let children = elements(element, kAXChildrenAttribute) else { return [] }
        return children.flatMap { boxes(under: $0, depth: depth + 1) }
    }

    private static func focused(in app: AXUIElement) -> AXUIElement? {
        element(app, kAXFocusedUIElementAttribute)
    }

    private static func isMessageBox(_ element: AXUIElement?) -> Bool {
        guard let element else { return false }
        let names = [kAXDescriptionAttribute, kAXTitleAttribute, placeholderValueAttribute]
            .compactMap { string(element, $0) }
        return names.contains { $0.lowercased().contains(messageInput) }
    }

    /// Accessibility hands every attribute back untyped, so this is the one place one is read raw.
    private static func copyValue(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    /// An attribute that names another element, or nil when it holds anything else.
    private static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = copyValue(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func elements(_ element: AXUIElement, _ name: String) -> [AXUIElement]? {
        copyValue(element, name) as? [AXUIElement]
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String? {
        copyValue(element, name) as? String
    }
}
