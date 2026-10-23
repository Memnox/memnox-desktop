import AppKit

/// The right Option key, from anywhere: held down, everything said until it is let go is dictated where the cursor
/// is; tapped twice, dictation runs hands free until it is tapped again. Only the right one, so Option with a letter
/// for an accent, which most people type with the left, never starts it, and a hold only counts once it has lasted.
/// Seeing keys outside the app needs the Accessibility leave that typing already asks for.
@MainActor
final class DictationKey {
    /// Called once dictation should start, held or hands free.
    var began: () -> Void = {}
    private var global: EventMonitor?
    private var local: EventMonitor?
    private var pending: Task<Void, Never>?
    /// When the key last went up after a tap too short to be a hold, to tell a double tap.
    private var tappedAt: Date?
    private var isDown = false
    /// Held, or locked on by a double tap, until let go or tapped again.
    private(set) var active = false {
        didSet { down.set(active) }
    }
    private var handsFree = false
    /// The same as `active`, for the recognizer's own thread, which listens for as long as it says.
    nonisolated let down = Flag()

    /// Long enough that Option pressed for a character never starts dictating.
    private static let meantAfter: TimeInterval = 0.25
    /// Two taps closer than this are one double tap.
    private static let doubleTap: TimeInterval = 0.4
    private static let nanosecondsPerSecond: TimeInterval = 1_000_000_000
    /// kVK_RightOption, written out so Carbon need not be imported for one key.
    private static let rightOption: UInt16 = 61
    /// The device bit macOS sets while the right Option key in particular is down.
    private static let rightOptionDown: UInt = 0x40
    /// Any of these held with it makes it some other shortcut.
    private static let others: NSEvent.ModifierFlags = [.command, .control, .shift, .function]

    /// Whether to listen for the key at all, chosen on the Dictation page.
    static let enabledKey = "dictation"

    func start() {
        global = EventMonitor.global([.flagsChanged, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.saw(event) }
        }
        local = EventMonitor.local([.flagsChanged, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.saw(event) }
            return event
        }
    }

    private func saw(_ event: NSEvent) {
        if event.type == .keyDown {
            // A character typed with it is Option at work, so a hold not yet begun is called off.
            cancelPending()
            tappedAt = nil
            return
        }
        guard event.keyCode == Self.rightOption else { return }
        let pressed = event.modifierFlags.rawValue & Self.rightOptionDown != 0
        if pressed, !isDown {
            isDown = true
            pressedDown(alone: event.modifierFlags.isDisjoint(with: Self.others))
        } else if !pressed, isDown {
            isDown = false
            letGo()
        }
    }

    private func pressedDown(alone: Bool) {
        // Hands free ends on the next press, which is how the person says they are done.
        if active, handsFree {
            stop()
            return
        }
        guard alone, UserDefaults.standard.bool(forKey: Self.enabledKey) else { return }
        if let tapped = tappedAt, Date().timeIntervalSince(tapped) < Self.doubleTap {
            tappedAt = nil
            handsFree = true
            activate()
            return
        }
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.meantAfter * Self.nanosecondsPerSecond))
            guard !Task.isCancelled, let self else { return }
            self.pending = nil
            self.handsFree = false
            self.activate()
        }
    }

    private func letGo() {
        if pending != nil {
            // Up before it counted as a hold: a tap, which a second tap soon after makes hands free.
            cancelPending()
            tappedAt = Date()
            return
        }
        if active, !handsFree { stop() }
    }

    private func activate() {
        active = true
        began()
    }

    /// Watches afresh, since macOS sends another app's keys only to monitors made once it trusts this one, so the
    /// ones made before Accessibility was switched on stay deaf until they are made again.
    func rewatch() {
        global?.stop()
        local?.stop()
        start()
    }

    /// Ends dictation, held or hands free, as letting go does.
    func stop() {
        active = false
        handsFree = false
    }

    private func cancelPending() {
        pending?.cancel()
        pending = nil
    }
}
