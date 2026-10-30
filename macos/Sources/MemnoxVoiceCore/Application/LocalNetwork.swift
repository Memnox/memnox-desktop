import Foundation

/// The local network as the runtime keeps it. It holds no rule: turning it off is done at once, since it only narrows
/// who reaches this Mac, and turning it on is a proposal signed with Touch ID on the island.
public final class LocalNetwork: @unchecked Sendable {
    private let link: DaemonLink
    private let ids: RequestIds
    private let lock = NSLock()
    private var view: LanStatus?
    private var failed = false
    private var pressing = false

    /// Told after anything here changed, on whatever thread that happened.
    public var changed: (@Sendable () -> Void)?

    public init(link: DaemonLink, ids: RequestIds = RequestIds()) {
        self.link = link
        self.ids = ids
    }

    public var status: LanStatus? { lock.withLock { view } }

    /// The last read failed, so the page says so rather than drawing nothing.
    public var unreadable: Bool { lock.withLock { failed } }

    public var busy: Bool { lock.withLock { pressing } }

    public func refresh() async {
        let response = await ask(DaemonRequest(id: ids.next(), method: .lanStatus))
        lock.withLock {
            failed = response?.ok != true
            if let lan = response?.lan { view = lan }
        }
        changed?()
    }

    /// Off is immediate; on is only proposed, and holds once signed.
    public func set(on: Bool) async -> LanOutcome {
        lock.withLock { pressing = true }
        changed?()
        var request = DaemonRequest(id: ids.next(), method: .lanSet)
        request.lanOn = on
        let response = await ask(request)
        lock.withLock {
            pressing = false
            if let lan = response?.lan { view = lan }
        }
        changed?()
        guard let response else { return .failed("The runtime is not answering.") }
        guard response.ok else { return .failed(response.error ?? "The runtime refused this.") }
        if let proposed = response.proposed { return .proposed(id: proposed) }
        return .done
    }

    /// A runtime that went away is said by `unreadable` and the outcome, never thrown at the page.
    private func ask(_ request: DaemonRequest) async -> DaemonResponse? {
        try? await link.request(request)
    }
}
