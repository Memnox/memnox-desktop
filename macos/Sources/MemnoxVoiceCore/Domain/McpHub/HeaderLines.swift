import Foundation

/// One header row as the Add server sheet fills it: a name, the value as typed, and whether this Mac keeps it.
public struct HeaderRow: Equatable, Sendable {
    public var name: String
    public var value: String
    public var secret: Bool

    public init(name: String = "", value: String = "", secret: Bool = false) {
        self.name = name
        self.value = value
        self.secret = secret
    }
}

/// A remote server's headers and its address, worded and checked as the runtime refuses them, mirrored from the Tauri
/// core's `mcp-hub-lines.ts`. A header kept as a secret is sent as `memnox-secret:<name>`, which the proxy fills in.
public enum HeaderLines {
    /// Headers that carry a credential, which the runtime refuses unless their value is a secret reference.
    private static let credentialHeaders: Set<String> = ["authorization", "proxy-authorization", "cookie", "x-api-key", "api-key"]
    /// A header's name as HTTP spells a token, the runtime's own check.
    private static let headerName = "^[A-Za-z0-9!#$%&'*+.^_`|~-]+$"
    /// How a header value names a kept secret.
    public static let secretReference = "memnox-secret:"
    /// A scheme a token is written after, kept in front of the reference so the server still reads `Bearer <token>`.
    private static let tokenScheme = "^(Bearer|Basic|Token|Bot)\\s+(\\S.*)$"
    /// The longest secret name the runtime keeps.
    private static let secretNameLimit = 64
    /// Plain http is for a server on this Mac only, since a header may carry a credential.
    private static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "[::1]"]

    /// Whether a header carries a credential, so its row starts kept as a secret and cannot be sent plain.
    public static func isCredential(_ name: String) -> Bool {
        credentialHeaders.contains(name.trimmingCharacters(in: .whitespaces).lowercased())
    }

    /// The name this Mac keeps a header's secret under, from the server's and the header's names.
    public static func secretName(server: String, header: String) -> String {
        let lowered = header.trimmingCharacters(in: .whitespaces).lowercased()
        let joined = lowered.replacingOccurrences(of: "[^a-z0-9._-]+", with: "-", options: .regularExpression)
        return String("\(server)-\(joined)".prefix(secretNameLimit))
    }

    /// What a kept header is sent as, a scheme in front kept as typed, and the secret itself, which goes to the Keychain.
    public static func reference(_ value: String, secretName: String) -> (sent: String, secret: String) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard let match = trimmed.range(of: tokenScheme, options: [.regularExpression, .caseInsensitive]), match == trimmed.startIndex..<trimmed.endIndex,
              let space = trimmed.firstIndex(where: \.isWhitespace) else {
            return ("\(secretReference)\(secretName)", trimmed)
        }
        let scheme = String(trimmed[..<space])
        let secret = trimmed[space...].trimmingCharacters(in: .whitespaces)
        return ("\(scheme) \(secretReference)\(secretName)", secret)
    }

    /// What is wrong with the rows, said as the runtime would refuse it, or nil when they can be sent.
    public static func problem(_ rows: [HeaderRow]) -> String? {
        var seen: Set<String> = []
        for row in rows {
            let name = row.name.trimmingCharacters(in: .whitespaces)
            if name.isEmpty { continue }
            if name.range(of: headerName, options: .regularExpression) == nil { return "\(name) is not a header name." }
            if seen.contains(name.lowercased()) { return "\(name) is given twice." }
            seen.insert(name.lowercased())
            if isCredential(name), !row.secret { return "\(name) carries a credential, so keep its value as a secret." }
            if row.value.trimmingCharacters(in: .whitespaces).isEmpty { return "Give the value \(name) is sent with." }
        }
        return nil
    }

    /// The headers as the server is written with them, a kept one as its reference, and the secrets to keep first by name.
    public static func headers(server: String, rows: [HeaderRow]) -> (headers: [String: String], secrets: [String: String]) {
        var headers: [String: String] = [:]
        var secrets: [String: String] = [:]
        for row in rows {
            let name = row.name.trimmingCharacters(in: .whitespaces)
            if name.isEmpty { continue }
            guard row.secret else {
                headers[name] = row.value
                continue
            }
            let secret = secretName(server: server, header: name)
            let kept = reference(row.value, secretName: secret)
            headers[name] = kept.sent
            secrets[secret] = kept.secret
        }
        return (headers, secrets)
    }

    /// Why a remote server cannot be reached at this address, in the runtime's terms, or nil when it can.
    public static func addressProblem(_ url: String) -> String? {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        guard let parsed = URLComponents(string: trimmed), let scheme = parsed.scheme?.lowercased(),
              let host = parsed.host, !host.isEmpty else { return "\(trimmed) is not an address." }
        guard scheme == "http" || scheme == "https" else { return "A remote server is reached over http or https." }
        // An IPv6 host may come with or without its brackets, and the runtime's list spells it with them.
        let bare = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        let spelled = bare.contains(":") ? "[\(bare)]" : bare
        if scheme == "http", !loopbackHosts.contains(spelled) {
            return "Plain http is only for a server on this Mac, at localhost or 127.0.0.1. Use https for one anywhere else."
        }
        return nil
    }

    /// A header as the inspector lists it, by name only, and whether the secret the sheet named for it is held.
    public static func lines(_ server: McpHubServerView) -> [(name: String, held: Bool?)] {
        (server.headerNames ?? []).map { name in (name, server.secretsHeld[secretName(server: server.name, header: name)]) }
    }
}
