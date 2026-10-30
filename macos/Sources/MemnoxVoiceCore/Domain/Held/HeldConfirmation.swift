import CryptoKit
import Foundation

// A yes to a held call bound to the exact call shown, mirrored from the runtime's gate/action-digest.ts and
// gate/confirm-message.ts. The daemon works the digest out again from the call it holds, so a call changed since
// it was shown no longer matches what was signed.

/// What a v4 confirmation signs, byte for byte what the runtime's `actionConfirmationMessage` builds.
public func actionConfirmationMessage(subject: String, answer: String, actionDigest: String) -> String {
    "memnox-confirm:v4:\(subject):\(answer):\(actionDigest)"
}

/// The words a yes to a held call signs: the v4 message when the daemon gave its digest, and the older one for a
/// daemon that gave none, which still verifies it.
public func heldConfirmation(subject: String, answer: String, actionDigest: String?) -> String {
    guard let actionDigest else { return confirmationMessage(subject: subject, answer: answer) }
    return actionConfirmationMessage(subject: subject, answer: answer, actionDigest: actionDigest)
}

/// The call as the digest reads it, as the runtime's `canonicalAction` writes it: five fields in a fixed order, each
/// written even when empty, and the arguments only as a digest of their own.
public func canonicalAction(operation: String, target: String?, command: String?, fingerprint: String, cwd: String?, agent: String) -> String {
    let fields: [(String, String)] = [
        ("operation", operation),
        ("target", target ?? ""),
        ("argumentDigest", sha256Hex("\(command ?? "")\n\(fingerprint)")),
        ("cwd", cwd ?? ""),
        ("agent", agent),
    ]
    return "{" + fields.map { "\(jsonString($0.0)):\(jsonString($0.1))" }.joined(separator: ",") + "}"
}

/// SHA-256 of the canonical call in lowercase hex, which a v4 confirmation signs.
public func actionDigest(ofCanonical canonical: String) -> String {
    sha256Hex(canonical)
}

private func sha256Hex(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
}

/// A string as JavaScript's JSON.stringify writes it, so the canonical call matches the runtime's byte for byte.
func jsonString(_ text: String) -> String {
    var out = "\""
    for scalar in text.unicodeScalars {
        switch scalar {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\u{08}": out += "\\b"
        case "\u{0C}": out += "\\f"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        case _ where scalar.value < JSONEscape.firstPrintable: out += String(format: "\\u%04x", scalar.value)
        default: out.unicodeScalars.append(scalar)
        }
    }
    return out + "\""
}

private enum JSONEscape {
    /// Below a space every character is written as a \u escape, as JSON.stringify does.
    static let firstPrintable: UInt32 = 0x20
}

/// How a yes to a held call is signed, said on the card before it is given.
public enum HeldSigning {
    public static func line(touchID: Bool, actionDigest: String?) -> String {
        guard touchID else { return "Inside its own repository, so a yes needs no signature" }
        guard actionDigest != nil else { return "A yes is signed with Touch ID" }
        return "A yes is signed with Touch ID over exactly this call, so one changed since is refused"
    }
}
