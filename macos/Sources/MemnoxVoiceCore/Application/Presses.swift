import Foundation

/// Proposals a press in this app's own window raised, named by the daemon's answer to that press, so the island puts
/// them to the card or the key rather than declining them as unasked. Nothing outside this app can add one: an id is
/// only ever taken from the answer to a request this app sent, never from an event or a flag on the socket.
public final class Presses: @unchecked Sendable {
    /// Long enough for the proposal's event to be handled behind whatever is being said, short enough that a press
    /// answered and never matched does not leave an allow open for later.
    public static let lifetime: TimeInterval = 60
    /// A window raises a handful at once at most, so an older one is dropped long before this fills.
    static let most = 32
    /// How long a proposal waits for a press still in flight, since its event can come before the answer naming it;
    /// launching an agent with a profile answers only once the terminal is open, so this is seconds rather than a blink.
    static let longestWait: TimeInterval = 10
    private static let step: UInt64 = 20_000_000
    private static let nanosecondsPerSecond: Double = 1_000_000_000

    private let now: () -> Date
    private let lock = NSLock()
    private var named: [String: Date] = [:]
    private var inFlight = Set<UUID>()

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// A press went to the daemon, so a proposal arriving before its answer waits for it.
    func began() -> UUID {
        let token = UUID()
        lock.withLock { _ = inFlight.insert(token) }
        return token
    }

    /// The press was answered, or never will be.
    func ended(_ token: UUID) {
        lock.withLock { _ = inFlight.remove(token) }
    }

    /// The proposals the answer to a press named.
    func raised(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        lock.withLock {
            let at = now()
            prune(at)
            for id in ids { named[id] = at }
            // Bounded, so a page pressed over and over cannot grow it; the oldest goes first.
            while named.count > Self.most, let oldest = named.min(by: { $0.value < $1.value })?.key {
                named.removeValue(forKey: oldest)
            }
        }
    }

    /// Whether a press raised this proposal, taken once, waiting a bounded while on a press still in flight.
    func take(_ id: String) async -> Bool {
        let checks = Int(Self.longestWait * Self.nanosecondsPerSecond / Double(Self.step))
        for _ in 0..<checks {
            let (found, waiting) = lock.withLock { (takeNow(id), !inFlight.isEmpty) }
            if found { return true }
            if !waiting { return false }
            try? await Task.sleep(nanoseconds: Self.step)
        }
        return lock.withLock { takeNow(id) }
    }

    private func takeNow(_ id: String) -> Bool {
        prune(now())
        return named.removeValue(forKey: id) != nil
    }

    private func prune(_ at: Date) {
        named = named.filter { at.timeIntervalSince($0.value) < Self.lifetime }
    }
}

/// Every daemon method whose answer can name a proposal, as the runtime's PROPOSING_METHODS lists them and the vectors
/// check, so only a press of one makes a proposal wait and a page's background read never does.
public enum ProposingMethods {
    public static let all: Set<String> = Set([
        DaemonMethod.handOver, .rule, .mcpServerPut, .mcpAssign, .rulePropose, .ruleRemove, .rulePackImport,
        .agentResume, .agentLaunch, .skillImport, .skillPut, .skillAssign, .skillAccept, .skillRollback,
        .projectOpen, .projectApply, .backupRestore, .memoryConfirm, .lanSet, .personalSyncKeyOffer,
        .personalSyncKeyAccept, .profileApply, .indexInstall, .indexSourceSet,
    ].map(\.rawValue))
}

/// The daemon as this app's own window reaches it: every proposal an answer names is noted as pressed for, and only a
/// method that can propose is waited on. Only the window's use cases are given this link; the voice and anything the
/// daemon pushes go over the plain one.
public final class PressingLink: DaemonLink {
    private let link: DaemonLink
    private let presses: Presses

    public init(link: DaemonLink, presses: Presses) {
        self.link = link
        self.presses = presses
    }

    public func stream(_ request: DaemonRequest) -> AsyncThrowingStream<DaemonResponse, Error> {
        let presses = self.presses
        let token = ProposingMethods.all.contains(request.method) ? presses.began() : nil
        let answers = link.stream(request)
        return AsyncThrowingStream { continuation in
            let reading = Task {
                var first = true
                do {
                    for try await response in answers {
                        // Noted before the caller sees it, so the page and the island never disagree on what was asked.
                        presses.raised(response.proposalIds)
                        if first, let token { presses.ended(token) }
                        first = false
                        continuation.yield(response)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                if let token { presses.ended(token) }
            }
            continuation.onTermination = { _ in
                reading.cancel()
                if let token { presses.ended(token) }
            }
        }
    }
}

extension DaemonResponse {
    /// Every proposal an answer names, wherever the method puts them.
    var proposalIds: [String] {
        var ids: [String] = []
        if let proposed { ids.append(proposed) }
        ids += packProposed ?? []
        ids += profileApplied?.proposed ?? []
        ids += indexInstalled?.proposed ?? []
        return ids
    }
}
