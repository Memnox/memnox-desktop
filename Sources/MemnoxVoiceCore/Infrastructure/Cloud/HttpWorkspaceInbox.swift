import Foundation

/// One HTTP exchange, so the inbox is tested with no network and the app sends through URLSession.
public protocol HttpTransport: Sendable {
    /// The body and the status, or a throw when nothing came back.
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

/// The real transport, through the shared URLSession.
public struct URLSessionTransport: HttpTransport {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

/// The person inbox over Memnox Cloud's JSON API, as memnox-cloud/docs/person-inbox.md describes it.
public final class HttpWorkspaceInbox: WorkspaceInbox, @unchecked Sendable {
    public static let defaultBase = URL(string: "https://api.memnox.com")! // A literal that always parses.
    private let base: URL
    private let transport: HttpTransport

    /// Long enough for a slow network, short enough that a poll never stacks behind a dead one.
    static let timeout: TimeInterval = 20
    private static let pending = "authorization_pending"

    public init(base: URL = HttpWorkspaceInbox.defaultBase, transport: HttpTransport = URLSessionTransport()) {
        // A base with a path of its own keeps it, since a relative path replaces whatever follows the last slash.
        self.base = base.absoluteString.hasSuffix("/") ? base : base.appendingPathComponent("")
        self.transport = transport
    }

    public func startSignIn(name: String) async throws -> PersonCode {
        try await call("POST", "v1/person/codes", body: ["name": name, "kind": PersonDeviceKind.desktop])
    }

    public func redeem(deviceCode: String) async throws -> CodeRedemption {
        let (data, status) = try await exchange("POST", "v1/person/tokens", body: ["deviceCode": deviceCode], token: nil)
        if Self.succeeded(status) { return .granted(try decode(PersonToken.self, data)) }
        let word = Self.errorWord(data)
        // Still waiting on the console is the one refusal that keeps the asking going.
        if word == Self.pending { return .pending }
        if status == Status.badRequest || status == Status.forbidden { return .stopped(word ?? "\(status)") }
        throw Self.failure(status, data)
    }

    public func workspaces(token: String) async throws -> [WorkspaceRef] {
        let view: PersonView = try await call("GET", "v1/me", token: token)
        return view.workspaces
    }

    public func registerDevice(name: String, signingPoint: String, token: String) async throws -> RegisteredDevice {
        try await call("POST", "v1/me/devices",
                       body: ["name": name, "kind": PersonDeviceKind.desktop, "signingPoint": signingPoint], token: token)
    }

    public func removeDevice(_ id: String, token: String) async throws {
        let (data, status) = try await exchange("DELETE", "v1/me/devices/\(Self.segment(id))", body: nil, token: token)
        guard Self.succeeded(status) else { throw Self.failure(status, data) }
    }

    public func held(in workspace: String, token: String) async throws -> [WorkspaceHeldCall] {
        // Recent settled calls come too, so a card can say who answered it; a cloud that ignores the query sends only open ones.
        let listed: [LossyCall] = try await call("GET", "v1/workspaces/\(Self.segment(workspace))/me/held?\(Self.recent)", token: token)
        return listed.compactMap(\.call)
    }

    static let recent = "include=recent"

    /// One item of the list, nil when it cannot be read, so one odd call never hides every other from the island.
    private struct LossyCall: Decodable {
        let call: WorkspaceHeldCall?

        init(from decoder: Decoder) throws {
            call = try? WorkspaceHeldCall(from: decoder)
        }
    }

    public func answer(_ call: String, in workspace: String, answer: HoldAnswer, deviceId: String, signature: String?,
                       token: String) async throws -> InboxAnswerReply {
        var body = ["answer": answer.rawValue, "deviceId": deviceId]
        if let signature { body["signature"] = signature }
        return try await self.call("POST", "v1/workspaces/\(Self.segment(workspace))/me/held/\(Self.segment(call))",
                                   body: body, token: token)
    }

    private func call<T: Decodable>(_ method: String, _ path: String, body: [String: String]? = nil, token: String? = nil) async throws -> T {
        let (data, status) = try await exchange(method, path, body: body, token: token)
        guard Self.succeeded(status) else { throw Self.failure(status, data) }
        return try decode(T.self, data)
    }

    private func exchange(_ method: String, _ path: String, body: [String: String]?, token: String?) async throws -> (Data, Int) {
        guard let url = URL(string: path, relativeTo: base)?.absoluteURL else {
            throw WorkspaceInboxError.refused(Status.unreadable, "no address for \(path)")
        }
        var request = URLRequest(url: url, timeoutInterval: Self.timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        }
        do {
            return try await transport.send(request)
        } catch {
            throw WorkspaceInboxError.unreachable(error.localizedDescription)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw WorkspaceInboxError.refused(Status.unreadable, "the workspace answered in a shape this app cannot read")
        }
    }

    private static func succeeded(_ status: Int) -> Bool { (Status.okFirst...Status.okLast).contains(status) }

    /// The status the contract names, with whatever words the cloud put beside it.
    static func failure(_ status: Int, _ data: Data) -> WorkspaceInboxError {
        let words = errorWord(data) ?? "status \(status)"
        switch status {
        case Status.unauthorized: return .signedOut
        case Status.forbidden: return .notReached(words)
        case Status.notFound: return .notFound(words)
        case Status.conflict: return .settled(words)
        default: return .refused(status, words)
        }
    }

    /// The cloud says why under `error` for the code flow and under `message` for Nest's own refusals.
    static func errorWord(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        for field in ["error", "message"] {
            if let text = object[field] as? String, !text.isEmpty { return text }
        }
        return nil
    }

    /// An id from the cloud kept to one path segment, so nothing in it can reach another route.
    private static func segment(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_."))) ?? id
    }

    private enum Status {
        static let okFirst = 200
        static let okLast = 299
        static let badRequest = 400
        static let unauthorized = 401
        static let forbidden = 403
        static let notFound = 404
        static let conflict = 409
        /// Not a status the cloud sends: a body that did not decode.
        static let unreadable = 0
    }
}
