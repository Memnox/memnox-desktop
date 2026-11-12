import Foundation

/// Where the app learns of the newest Memnox service.
public protocol RuntimeFeed: Sendable {
    /// The newest published version, or nil when none could be read.
    func newest() async -> String?
}
