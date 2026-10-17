import AppKit
import ApplicationServices
import MemnoxVoiceCore

/// Dictation written into the field while the person is still speaking, and revised in place as the recognizer
/// changes its mind. It writes through Accessibility where the field takes it, which most native fields do, and
/// otherwise as key presses, which Electron apps and browsers take; never through the clipboard. It knows exactly
/// what it wrote, so it only ever takes back its own words, and it stops the moment the person types or leaves.
@MainActor
final class LiveTyping {
    private let app: NSRunningApplication
    private let element: AXUIElement?
    /// Where its words begin in the field, in the UTF-16 units Accessibility counts in; nil when the field cannot say.
    private let start: Int?
    /// Exactly what it has written so far, which is what a revision is measured against.
    private(set) var typed = ""
    /// Set once the field would not take Accessibility writes, so the rest goes in as keys.
    private var byKeys: Bool
    /// The person typed, the app left the front, or a write went wrong: nothing more is written.
    private(set) var stopped = false
    private var personTyped = false
    private var monitor: EventMonitor?

    /// Marks its own key presses, so the watch for the person typing never mistakes them for theirs.
    private static let mark: Int64 = 0x4D454D4E
    private static let deleteKey: CGKeyCode = 51
    private static let returnKey: CGKeyCode = 36
    /// A pause between key presses that Electron apps need to keep every one, and still faster than speech.
    private static let keyGap: TimeInterval = 0.002
    private static let nanosecondsPerSecond: TimeInterval = 1_000_000_000

    /// Nil where nothing may be written live: no leave to press keys, a password field, or a selection being edited.
    init?(app: NSRunningApplication?, focus: FocusedText) {
        guard let app, AXIsProcessTrusted(), !focus.isSecure, focus.selection == nil else { return nil }
        self.app = app
        element = focus.element
        start = focus.range.map(\.location)
        // A field that cannot say where the cursor is cannot be checked after a write, so it gets keys from the start.
        byKeys = focus.element == nil || focus.range == nil || focus.value == nil
    }

    func begin() {
        monitor = EventMonitor.global([.keyDown]) { [weak self] event in
            let ours = event.cgEvent?.getIntegerValueField(.eventSourceUserData) == Self.mark
            guard !ours else { return }
            MainActor.assumeIsolated { self?.personTyped = true }
        }
    }

    func end() {
        monitor?.stop()
        monitor = nil
    }

    /// Makes the field hold `wanted` where `typed` was, changing only the end that differs. False once it has stopped.
    @discardableResult
    func show(_ wanted: String) async -> Bool {
        guard !stopped else { return false }
        guard !personTyped, NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
            stop(personTyped ? "the person typed" : "\(app.localizedName ?? "the app") left the front")
            return false
        }
        let revision = liveRevision(from: typed, to: wanted)
        guard !revision.isEmpty else { return true }
        if !byKeys {
            switch writeThroughAccessibility(revision) {
            case .written:
                typed = wanted
                return true
            case .untouched:
                diary.note("\(app.localizedName ?? "the app") would not take dictation through Accessibility, so it goes in as keys")
                byKeys = true
            case .wrong:
                stop("the field did not hold what was written")
                return false
            }
        }
        await writeAsKeys(revision)
        typed = wanted
        return true
    }

    /// Whether the field still holds what was written, so a final polish replaces only Memnox's own words.
    var stillOurs: Bool {
        guard !stopped, !personTyped else { return false }
        guard !byKeys, let element, let start else {
            // Keys leave nothing to read back, so the person not typing and the app still in front is the check.
            return NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
        }
        return Self.holds(typed, in: element, at: start)
    }

    private func stop(_ why: String) {
        guard !stopped else { return }
        stopped = true
        diary.note("stopped typing the dictation live: \(why)")
    }

    private enum Outcome { case written, untouched, wrong }

    private func writeThroughAccessibility(_ revision: LiveRevision) -> Outcome {
        guard let element, let start else { return .untouched }
        let before = FocusedText.value(of: element)
        var range = CFRange(location: start + revision.kept.utf16.count, length: revision.removed.utf16.count)
        guard let span = AXValueCreate(.cfRange, &range),
              AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, span) == .success,
              AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, revision.added as CFString) == .success
        else { return FocusedText.value(of: element) == before ? .untouched : .wrong }
        if Self.holds(revision.kept + revision.added, in: element, at: start) { return .written }
        // Some fields answer success and change nothing, which keys then fix; a field changed some other way is left alone.
        return FocusedText.value(of: element) == before ? .untouched : .wrong
    }

    private static func holds(_ text: String, in element: AXUIElement, at start: Int) -> Bool {
        guard let value = FocusedText.value(of: element) else { return false }
        let whole = value as NSString
        let length = text.utf16.count
        guard start + length <= whole.length else { return false }
        return whole.substring(with: NSRange(location: start, length: length)) == text
    }

    /// Backspaces for what is taken back, then each character as its own key press, with Return under Shift for a
    /// line break so a chat app starts a new line rather than sending.
    private func writeAsKeys(_ revision: LiveRevision) async {
        for _ in revision.removed {
            Self.post(key: Self.deleteKey)
            try? await Task.sleep(nanoseconds: UInt64(Self.keyGap * Self.nanosecondsPerSecond))
        }
        for character in revision.added {
            if character == "\n" {
                Self.post(key: Self.returnKey, flags: .maskShift)
            } else {
                Self.post(character: character)
            }
            try? await Task.sleep(nanoseconds: UInt64(Self.keyGap * Self.nanosecondsPerSecond))
        }
    }

    /// Its own event source, so the right Option key the person is holding is never carried onto a key it presses.
    private static func post(key: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            event?.flags = flags
            event?.setIntegerValueField(.eventSourceUserData, value: mark)
            event?.post(tap: .cghidEventTap)
        }
    }

    private static func post(character: Character) {
        let units = Array(String(character).utf16)
        let source = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
            event?.flags = []
            event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            event?.setIntegerValueField(.eventSourceUserData, value: mark)
            event?.post(tap: .cghidEventTap)
        }
    }
}

/// The latest words heard, written from the recognizer's thread and read by the typing loop on the main actor.
final class DictatedSoFar: @unchecked Sendable {
    private let lock = NSLock()
    private var words = ""
    private var fresh = false

    func set(_ text: String) {
        lock.lock()
        if text != words {
            words = text
            fresh = true
        }
        lock.unlock()
    }

    /// The words when they changed since the last look, nil otherwise.
    func takeChanged() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard fresh else { return nil }
        fresh = false
        return words
    }
}
