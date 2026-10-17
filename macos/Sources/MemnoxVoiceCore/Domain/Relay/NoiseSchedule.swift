import Foundation

/// When the phone asks the Noise library to rekey or to start over. The library does the rekeying; this only counts.
public enum NoiseSchedule {
    /// Every 2^20 transport messages in one direction, as remote-contract.md sets for both ends.
    public static let rekeyInterval = 1_048_576
    /// An hour, after which the phone closes and runs a fresh IK handshake, so no session key lives long.
    public static let sessionLifetime: TimeInterval = 3_600
}

/// Counts messages one way and says when the count reaches the rekey interval.
public struct RekeyCounter: Sendable {
    public let interval: Int
    public private(set) var count = 0

    public init(interval: Int = NoiseSchedule.rekeyInterval) {
        self.interval = max(1, interval)
    }

    /// Counts one message, true when that one completes an interval and the key should turn now.
    public mutating func counted() -> Bool {
        count += 1
        guard count == interval else { return false }
        count = 0
        return true
    }
}

/// Whether a session started at one time is past its lifetime at another.
public func sessionExpired(startedAt: Date, now: Date, lifetime: TimeInterval = NoiseSchedule.sessionLifetime) -> Bool {
    now.timeIntervalSince(startedAt) >= lifetime
}
