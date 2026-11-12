import Foundation

/// Decides whether the notch offers a newer Memnox service: only one newer than the service running, and never the
/// one the person put off. The app never updates it unasked unless it is too old to work with, which setup handles.
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
}
