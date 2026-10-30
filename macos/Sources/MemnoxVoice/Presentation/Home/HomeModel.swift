import Foundation
import MemnoxVoiceCore

/// The home the window opens on: the daemon's five blocks and what each of their buttons does, handed in by the app.
/// Read when the window comes forward and when the stream says something changed, never on a timer.
@MainActor
final class HomeModel: ObservableObject {
    /// Nil until the first read, and kept through a failed one so a daemon restarting does not blank the window.
    @Published private(set) var home: DaemonHome?
    /// Set once a read came back empty, which is a daemon away or one older than the home.
    @Published private(set) var unavailable = false
    /// The ready action being handed over, so its button waits rather than being pressed twice.
    @Published private(set) var handingOver = false
    /// What the last hand over came to, in words for under the card.
    @Published private(set) var handOverNote: String?
    @Published private(set) var protecting = false
    /// True while the runtime is asked to stop rather than watch, so Turn on stopping is not pressed twice.
    @Published private(set) var enforcing = false
    /// What the last Turn on stopping came to, in words for under the step.
    @Published private(set) var enforceNote: String?
    /// Why putting the agents under Memnox did not go through, in words the person can act on.
    @Published private(set) var protectFailed: String?
    /// True while the Memnox service is rebuilt and restarted for a Protect the old service could not see through.
    @Published private(set) var restarting = false

    private let load: () async -> DaemonHome?
    private let handOverAction: (String) async -> HandOver
    private let enforceAction: () async -> EnforceOutcome
    private let protectAgents: () async -> String?
    private let restartServiceAction: () async -> String?
    /// True while the voice talks to a server, whose agents this Mac's own CLI cannot put under Memnox.
    let remote: () -> Bool
    let openWaiting: () -> Void
    let openSession: (HomeWorking) -> Void
    private var reading: Task<Void, Never>?
    private var soon: Task<Void, Never>?
    private var again = false

    /// Long enough to fold a burst of events into one read, short enough that the window looks live.
    private static let settleSeconds: TimeInterval = 1.5

    init(
        load: @escaping () async -> DaemonHome?,
        handOver: @escaping (String) async -> HandOver,
        enforce: @escaping () async -> EnforceOutcome,
        protectAgents: @escaping () async -> String?,
        restartService: @escaping () async -> String?,
        remote: @escaping () -> Bool,
        openWaiting: @escaping () -> Void,
        openSession: @escaping (HomeWorking) -> Void
    ) {
        self.load = load
        handOverAction = handOver
        enforceAction = enforce
        self.protectAgents = protectAgents
        restartServiceAction = restartService
        self.remote = remote
        self.openWaiting = openWaiting
        self.openSession = openSession
    }

    /// Reads the home now, one read at a time.
    func refresh() {
        soon?.cancel()
        soon = nil
        guard reading == nil else {
            // Asked during a read, which may have counted from before the change, so one more follows it.
            again = true
            return
        }
        reading = Task { [weak self] in
            guard let self else { return }
            let read = await self.load()
            if let read { self.home = read }
            self.unavailable = read == nil
            self.reading = nil
            if self.again {
                self.again = false
                self.refresh()
            }
        }
    }

    /// Actions the runtime sent live, counted into today at once rather than read again every second.
    func heard(_ actions: Int) {
        guard let home else { return }
        self.home = home.counting(actions: actions)
    }

    /// Something on the stream changed what the home counts: read once the burst has passed.
    func refreshSoon() {
        guard soon == nil else { return }
        soon = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.settleSeconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.soon = nil
            self.refresh()
        }
    }

    /// Asks the daemon to propose the ready action as a rule; the proposal comes up on the island's rule card.
    func handOver(_ ready: HomeReady) {
        guard !handingOver else { return }
        handingOver = true
        handOverNote = nil
        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.handOverAction(ready.action)
            self.handingOver = false
            switch outcome {
            case .proposed: self.handOverNote = "Pick where it holds on the island, then confirm with Touch ID."
            case .refused(let why): self.handOverNote = why
            case .unreachable: self.handOverNote = "Memnox did not answer. Check that it is running, then try again."
            }
            self.refresh()
        }
    }

    /// Asks the daemon to move this Mac to enforce, then reads the home again so its mode and stage follow. A window on a
    /// server is told to do it there, because this Mac's own daemon is the one the method reaches.
    func enforce() {
        guard !enforcing else { return }
        guard !remote() else {
            enforceNote = HomeEnforce.remote
            return
        }
        enforcing = true
        enforceNote = nil
        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.enforceAction()
            self.enforcing = false
            self.enforceNote = HomeEnforce.line(outcome)
            self.refresh()
        }
    }

    /// One press: every agent found here goes under Memnox through the runtime's own setup, then the home is read again.
    func protect() {
        Task { _ = await protectNow() }
    }

    /// The same press for a page that reads its own cards after it: nil when setup went through, else why not,
    /// and nil at once while a press is already under way, whose own caller reports it.
    func protectNow() async -> String? {
        guard !protecting else { return nil }
        protecting = true
        protectFailed = nil
        let failed = await protectAgents()
        protectFailed = failed
        protecting = false
        refresh()
        return failed
    }

    /// Restarts the Memnox service on the newest runtime: nil once it answers again, else why not, and nil at once
    /// while a restart or a Protect is already under way, whose own caller reports it.
    func restartService() async -> String? {
        guard !restarting, !protecting else { return nil }
        restarting = true
        let failed = await restartServiceAction()
        restarting = false
        refresh()
        return failed
    }
}
