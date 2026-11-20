import Foundation

/// Where the app learns of the newest Memnox service.
public protocol RuntimeFeed: Sendable {
    /// The newest published version, or nil when none could be read.
    func newest() async -> String?
    /// Why the team withdrew `version` with `npm deprecate`, or nil when it stands or could not be read.
    func deprecation(of version: String) async -> String?
}
