import Foundation

/// Decides whether the notch offers a newer Memnox service: only one newer than the service running, and never the
/// one the person put off. The app updates it unasked only when it is too old to work with, which setup handles, or
/// when the team withdrew the running version with `npm deprecate`.
public struct RuntimeUpdates: Sendable {
    private let feed: RuntimeFeed

    public init(feed: RuntimeFeed) {
        self.feed = feed
    }

    /// The version to offer the service at `running`, or nil. A service that did not answer is offered nothing, and a
    /// version newer than `skipped` is offered again, since Later puts off one version rather than every one after it.
    public func offer(running: String?, skipped: String?) async -> String? {
        guard let running, let newest = await feed.newest(), RuntimeRelease.isNewer(newest, than: running),
              newest != skipped else { return nil }
        return newest
    }

    /// The version to move to at once, with no Later, because the team withdrew the one running. Nil while the
    /// running one stands, when nothing newer is out yet, or when the newest was withdrawn too, so it never moves to
    /// another faulty version.
    public func withdrawal(running: String?) async -> Withdrawal? {
        guard let running, let reason = await feed.deprecation(of: running), let newest = await feed.newest(),
              RuntimeRelease.isNewer(newest, than: running), await feed.deprecation(of: newest) == nil else { return nil }
        return Withdrawal(running: running, version: newest, reason: reason)
    }
}

/// A running service the team withdrew, and the version that replaces it.
public struct Withdrawal: Equatable, Sendable {
    public let running: String
    public let version: String
    /// The words the team gave `npm deprecate`, kept for the diary.
    public let reason: String
}
