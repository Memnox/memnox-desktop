import Foundation

/// The local network as the runtime keeps it, read so Phones can say when pairing needs no account. Turning it on or
/// off is the runtime's, from the terminal, since this Mac no longer keeps a page for it.
public final class LocalNetwork: @unchecked Sendable {
    private let link: DaemonLink
    private let ids: RequestIds
    private let lock = NSLock()
    private var view: LanStatus?
    private var failed = false

    /// Told after anything here changed, on whatever thread that happened.
    public var changed: (@Sendable () -> Void)?

    public init(link: DaemonLink, ids: RequestIds = RequestIds()) {
        self.link = link
        self.ids = ids
    }

    public var status: LanStatus? { lock.withLock { view } }

    /// The last read failed, so a line that depends on it stays unsaid.
    public var unreadable: Bool { lock.withLock { failed } }

    public func refresh() async {
        let response = await ask(DaemonRequest(id: ids.next(), method: .lanStatus))
        lock.withLock {
            failed = response?.ok != true
            if let lan = response?.lan { view = lan }
        }
        changed?()
    }

    /// A runtime that went away is said by `unreadable` and the outcome, never thrown at the page.
    private func ask(_ request: DaemonRequest) async -> DaemonResponse? {
        try? await link.request(request)
    }
}
