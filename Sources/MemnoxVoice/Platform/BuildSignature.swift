import Foundation
import Security

/// How this build of Memnox is signed, which decides whether macOS remembers its grants from one build to the
/// next: an ad hoc signature makes every rebuild a stranger to Accessibility, so the switch shows on while
/// `AXIsProcessTrusted` says no until it is turned off and on again.
enum BuildSignature {
    /// Read once, since a running process cannot change how it was signed.
    static let isAdHoc: Bool = {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return false }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return false }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let found = information as? [String: Any],
              let flags = found[kSecCodeInfoFlags as String] as? UInt32 else { return false }
        return flags & SecCodeSignatureFlags.adhoc.rawValue != 0
    }()
}
