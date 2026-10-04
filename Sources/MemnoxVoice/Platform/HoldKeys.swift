import AppKit

/// Control and Option held down together, from anywhere, and nothing else with them: the way into
/// saying a rule. A press that is let go at once is somebody reaching for another shortcut, so the
/// hold only counts once it has lasted a moment. Watching modifier keys outside the app needs the
/// same Accessibility leave typing does, which the app already asks for.
@MainActor
final class HoldKeys {
    /// Called once the hold has lasted long enough to be meant.
    var began: () -> Void = {}
    /// Called when either key is let go after a hold began.
    var ended: () -> Void = {}
    private var global: EventMonitor?
    private var local: EventMonitor?
    private var pending: Task<Void, Never>?
    private(set) var holding = false {
        didSet { down.set(holding) }
    }
    /// The same as `holding`, readable from the recognizer's own thread, which listens for as long as it says.
    nonisolated let down = Flag()

    /// Long enough that Control Option with a letter, a common shortcut, never opens it by accident.
    private static let meantAfter: TimeInterval = 0.3
    private static let nanosecondsPerSecond: TimeInterval = 1_000_000_000
    /// Only these two, so Command or Shift alongside them is some other shortcut.
    private static let chord: NSEvent.ModifierFlags = [.control, .option]
    private static let watched: NSEvent.ModifierFlags = [.control, .option, .command, .shift]

    func start() {
        global = EventMonitor.global([.flagsChanged, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.saw(event) }
        }
        local = EventMonitor.local([.flagsChanged, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.saw(event) }
            return event
        }
    }

    /// Whether this Mac lets the app see keys pressed in other apps, without which the hold is never seen.
    static var canWatch: Bool { AXIsProcessTrusted() }

    private func saw(_ event: NSEvent) {
        // A letter pressed with the chord is a shortcut, so the hold is called off before it begins.
        if event.type == .keyDown {
            if !holding { cancelPending() }
            return
        }
        let pressed = event.modifierFlags.intersection(Self.watched) == Self.chord
        if pressed, !holding, pending == nil {
            pending = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.meantAfter * Self.nanosecondsPerSecond))
                guard !Task.isCancelled, let self else { return }
                self.pending = nil
                self.holding = true
                self.began()
            }
        } else if !pressed {
            cancelPending()
            if holding {
                holding = false
                ended()
            }
        }
    }

    private func cancelPending() {
        pending?.cancel()
        pending = nil
    }
}

/// A yes or no read from one thread and written from another, behind a lock.
final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ on: Bool) {
        lock.lock()
        value = on
        lock.unlock()
    }

    /// Whether it was set, clearing it, so one request is answered once.
    func take() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let was = value
        value = false
        return was
    }
}
