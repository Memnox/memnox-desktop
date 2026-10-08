import Foundation

/// Base64url without padding, the way remote-contract.md writes mailbox ids, the QR and fingerprints.
public enum Base64URL {
    /// Base64 groups four characters, so an unpadded string is filled to a multiple of it before decoding.
    private static let groupLength = 4

    public static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func decode(_ text: String) -> Data? {
        var standard = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = standard.count % groupLength
        if remainder > 0 { standard += String(repeating: "=", count: groupLength - remainder) }
        return Data(base64Encoded: standard)
    }
}
