import Foundation

/// Hands the relay the tokens it wakes this phone with. The pushes carry generic text only, and the
/// island is always updated on the phone itself, never by a push.
public protocol PushRegistrar: Sendable {
    func register(apnsToken: String, pushToStartToken: String?) async throws
}
