import Foundation

/// Where this build of the app gets `memnox`, which `scripts/bundle.sh` writes into its Info.plist.
public enum RuntimeSource: Equatable, Sendable {
    /// The runtime checkout the app was built beside, at this path, for working on both at once.
    case local(String)
    /// The package published to npm, which is what a release installs.
    case npm

    private enum Key {
        static let source = "MemnoxRuntimeSource"
        static let checkout = "MemnoxRuntimeCheckout"
        static let local = "local"
    }

    /// Read from this app's Info.plist; an app built without the keys installs from npm, as a release does.
    public static func ofThisApp(_ info: [String: Any] = Bundle.main.infoDictionary ?? [:]) -> RuntimeSource {
        guard info[Key.source] as? String == Key.local, let checkout = info[Key.checkout] as? String, !checkout.isEmpty else {
            return .npm
        }
        return .local(checkout)
    }
}
