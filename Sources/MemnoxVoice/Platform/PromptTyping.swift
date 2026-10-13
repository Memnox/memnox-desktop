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
        /// How many keys go in between checks that the app is still in front: every one, so no key of the
        /// message ever lands in a prompt that took the front, such as a password field.
        static let frontCheckInterval = 1
        static let nanosecondsPerSecond = 1_000_000_000.0
        /// A beat before Return, since an agent reads text and Return arriving together as a paste.
        static let beforeReturn: TimeInterval = 0.15
        /// A moment for the conversation the link brought forward to settle and take focus.
        static let editorSettle: TimeInterval = 0.3
        /// How often, and how many more times, the message box is looked for: a panel opened by the
        /// link a moment ago is still drawing its box after the settle, which failed the first send.
        static let boxPoll: TimeInterval = 0.1
        static let boxLooks = 20
        /// How many more times the box is read after Return for it to empty, about two seconds.
        static let sentLooks = 20
        /// Long enough for a desktop app a link just launched to open its window and draw its box.
        static let launchLooks = 60
        /// Longer for the box itself, since a page such as a new Claude Code chat draws well after its window.
        static let appBoxLooks = 150
        /// About ten seconds for a prompt link's words to reach the chat, which may first wait on the person to allow the link.
        static let prefillLooks = 100
        /// About a second to take the front back from Memnox's own window.
        static let takeBackLooks = 4
        /// Half a minute for the person to answer a system prompt such as Touch ID before typing gives up.
        static let promptLooks = 300
        /// Long enough for the editor to move focus to the message box once asked.
        static let focusSettle: TimeInterval = 0.12
        /// The slowest and quickest a key may go, and the whole run the pace aims to fit within.
        static let slowestKey: TimeInterval = 0.012
        static let quickestKey: TimeInterval = 0.001
        static let targetRun: TimeInterval = 0.4
        /// How far one key may stray either way from the base pace.
        static let jitter: ClosedRange<Double> = 0.7...1.3
        /// The breath after punctuation.
        static let breath: TimeInterval = 0.015
        /// The marks a person pauses after.
        static let breathMarks = ",.?!;:"
        /// How long the words sit in the box before Return, so the person can start fixing one.
        static let editGrace: TimeInterval = 0.4
        /// How often the box is read while the person edits it.
        static let editPoll: TimeInterval = 0.5
        /// How long an edit is waited on before it is let go unlearned, since a message left unsent taught nothing.
        static let editWatch: TimeInterval = 120

        static func nanoseconds(_ seconds: TimeInterval) -> UInt64 {
            UInt64(seconds * nanosecondsPerSecond)
        }
    }

    /// The value of kAXTrustedCheckOptionPrompt, written out because Swift 6 refuses that global as shared mutable state.
    private static let trustedCheckPrompt = "AXTrustedCheckOptionPrompt"
    /// The Privacy and Security pane, opened at Accessibility.
    private static let accessibilitySettings = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    /// Electron's switch for building its accessibility tree, which has no kAX constant.
    private static let manualAccessibilityAttribute = "AXManualAccessibility"
    /// The switch an assistive app sets, which Chromium also waits for before building its tree.
    private static let enhancedInterfaceAttribute = "AXEnhancedUserInterface"
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
        // A grant left over from an earlier build shows as on and does nothing, and no sheet appears for it, which is
        // what "I gave you access" meant. Memnox's own entries are forgotten first, so the sheet and the switch that
        // follow are for this build; then the page it is switched on in is opened.
        Task { @MainActor in
            await SettingsPane.typing.forgetEarlierBuilds()
            if AXIsProcessTrustedWithOptions([trustedCheckPrompt: true] as CFDictionary) { return }
            if let page = URL(string: accessibilitySettings) { NSWorkspace.shared.open(page) }
        }
        return false
    }

    private static var asked = false

    /// Types the words into whatever has focus in the app, then presses Return. Stops, and leaves
    /// the words on the clipboard, the moment the app is no longer in front. Given the message box,
    /// it waits a moment first: the person fixing a word takes the message over and sends it
    /// themselves, and `sent` hears what they sent so the word they fixed is learned.
    static func type(
        _ text: String, into app: NSRunningApplication, box: AXUIElement? = nil, sent: ((String) -> Void)? = nil
    ) async -> Typed {
        let words = Array(oneLine(text))
        let pause = keyPause(for: words.count)
        for (index, character) in words.enumerated() {
            // Checked every few keys rather than every key: a click away takes longer than that to matter.
            if index % Timing.frontCheckInterval == 0, !(await stillInFront(app, box: box)) {
                leaveOnClipboard(text)
                return Typed(.clipboard, "\(frontName()) came to the front while it was typing")
            }
            press(character)
            try? await Task.sleep(nanoseconds: pause(character))
        }
        try? await Task.sleep(nanoseconds: Timing.nanoseconds(Timing.beforeReturn))
        if let box, let typed = string(box, kAXValueAttribute) {
            try? await Task.sleep(nanoseconds: Timing.nanoseconds(Timing.editGrace))
            if let now = string(box, kAXValueAttribute), now != typed {
                Task { await watchEdit(box, from: now, sent: sent) }
                return .landed
            }
        }
        guard await stillInFront(app, box: box) else {
            leaveOnClipboard(text)
            return Typed(.clipboard, "\(frontName()) came to the front before it was sent")
        }
        press(returnKey)
        guard let box else { return .landed }
        return Typed.landed.verified(await emptied(box, after: oneLine(text)))
    }

    /// The box read until it empties, which is the app taking the message; nil when it never did.
    private static func emptied(_ box: AXUIElement, after words: String) async -> Proof? {
        for _ in 0..<Timing.sentLooks {
            try? await Task.sleep(nanoseconds: Timing.nanoseconds(Timing.boxPoll))
            let now = string(box, kAXValueAttribute)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if now?.isEmpty == true { return Proof(checked: "its message box taking the words and emptying", seen: words) }
        }
        return nil
    }

    /// Brings the conversation's message box into focus in the editor in front, then types into it.
    static func typeIntoEditor(_ text: String, inAppAt path: String?, sent: ((String) -> Void)? = nil) async -> Typed {
        guard allowed() else { return Typed(.notAllowed, "Memnox is not allowed to type yet") }
        guard let app = running(path) else { return Typed(.clipboard, "the editor is not running") }
        app.activate()
        let element = AXUIElementCreateApplication(app.processIdentifier)
        // Electron only builds its web content's accessibility tree when something asks for it.
        AXUIElementSetAttributeValue(element, manualAccessibilityAttribute as CFString, kCFBooleanTrue)
        try? await Task.sleep(nanoseconds: Timing.nanoseconds(Timing.editorSettle))
        var found = messageBox(in: element)
        for _ in 0..<Timing.boxLooks where found == nil {
            try? await Task.sleep(nanoseconds: Timing.nanoseconds(Timing.boxPoll))
            found = messageBox(in: element)
        }
        guard let input = found else {
            // Asked of the person, since a click in the box is the one thing that always finds it, and it is learned from then on.
            return Typed(.clipboard, "Claude's message box could not be found in the editor", hint: .clickMessageBox(app: app.localizedName ?? "the editor"))
        }
        learn(input)
        AXUIElementSetAttributeValue(input, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        try? await Task.sleep(nanoseconds: Timing.nanoseconds(Timing.focusSettle))
        guard isMessageBox(focused(in: element)) else {
            return Typed(.clipboard, "the message box would not take focus")
        }
        return await type(text, into: app, box: input, sent: sent)
    }

    /// Reads the box while the person edits it, and hands over the last of it once they send it,
    /// which empties the box. Left unsent too long, it is let go: nothing was confirmed.
    private static func watchEdit(_ box: AXUIElement, from start: String, sent: ((String) -> Void)?) async {
        var last = start
        let polls = Int(Timing.editWatch / Timing.editPoll)
        for _ in 0..<polls {
            try? await Task.sleep(nanoseconds: Timing.nanoseconds(Timing.editPoll))
            let now = string(box, kAXValueAttribute)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if now.isEmpty {
                sent?(last)
                return
            }
            last = now
        }
    }

    /// kVK_ANSI_V, for Command V.
    private static let vKey: CGKeyCode = 9
    /// Long enough for the app in front to read the clipboard before what was on it is put back.
    private static let pasteSettle: TimeInterval = 0.4

    /// Dictated words put where the cursor is in the app in front, all at once as a paste does, and the clipboard
    /// given back exactly as it was, images and files included. False when that app is no longer in front, so the
    /// words are left on the clipboard instead.
    static func paste(_ text: String, into app: NSRunningApplication?) async -> Bool {
        guard allowed(), let app, inFront(app) else {
            leaveOnClipboard(text)
            return false
        }
        let board = NSPasteboard.general
        let earlier = ClipboardSnapshot(of: board)
        board.clearContents()
        board.setString(text, forType: .string)
        let ours = board.changeCount
        pressCommand(vKey)
        try? await Task.sleep(nanoseconds: Timing.nanoseconds(pasteSettle))
        // Only while the dictation is still what is there, so a copy made meanwhile is never undone.
        if board.changeCount == ours { earlier.restore(to: board) }
        return true
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
        let base = basePause(for: count)
        return { character in
            let jitter = Double.random(in: Timing.jitter)
            let breath = Timing.breathMarks.contains(character) ? Timing.breath : 0
            return Timing.nanoseconds(base * jitter + breath)
        }
    }

    /// The even pace under the unevenness, for a terminal's own scripting that types at one pace.
    static func basePause(for count: Int) -> TimeInterval {
        min(Timing.slowestKey, max(Timing.quickestKey, Timing.targetRun / Double(max(count, 1))))
    }

    private static func inFront(_ app: NSRunningApplication) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
    }

    /// Whether the app is still in front, taking it back when Memnox's own window took it, since that
    /// was a card or the orb and never the person, who twice heard they had moved when they had not.
    private static func stillInFront(_ app: NSRunningApplication, box: AXUIElement?) async -> Bool {
        if inFront(app) { return true }
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        if isSystemPrompt(front) {
            diary.note("\(front.localizedName ?? "a system prompt") asked the person something while typing, so typing waits for it")
            for _ in 0..<Timing.promptLooks where NSWorkspace.shared.frontmostApplication?.processIdentifier == front.processIdentifier {
                try? await Task.sleep(nanoseconds: Timing.nanoseconds(Timing.boxPoll))
            }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier != front.processIdentifier else { return false }
        } else if front.processIdentifier != NSRunningApplication.current.processIdentifier {
            return false
        } else {
            diary.note("Memnox's own window took the front from \(app.localizedName ?? "the app") while typing, so it is handed back")
        }
        for _ in 0..<Timing.takeBackLooks where !inFront(app) {
            if #available(macOS 14, *) { NSApp.yieldActivation(to: app) }
            app.activate()
            try? await Task.sleep(nanoseconds: Timing.nanoseconds(Timing.boxPoll))
        }
        guard inFront(app) else { return false }
        if let box { AXUIElementSetAttributeValue(box, kAXFocusedAttribute as CFString, kCFBooleanTrue) }
        try? await Task.sleep(nanoseconds: Timing.nanoseconds(Timing.focusSettle))
        return true
    }

    /// A prompt the system puts up, such as Touch ID or a password, which takes the front for a moment and
    /// gives it back: it is an agent with no Dock icon, never an app the person switched to.
    private static func isSystemPrompt(_ app: NSRunningApplication) -> Bool {
        app.activationPolicy != .regular && app.processIdentifier != NSRunningApplication.current.processIdentifier
    }

    /// The app in front by name, so a failure says who took it rather than guessing it was the person.
    private static func frontName() -> String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? "another app"
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

    /// One window, one tab: the count at which whatever is in front can only be the session's.
    private static let soleView = 1
    /// Where a walk down the accessibility tree begins.
    private static let rootDepth = 0
    /// What chat apps call the button that stops a reply, as Stop or Stop generating.
    private static let stopLabel = "stop"

    /// Whether the app shows one window holding one tab, so whatever it has in front is the only terminal it has.
    static func showsOneView(_ app: NSRunningApplication) -> Bool {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        guard let windows = elements(element, kAXWindowsAttribute), windows.count == soleView, let window = windows.first else { return false }
        let tabGroups = (elements(window, kAXChildrenAttribute) ?? []).filter { string($0, kAXRoleAttribute) == kAXTabGroupRole }
        return tabGroups.allSatisfy { (elements($0, kAXTabsAttribute) ?? elements($0, kAXChildrenAttribute) ?? []).count <= soleView }
    }

    /// Windows and the tabs inside them, counted so a terminal that opened a new one can be told from one that did not.
    static func viewCount(_ app: NSRunningApplication?) -> Int {
        guard let app else { return 0 }
        let windows = elements(AXUIElementCreateApplication(app.processIdentifier), kAXWindowsAttribute) ?? []
        return windows.reduce(0) { total, window in
            let tabs = (elements(window, kAXChildrenAttribute) ?? [])
                .filter { string($0, kAXRoleAttribute) == kAXTabGroupRole }
                .map { (elements($0, kAXTabsAttribute) ?? []).count }
                .max() ?? 0
            return total + max(tabs, soleView)
        }
    }

    /// Raises the app's window whose title names this, such as the session's folder; false when none does.
    @discardableResult
    static func raiseWindow(of app: NSRunningApplication, titled name: String) -> Bool {
        guard !name.isEmpty else { return false }
        let windows = elements(AXUIElementCreateApplication(app.processIdentifier), kAXWindowsAttribute) ?? []
        let named = windows.filter { (string($0, kAXTitleAttribute) ?? "").localizedCaseInsensitiveContains(name) }
        // Only one, since raising a guess among two would show the person the wrong session.
        guard named.count == soleView, let window = named.first else { return false }
        return AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success
    }

    /// A shortcut with Command held, such as Command W to close or Command N for a new chat, into the app in front.
    static func pressCommand(_ key: CGKeyCode, shift: Bool = false) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            event?.flags = shift ? [.maskCommand, .maskShift] : .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    /// kVK_ANSI_W, kVK_ANSI_N and kVK_ANSI_P, written out so Carbon need not be imported for three keys.
    static let wKey: CGKeyCode = 13
    static let nKey: CGKeyCode = 45
    static let pKey: CGKeyCode = 35

    /// The command VS Code and the editors built on it run to load an extension put in since the window opened.
    private static let restartExtensionHostCommand = "Developer: Restart Extension Host"
    /// Long enough for the command palette to open, and then to find the command typed into it.
    private static let paletteSettle: TimeInterval = 0.35

    /// The step the person used to be asked to take by hand, taken where they watch: the editor in
    /// front opens its command palette and restarts its extensions, so the copy on disk is the one running.
    static func restartExtensionHost(in app: NSRunningApplication) async -> Bool {
        guard allowed(), inFront(app) else { return false }
        pressCommand(pKey, shift: true)
        try? await Task.sleep(nanoseconds: Timing.nanoseconds(paletteSettle))
        guard inFront(app) else { return false }
        for character in restartExtensionHostCommand { press(character) }
        try? await Task.sleep(nanoseconds: Timing.nanoseconds(paletteSettle))
        guard inFront(app) else { return false }
        press(returnKey)
        return true
    }

    /// Escape in an editor's agent panel, pressed with its message box in focus so it reaches the conversation.
    static func escapeInEditor(inAppAt path: String?) async -> Bool {
        guard let app = running(path) else { return false }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        guard let box = messageBox(in: element) else { return false }
        AXUIElementSetAttributeValue(box, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        try? await Task.sleep(nanoseconds: Timing.nanoseconds(Timing.focusSettle))
        guard inFront(app) else { return false }
        press(escapeKey)
        return true
    }

    /// The button an app shows while it writes a reply, Stop or Stop generating, pressed; false when it shows none.
    static func pressStop(in app: NSRunningApplication) -> Bool {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        guard let button = stopButton(under: element, depth: rootDepth) else { return false }
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }

    private static func stopButton(under element: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth < maxTreeDepth else { return nil }
        if string(element, kAXRoleAttribute) == kAXButtonRole {
            let label = [string(element, kAXTitleAttribute), string(element, kAXDescriptionAttribute)]
                .compactMap { $0?.lowercased() }
            if label.contains(where: { $0 == stopLabel || $0.hasPrefix(stopLabel + " ") }) { return element }
        }
        for child in elements(element, kAXChildrenAttribute) ?? [] {
            if let found = stopButton(under: child, depth: depth + 1) { return found }
        }
        return nil
    }

    /// Long enough between keys for a terminal app to redraw its list before the next one moves through it.
    private static let keyGap: TimeInterval = 0.08

    /// Keys pressed one after another in the app in front, answering an agent's question; the caller checks which app.
    static func press(_ keys: [TerminalPress]) async {
        for each in keys {
            switch each {
            case .key(let key): press(CGKeyCode(key.code))
            case .character(let character): press(character)
            }
            try? await Task.sleep(nanoseconds: Timing.nanoseconds(keyGap))
        }
    }

    /// The Escape key, which stops an agent's turn in the terminal in front; the caller checks which one that is.
    static func pressEscape() {
        press(escapeKey)
    }

    /// kVK_Escape, written out so Carbon need not be imported for one key.
    private static let escapeKey: CGKeyCode = 53

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

    /// Types into a desktop app's own message box, Claude, Codex or Hermes: the text area in focus, or
    /// the only one in its window, so the words never land in a field picked by guess. Waits for an app
    /// a link just launched to be running, then sends with Return as a person would.
    static func typeIntoApp(_ text: String, inAppAt path: String) async -> Typed {
        guard allowed() else { return Typed(.notAllowed, "Memnox is not allowed to type yet") }
        var found = running(at: path)
        for _ in 0..<Timing.launchLooks where found == nil {
            try? await Task.sleep(nanoseconds: Timing.nanoseconds(Timing.boxPoll))
            found = running(at: path)
        }
        guard let app = found else { return Typed(.clipboard, "the app did not start") }
        guard await bringForward(app) else { return Typed(.clipboard, "the app did not come to the front") }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        // Electron only builds its web content's accessibility tree when something asks for it, and
        // Chromium waits for the switch assistive apps set as well.
        AXUIElementSetAttributeValue(element, manualAccessibilityAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(element, enhancedInterfaceAttribute as CFString, kCFBooleanTrue)
        try? await Task.sleep(nanoseconds: Timing.nanoseconds(Timing.editorSettle))
        // Polled, since a window just opened, such as Codex's, draws its composer well after a button takes focus.
        var box = textArea(in: element)
        for _ in 0..<Timing.appBoxLooks where box == nil {
            try? await Task.sleep(nanoseconds: Timing.nanoseconds(Timing.boxPoll))
            box = textArea(in: element)
        }
        // A new chat puts the keyboard in its message box, so an editable field in focus is that box.
        guard let input = box ?? focused(in: element).flatMap({ isEditable($0) ? $0 : nil }) else {
            let role = focused(in: element).flatMap { string($0, kAXRoleAttribute) } ?? "nothing"
            diary.note("no message box in \(app.localizedName ?? "the app"): \(role) has focus, and its window shows no text area")
            return Typed(.clipboard, "no message box was found in the app")
        }
        let hadFocus = holdsFocus(input, in: element)
        AXUIElementSetAttributeValue(input, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        try? await Task.sleep(nanoseconds: Timing.nanoseconds(Timing.focusSettle))
        // A box found in the window rather than in focus is typed into only once it holds the focus, since a key on a button presses it.
        if !hadFocus {
            let role = string(input, kAXRoleAttribute) ?? "a control"
            guard holdsFocus(input, in: element) else {
                diary.note("\(app.localizedName ?? "the app") showed its message box as \(role), which would not take focus")
                return Typed(.clipboard, "the message box would not take focus")
            }
            diary.note("found \(app.localizedName ?? "the app")'s message box as \(role) in its window and put the keyboard there")
        }
        return await type(text, into: app, box: input)
    }

    /// Sends what an app's own prompt link left in its chat: only with the app already in front, its chat input in focus
    /// and holding exactly those words, then Return. Nil when anything does not check out, so the words wait for the person.
    static func sendPrefilled(_ words: String, inAppAt path: String) async -> Typed? {
        guard AXIsProcessTrusted(), let app = running(at: path) else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        // Electron only builds its web content's accessibility tree when something asks for it.
        AXUIElementSetAttributeValue(element, manualAccessibilityAttribute as CFString, kCFBooleanTrue)
        let wanted = spaced(words)
        var box: AXUIElement?
        for _ in 0..<Timing.prefillLooks where box == nil {
            box = prefilledBox(holding: wanted, in: element, of: app)
            if box == nil { try? await Task.sleep(nanoseconds: Timing.nanoseconds(Timing.boxPoll)) }
        }
        guard let box else {
            diary.note("left the words in \(app.localizedName ?? "the app")'s chat, since its focused input did not hold them with the app in front")
            return nil
        }
        try? await Task.sleep(nanoseconds: Timing.nanoseconds(Timing.beforeReturn))
        // Read once more right before Return, so a word the person changed meanwhile is never sent for them.
        guard prefilledBox(holding: wanted, in: element, of: app) != nil else { return nil }
        press(returnKey)
        diary.note("sent what \(app.localizedName ?? "the app")'s prompt link left in its chat")
        return Typed.landed.verified(await cleared(box, in: element, after: wanted))
    }

    /// The chat input in focus when the app is in front and the input holds exactly these words.
    private static func prefilledBox(holding words: String, in app: AXUIElement, of running: NSRunningApplication) -> AXUIElement? {
        guard inFront(running), let box = focusedComposer(in: app),
              let value = string(box, kAXValueAttribute), spaced(value) == words
        else { return nil }
        return box
    }

    /// The editable input the focus sits in, the focused element itself or the nearest composer above it.
    private static func focusedComposer(in app: AXUIElement) -> AXUIElement? {
        var current = focused(in: app)
        for _ in 0..<deepestAncestry {
            guard let node = current else { return nil }
            if isComposer(node) { return node }
            current = AXTree.element(node, kAXParentAttribute)
        }
        return nil
    }

    /// The input read after Return until it empties, which is the app taking the words; nil when it never did.
    private static func cleared(_ box: AXUIElement, in app: AXUIElement, after words: String) async -> Proof? {
        for _ in 0..<Timing.sentLooks {
            try? await Task.sleep(nanoseconds: Timing.nanoseconds(Timing.boxPoll))
            // A chat that draws a fresh input once it sends is read through the focus instead.
            let now = string(box, kAXValueAttribute) ?? focusedComposer(in: app).flatMap { string($0, kAXValueAttribute) }
            if let now, spaced(now).isEmpty { return Proof(checked: "its chat input holding the words, then emptying after Return", seen: words) }
        }
        return nil
    }

    /// Runs of whitespace as one space and none at either end, since an input may wrap or pad what it holds.
    private static func spaced(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Whether the focus sits in this input, on it or on something inside it, as web content reports a caret.
    private static func holdsFocus(_ input: AXUIElement, in app: AXUIElement) -> Bool {
        if boolean(input, kAXFocusedAttribute) { return true }
        var current = focused(in: app)
        for _ in 0..<deepestAncestry {
            guard let node = current else { return false }
            if CFEqual(node, input) { return true }
            current = AXTree.element(node, kAXParentAttribute)
        }
        return false
    }

    private static func boolean(_ element: AXUIElement, _ name: String) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return false }
        return (value as? Bool) ?? false
    }

    /// Asked again until it is really in front: an app a link just launched is still opening its window,
    /// and since macOS 14 an app only comes forward when the one in front, Memnox, yields to it.
    private static func bringForward(_ app: NSRunningApplication) async -> Bool {
        for _ in 0..<Timing.launchLooks {
            if inFront(app) { return true }
            if #available(macOS 14, *) { NSApp.yieldActivation(to: app) }
            app.activate()
            try? await Task.sleep(nanoseconds: Timing.nanoseconds(Timing.boxPoll))
        }
        return inFront(app)
    }

    private static func running(at path: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleURL?.standardizedFileURL.path == URL(fileURLWithPath: path).standardizedFileURL.path }
    }

    /// The box in focus, or else the editable box lowest in the window: every chat app keeps its message
    /// box at the bottom and any search field above it, whatever its version, language or layout.
    private static func textArea(in app: AXUIElement) -> AXUIElement? {
        // A focused field is taken only when it is a text area, since one in focus may be a search field.
        if let current = focused(in: app), isTextArea(current) { return current }
        guard let window = element(app, kAXFocusedWindowAttribute) ?? element(app, kAXMainWindowAttribute)
                ?? elements(app, kAXWindowsAttribute)?.first
        else { return nil }
        var visited = 0
        let found = textAreas(under: window, depth: 0, visited: &visited)
        return found.count <= 1 ? found.first : found.max { top(of: $0) < top(of: $1) }
    }

    /// Where an element's top edge sits on screen, which grows downward; nil reads as the very top.
    private static func top(of element: AXUIElement) -> CGFloat {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return -.greatestFiniteMagnitude }
        var point = CGPoint.zero
        // Checked to be an AXValue just above, which is the only type a position comes back as.
        AXValueGetValue(value as! AXValue, .cgPoint, &point)
        return point.y
    }

    /// Deep enough for a chat app's composer, which Electron nests far below its window, as AXTree reads words.
    private static let composerDepth = 80
    /// Enough elements for a long conversation, few enough that one look still answers in a moment.
    private static let composerElements = 6_000

    private static func textAreas(under element: AXUIElement, depth: Int, visited: inout Int) -> [AXUIElement] {
        visited += 1
        if isComposer(element) { return [element] }
        guard depth < composerDepth, visited < composerElements, let children = elements(element, kAXChildrenAttribute) else { return [] }
        var found: [AXUIElement] = []
        for child in children { found += textAreas(under: child, depth: depth + 1, visited: &visited) }
        return found
    }

    private static func isTextArea(_ element: AXUIElement) -> Bool {
        string(element, kAXRoleAttribute) == kAXTextAreaRole
    }

    /// Chromium's pointer from inside editable web content to its outermost editable element, which has no kAX constant.
    private static let highestEditableAncestorAttribute = "AXHighestEditableAncestor"

    /// A text area, an editable field, or the root of editable web content, which is how a contenteditable composer
    /// shows: a group whose value may be set, or the element its own content names as its outermost editable one.
    private static func isComposer(_ element: AXUIElement) -> Bool {
        if isTextArea(element) || isEditable(element) { return true }
        if let highest = AXTree.element(element, highestEditableAncestorAttribute), CFEqual(highest, element) { return true }
        guard string(element, kAXRoleAttribute) == kAXGroupRole else { return false }
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success && settable.boolValue
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

    /// Claude's message box by its label, by a label it was seen with before, or by what it is: the
    /// editable field inside an extension's web view, which no change to its wording can move.
    private static func isMessageBox(_ element: AXUIElement?) -> Bool {
        guard let element else { return false }
        let names = labelsOf(element)
        let learned = learnedBoxLabels()
        if names.contains(where: { $0.contains(messageInput) || learned.contains($0) }) { return true }
        return isEditable(element) && webAreasAbove(element) >= extensionWebDepth
    }

    /// What a box calls itself, lowercased, so a label once seen on Claude's box is known again.
    private static func labelsOf(_ element: AXUIElement) -> [String] {
        [kAXDescriptionAttribute, kAXTitleAttribute, placeholderValueAttribute]
            .compactMap { string(element, $0)?.lowercased() }
            .filter { !$0.isEmpty }
    }

    /// The editor's own web content is one web area and an extension's view sits inside it as a second.
    private static let extensionWebDepth = 2
    private static let deepestAncestry = 80

    private static func webAreasAbove(_ element: AXUIElement) -> Int {
        var count = 0
        var current: AXUIElement? = element
        for _ in 0..<deepestAncestry {
            guard let node = current else { break }
            if string(node, kAXRoleAttribute) == webAreaRole { count += 1 }
            current = AXTree.element(node, kAXParentAttribute)
        }
        return count
    }

    /// AXWebArea, which has no kAX constant.
    private static let webAreaRole = "AXWebArea"

    private static func isEditable(_ element: AXUIElement) -> Bool {
        let role = string(element, kAXRoleAttribute)
        guard role == kAXTextAreaRole || role == kAXTextFieldRole else { return false }
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success && settable.boolValue
    }

    /// Labels Claude's box was found with, kept so a box found once by what it is is found again by name.
    private static let learnedBoxKey = "learnedMessageBoxLabels"
    private static let mostLearned = 8

    private static func learnedBoxLabels() -> [String] {
        UserDefaults.standard.stringArray(forKey: learnedBoxKey) ?? []
    }

    private static func learn(_ box: AXUIElement) {
        let known = learnedBoxLabels()
        let fresh = labelsOf(box).filter { !known.contains($0) }
        guard !fresh.isEmpty else { return }
        UserDefaults.standard.set(Array((known + fresh).suffix(mostLearned)), forKey: learnedBoxKey)
        diary.note("learned what Claude's message box calls itself: \(fresh.joined(separator: ", "))")
    }

    private static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? { AXTree.element(element, name) }
    private static func elements(_ element: AXUIElement, _ name: String) -> [AXUIElement]? { AXTree.elements(element, name) }
    private static func string(_ element: AXUIElement, _ name: String) -> String? { AXTree.string(element, name) }
}
