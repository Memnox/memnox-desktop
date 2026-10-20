import Foundation

/// Where the app learns of its newest release.
public protocol ReleaseFeed: Sendable {
    /// The newest release carrying the Mac app, or nil when none could be read.
    func newest() async -> AppRelease?
}
