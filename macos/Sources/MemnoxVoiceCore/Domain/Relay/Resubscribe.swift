import Foundation

/// Thrown to every stream on a session the phone closed itself for its hourly fresh handshake, so a
/// listener can tell a renewal on schedule from a relay or a network that dropped it.
public struct SessionRenewed: Error, Equatable, Sendable {
    public init() {}
}

/// Why an event subscription ended, which decides how soon the phone subscribes again.
public enum SubscriptionEnd: Equatable, Sendable {
    /// The hourly fresh handshake closed the session on schedule, so a new one can open at once.
    case renewed
    /// The relay or the network dropped it, or it simply ended.
    case lost

    public init(_ error: Error?) {
        self = error is SessionRenewed ? .renewed : .lost
    }
}

/// How long the phone waits before it subscribes to events again.
public enum Resubscribe {
    /// After a loss, so a phone out of signal does not spin on a relay it cannot reach.
    public static let afterLoss: TimeInterval = 5
    /// After the hourly renewal, since nothing is wrong and the new session is one handshake away.
    public static let afterRenewal: TimeInterval = 0

    public static func delay(after end: SubscriptionEnd) -> TimeInterval {
        switch end {
        case .renewed: return afterRenewal
        case .lost: return afterLoss
        }
    }
}
