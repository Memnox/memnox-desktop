import AppKit

/// Polls the pointer quickly only while it is near what it watches, since a poll at a frame rate wakes the Mac all day.
@MainActor final class PointerPoll {
    private enum Rate {
        static let near: TimeInterval = 1.0 / 60
        /// Far away only a heartbeat, for a change that is not the pointer's, since a move toward the island ticks at once.
        static let far: TimeInterval = 1
        /// The quickest a moving pointer far away is looked at, so sweeping across the screen costs a tenth of a frame rate.
        static let farMove: TimeInterval = 1.0 / 10
        /// The share of an interval macOS may move a tick by, so it can wake for several timers at once.
        static let tolerance = 0.2
    }

    private var near = true
    private let tick: @MainActor () -> Void
    /// Bumped by every tick set, so a slow heartbeat still pending when the pointer came near never ticks twice.
    private var scheduled = 0
    private var lastTick = Date.distantPast
    private var monitors: [Any] = []
    private var lookPending = false

    init(_ tick: @escaping @MainActor () -> Void) {
        self.tick = tick
        schedule()
        watchPointer()
    }

    /// The pointer's moves anywhere on screen, which cost nothing while it is still, unlike a timer that wakes the Mac.
    private func watchPointer() {
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        let global = NSEvent.addGlobalMonitorForEvents(matching: moves) { [weak self] _ in
            MainActor.assumeIsolated { self?.moved() }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: moves) { [weak self] event in
            MainActor.assumeIsolated { self?.moved() }
            return event
        }
        monitors = [global, local].compactMap { $0 }
    }

    /// Far away, a move ticks at once, at most ten times a second; near, the frame rate timer already has it.
    private func moved() {
        guard !near, Date().timeIntervalSince(lastTick) >= Rate.farMove else { return }
        run()
        if near { schedule() }
    }

    /// A look now and the pace it calls for, for a change the panel made itself, such as opening, which no pointer move announced.
    /// On the next turn of the main loop and once however often it was asked, since a tick that opens the panel asks for
    /// another, and running it inside the tick that asked would follow the pointer from within itself.
    func now() {
        guard !lookPending else { return }
        lookPending = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.lookPending = false
                self.run()
                self.schedule()
            }
        }
    }

    private func run() {
        lastTick = Date()
        tick()
    }

    /// Called from each tick with whether the pointer is close enough to need every frame, and read when the next tick is set.
    func pace(near: Bool) {
        self.near = near
    }

    /// One shot set after each tick rather than a repeating timer rebuilt on a change of pace, because rebuilding it from inside its own tick freed the closure still running and crashed the app.
    private func schedule() {
        let interval = near ? Rate.near : Rate.far
        scheduled += 1
        let mine = scheduled
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.scheduled == mine else { return }
                self.run()
                self.schedule()
            }
        }
        timer.tolerance = interval * Rate.tolerance
        RunLoop.main.add(timer, forMode: .default)
    }
}
