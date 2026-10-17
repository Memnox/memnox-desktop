import Foundation

/// How long listening for its name rests between rounds, so a recognizer that fails again and again backs off
/// rather than spinning on the microphone all day. Only a failure counts, because a round that heard words
/// and no name is the recognizer working.
public struct WakeRest: Equatable, Sendable {
    /// The rest after a round that worked, short so listening barely pauses.
    public static let afterWorking: TimeInterval = 0.3
    /// The rest after the first failure in a row, which doubles with each one after it.
    public static let afterFirstFailure: TimeInterval = 1.0
    /// Never longer than this, so a recognizer that comes back is listened to again within half a minute.
    public static let longest: TimeInterval = 30
    /// Each failure in a row doubles the rest.
    private static let growth: Double = 2

    private var failuresInARow = 0

    public init() {}

    /// The rest before the next round, after one that ended on a failure or not.
    public mutating func after(failed: Bool) -> TimeInterval {
        guard failed else {
            failuresInARow = 0
            return Self.afterWorking
        }
        let rest = Self.afterFirstFailure * pow(Self.growth, Double(failuresInARow))
        failuresInARow += 1
        return min(Self.longest, rest)
    }
}
