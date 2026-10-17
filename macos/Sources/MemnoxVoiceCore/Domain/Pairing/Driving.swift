import Foundation

/// A phone driving this Mac until a time, as the island shows it for the whole of the grant.
public struct DriveGrant: Equatable, Sendable {
    public let deviceId: String
    public let name: String
    public let until: Date

    public init(deviceId: String, name: String, until: Date) {
        self.deviceId = deviceId
        self.name = name
        self.until = until
    }

    /// The grant a notice names, or nil when it says the grant ended: no until, one unreadable, or one already past.
    public init?(_ drivenBy: DrivenBy, now: Date) {
        guard let until = drivenBy.until.flatMap(Self.date(from:)), until > now else { return nil }
        self.init(deviceId: drivenBy.deviceId, name: drivenBy.name, until: until)
    }

    /// Still live at this moment, so the island stops saying it the instant the time comes.
    public func isLive(at moment: Date) -> Bool { moment < until }

    /// What the island says for as long as it lasts, with a plain word when the phone gave no name.
    public var label: String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return "Driven from \(name.isEmpty ? "your phone" : name)"
    }

    /// The runtime writes ISO 8601 with milliseconds, and a hand written time may leave them out.
    private static func date(from text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

extension DaemonEvent {
    /// Held by a phone or done for its ask, so the phone speaks and the Mac only shows it, with no sound and no chime.
    public var quietOnMac: Bool { quietOnMac(own: OwnDevices.shared.ids) }

    /// Quiet as well for as long as a phone holds this Mac's voice, which covers a server's or a late event with no stamp.
    public func quietOnMac(phoneHolds: Bool) -> Bool { phoneHolds || quietOnMac }

    /// A server stamps this Mac's own asks with the device id it paired as, so those ids are this Mac speaking, not a phone.
    public func quietOnMac(own: Set<String>) -> Bool {
        [heardOn?.deviceId, origin?.deviceId].contains { id in id.map { !own.contains($0) } ?? false }
    }
}

/// This Mac's device id on each server it paired with, so an event a server raised for this Mac's own
/// ask is said here rather than left for a phone. Set by the app whenever the servers change.
public final class OwnDevices: @unchecked Sendable {
    public static let shared = OwnDevices()
    private let lock = NSLock()
    private var kept: Set<String> = []

    public init() {}

    public var ids: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return kept
    }

    public func set(_ ids: Set<String>) {
        lock.lock()
        kept = ids
        lock.unlock()
    }
}
