import Foundation

/// Decides whether the notch offers an update: only a release newer than this app, and never the one the person put off.
public struct AppUpdates: Sendable {
    private let feed: ReleaseFeed

    public init(feed: ReleaseFeed) {
        self.feed = feed
    }

    /// The release to offer the app at `running`, or nil. A release newer than `skipped` is offered again, since Later
    /// puts off one version rather than every one after it.
    public func offer(running: String, skipped: String?) async -> AppRelease? {
        guard let newest = await feed.newest(), newest.isNewer(than: running), newest.version != skipped else { return nil }
        return newest
    }
}
