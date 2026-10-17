import Foundation

/// Request ids shared by every use case on the phone. Over the socket each request had a connection
/// of its own; in the tunnel they share one session, so two in flight must never carry the same id.
public final class RequestIds: @unchecked Sendable {
    private let lock = NSLock()
    private var last = 0

    public init() {}

    public func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        last += 1
        return last
    }
}
