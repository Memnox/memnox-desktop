import Foundation

/// The confirmation key, opened again on the next need when it could not be opened before. A Memnox signed anew, as
/// the move to a Developer ID is, makes macOS ask once whether it may read the key's keychain item; a person who
/// said no then is asked again at the next yes rather than left with no Touch ID until they reopen the app.
public final class RetryingConfirmKey: ConfirmKey, @unchecked Sendable {
    private let open: () throws -> ConfirmKey
    private let lock = NSLock()
    private var opened: ConfirmKey?

    /// Tries once at once, so the keychain's question comes with launch as it always has.
    public init(_ open: @escaping () throws -> ConfirmKey) {
        self.open = open
        _ = current()
    }

    /// Empty while no key could be opened, which the daemon never registers.
    public var publicPoint: String { current()?.publicPoint ?? "" }

    public func sign(_ message: String, reason: String) async throws -> String? {
        guard let key = current() else { return nil }
        return try await key.sign(message, reason: reason)
    }

    public func sign(_ messages: [String], reason: String) async throws -> [String]? {
        guard let key = current() else { return nil }
        return try await key.sign(messages, reason: reason)
    }

    private func current() -> ConfirmKey? {
        lock.withLock {
            if let opened { return opened }
            do {
                let key = try open()
                opened = key
                return key
            } catch {
                diary.note("the confirmation key could not be opened, so it is tried again at the next yes: \(error.localizedDescription)")
                return nil
            }
        }
    }
}
