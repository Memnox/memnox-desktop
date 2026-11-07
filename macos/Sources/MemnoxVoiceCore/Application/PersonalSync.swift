import Foundation

/// Personal sync as the runtime runs it. It holds no key and no rule: the runtime seals and syncs, and the key moves
/// between the person's machines only as a proposal signed with Touch ID after they compared a fingerprint.
public final class PersonalSync: @unchecked Sendable {
    private let link: DaemonLink
    private let ids: RequestIds
    private let lock = NSLock()
    private var view: PersonalSyncStatus?
    private var opened: [PersonalSyncConflict]?
    private var failed = false
    private var busyWith: String?

    /// What `busy` names for Sync now, opening the conflicts and Accept; a conflict or a machine is named by its id.
    public static let now = "now"
    public static let opening = "conflicts"
    public static let accepting = "accept"

    /// Told after anything here changed, on whatever thread that happened.
    public var changed: (@Sendable () -> Void)?

    public init(link: DaemonLink, ids: RequestIds = RequestIds()) {
        self.link = link
        self.ids = ids
    }

    public var status: PersonalSyncStatus? { lock.withLock { view } }

    /// The conflict copies opened beside this Mac's own, once asked for.
    public var conflicts: [PersonalSyncConflict]? { lock.withLock { opened } }

    /// The last read failed, so the page says so rather than drawing nothing.
    public var unreadable: Bool { lock.withLock { failed } }

    public var busy: String? { lock.withLock { busyWith } }

    public func refresh() async {
        let response = await ask(DaemonRequest(id: ids.next(), method: .personalSyncStatus))
        lock.withLock {
            failed = response?.ok != true
            take(response)
        }
        changed?()
    }

    public func syncNow() async -> SyncOutcome {
        await press(Self.now, DaemonRequest(id: ids.next(), method: .personalSyncNow))
    }

    public func loadConflicts() async -> SyncOutcome {
        await press(Self.opening, DaemonRequest(id: ids.next(), method: .personalSyncConflicts))
    }

    /// Keeps one side; the conflict is gone from the list once the runtime answers.
    public func resolve(_ id: String, keep: SyncKeep) async -> SyncOutcome {
        var request = DaemonRequest(id: ids.next(), method: .personalSyncResolve)
        request.syncConflictId = id
        request.syncKeep = keep.rawValue
        let outcome = await press(id, request)
        if case .failed = outcome { return outcome }
        lock.withLock { opened = opened?.filter { $0.id != id } }
        changed?()
        return outcome
    }

    /// On the Mac holding the key: proposes sealing it to a waiting machine whose fingerprint was compared.
    public func offer(machineId: String, fingerprint: String) async -> SyncOutcome {
        var request = DaemonRequest(id: ids.next(), method: .personalSyncKeyOffer)
        request.syncMachineId = machineId
        request.syncFingerprint = fingerprint
        return await press(machineId, request)
    }

    /// On the new Mac: proposes taking the key that arrived, once the same fingerprint was compared.
    public func accept(fingerprint: String) async -> SyncOutcome {
        var request = DaemonRequest(id: ids.next(), method: .personalSyncKeyAccept)
        request.syncFingerprint = fingerprint
        return await press(Self.accepting, request)
    }

    private func press(_ subject: String, _ request: DaemonRequest) async -> SyncOutcome {
        lock.withLock { busyWith = subject }
        changed?()
        let response = await ask(request)
        lock.withLock {
            busyWith = nil
            take(response)
        }
        changed?()
        guard let response else { return .failed("The runtime is not answering.") }
        guard response.ok else { return .failed(response.error ?? "The runtime refused this.") }
        if let proposed = response.proposed { return .proposed(id: proposed) }
        return .done
    }

    /// Called under the lock.
    private func take(_ response: DaemonResponse?) {
        if let status = response?.personalSync { view = status }
        if let conflicts = response?.syncConflicts { opened = conflicts }
    }

    /// A runtime that went away is said by `unreadable` and the outcome, never thrown at the page.
    private func ask(_ request: DaemonRequest) async -> DaemonResponse? {
        try? await link.request(request)
    }
}
