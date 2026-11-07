import Foundation

/// Which daemon methods this Mac's runtime answers, asked once each. A runtime older than the window refuses a method
/// it does not know, and the tab that needs it stays hidden rather than broken.
public final class DaemonSupport: @unchecked Sendable {
    private let link: DaemonLink
    private let ids: RequestIds
    private let lock = NSLock()
    private var known: [String: Bool] = [:]
    private var asking: [String: Task<Bool, Never>] = [:]

    /// Told after an answer arrives or the answers are forgotten, on whatever thread that happened.
    public var changed: (@Sendable () -> Void)?

    public init(link: DaemonLink, ids: RequestIds = RequestIds()) {
        self.link = link
        self.ids = ids
    }

    /// True or false once asked; nil before, which also starts the asking.
    public func supports(_ method: String) -> Bool? {
        if let answer = lock.withLock({ known[method] }) { return answer }
        _ = probe(method)
        return nil
    }

    /// Asks now, or joins the asking already under way, and gives the answer.
    @discardableResult
    public func check(_ method: String) async -> Bool {
        await probe(method).value
    }

    /// Asks again, after the runtime was updated or restarted.
    public func forget() {
        lock.withLock { known.removeAll() }
        changed?()
    }

    private func probe(_ method: String) -> Task<Bool, Never> {
        lock.lock()
        defer { lock.unlock() }
        if let answer = known[method] { return Task { answer } }
        if let running = asking[method] { return running }
        let request = DaemonRequest(id: ids.next(), probing: method)
        let task = Task { [link, weak self] () -> Bool in
            // An unknown method comes back refused, which is the answer sought; no daemon at all reads as not supported.
            let answered = (try? await link.request(request))?.ok ?? false
            self?.settle(method, answered)
            return answered
        }
        asking[method] = task
        return task
    }

    private func settle(_ method: String, _ answered: Bool) {
        lock.withLock {
            asking[method] = nil
            known[method] = answered
        }
        changed?()
    }
}

extension DaemonRequest {
    /// A bare request for any method by name, which only the daemon itself can judge as known or not.
    init(id: Int, probing method: String) {
        self.id = id
        self.method = method
    }
}
