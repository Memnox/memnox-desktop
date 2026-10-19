import Foundation

/// Polls the pointer quickly only while it is near what it watches, since a poll at a frame rate wakes the Mac all day.
@MainActor final class PointerPoll {
    private enum Rate {
        static let near: TimeInterval = 1.0 / 60
        /// Slow enough to let the Mac sleep between ticks, quick enough that arriving at the island is not felt.
        static let far: TimeInterval = 1.0 / 10
        /// The share of an interval macOS may move a tick by, so it can wake for several timers at once.
        static let tolerance = 0.2
    }

    private var timer: Timer?
    private var near = true
    private let tick: @MainActor () -> Void

    init(_ tick: @escaping @MainActor () -> Void) {
        self.tick = tick
        start()
    }

    /// Called from each tick with whether the pointer is close enough to need every frame.
    func pace(near: Bool) {
        guard near != self.near else { return }
        self.near = near
        start()
    }

    private func start() {
        timer?.invalidate()
        let interval = near ? Rate.near : Rate.far
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = interval * Rate.tolerance
        RunLoop.main.add(timer, forMode: .default)
        self.timer = timer
    }
}
