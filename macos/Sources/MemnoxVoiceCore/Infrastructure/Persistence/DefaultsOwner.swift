import Foundation

/// Kept in the app's own defaults: it is the person's name, not a secret, and never leaves the Mac.
public final class DefaultsOwner: OwnerStore {
    private let defaults: UserDefaults
    private static let key = "ownerName"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var name: String? {
        get {
            let kept = defaults.string(forKey: Self.key)?.trimmingCharacters(in: .whitespaces)
            return kept?.isEmpty == false ? kept : nil
        }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}
