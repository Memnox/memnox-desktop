import Foundation
import MemnoxVoiceCore
import Security

/// How this build of Memnox is signed, which decides whether macOS remembers its grants from one build to the
/// next: an ad hoc signature makes every rebuild a stranger to Accessibility, so the switch shows on while
/// `AXIsProcessTrusted` says no until it is turned off and on again.
enum BuildSignature {
    /// The Info.plist key `scripts/bundle.sh` writes the release team into, so a preview signed before the Developer
    /// ID existed still holds its updates to that team.
    static let pinnedTeamKey = "MemnoxTeamIdentifier"

    /// Read once, since a running process cannot change how it was signed.
    static let isAdHoc: Bool = {
        guard let code = ownStaticCode, let flags = signingInformation(of: code).flags else { return false }
        return flags & SecCodeSignatureFlags.adhoc.rawValue != 0
    }()

    /// This app's own seal and team.
    static let running: AppSignature = {
        guard let code = ownStaticCode else { return AppSignature(isIntact: false, team: nil) }
        return AppSignature(isIntact: true, team: signingInformation(of: code).team)
    }()

    /// The team this build was told to expect, when it was built for a release.
    static var pinnedTeam: String? { Bundle.main.object(forInfoDictionaryKey: pinnedTeamKey) as? String }

    /// The seal and team of the app at `url`, checked file by file, nested code included.
    static func of(_ url: URL) -> AppSignature {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else {
            return AppSignature(isIntact: false, team: nil)
        }
        let strict = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        let intact = SecStaticCodeCheckValidity(code, strict, nil) == errSecSuccess
        return AppSignature(isIntact: intact, team: signingInformation(of: code).team)
    }

    private static var ownStaticCode: SecStaticCode? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess else { return nil }
        return staticCode
    }

    /// The signing dictionary is untyped, so this is the one place it is read.
    private static func signingInformation(of code: SecStaticCode) -> (flags: UInt32?, team: String?) {
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let found = information as? [String: Any] else { return (nil, nil) }
        return (found[kSecCodeInfoFlags as String] as? UInt32, found[kSecCodeInfoTeamIdentifier as String] as? String)
    }
}
