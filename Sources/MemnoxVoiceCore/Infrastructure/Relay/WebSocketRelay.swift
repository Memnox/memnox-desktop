import Foundation

/// The real relay: a URLSessionWebSocketTask with the token as a bearer header. It sees only
/// ciphertext and a mailbox id, so a stolen token gets someone bytes that fail the handshake.
public struct WebSocketDialer: RelayDialer {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func dial(_ url: URL, token: String) async throws -> RelaySocket {
        var request = URLRequest(url: url)
        request.setValue("\(bearerPrefix)\(token)", forHTTPHeaderField: authorizationHeader)
        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = RelayFraming.largestMessage
        task.resume()
        return WebSocketRelay(task: task)
    }
}

/// One relay connection over a WebSocket task.
final class WebSocketRelay: RelaySocket, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    func send(_ message: Data) async throws {
        do {
            try await task.send(.data(message))
        } catch {
            noteWhy("sending", error)
            throw ProtocolError.disconnected
        }
    }

    func receive() async throws -> Data {
        while true {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await task.receive()
            } catch {
                noteWhy("receiving", error)
                throw ProtocolError.disconnected
            }
            switch message {
            case .data(let data): return data
            case .string:
                // The relay speaks only binary, so text is somebody else's and is skipped.
                diary.note("skipped a text message on the relay")
                continue
            @unknown default:
                continue
            }
        }
    }

    func close() {
        task.cancel(with: .normalClosure, reason: nil)
    }

    /// The real reason the socket went, which the caller only hears as disconnected: the relay's HTTP answer to the
    /// upgrade, such as 401 for a refused token or 404 for a relay not deployed, and the system's own error.
    private func noteWhy(_ doing: String, _ error: Error) {
        let status = (task.response as? HTTPURLResponse).map { "the relay answered \($0.statusCode)" } ?? "no answer from the relay"
        let host = task.originalRequest?.url?.host() ?? "the relay"
        diary.note("the socket to \(host) failed while \(doing): \(status), \(error.localizedDescription)")
    }
}

/// Puts the APNs and push to start tokens with the relay, authenticated with the phone's rly_ token.
public struct RelayPush: PushRegistrar {
    private let relay: URL
    private let token: String
    private let session: URLSession

    public init(relay: URL, token: String, session: URLSession = .shared) {
        self.relay = relay
        self.token = token
        self.session = session
    }

    public func register(apnsToken: String, pushToStartToken: String?) async throws {
        guard let url = RelayAddress.pushURL(from: relay) else { throw ProtocolError.refused("the relay address has no push route") }
        var request = URLRequest(url: url, timeoutInterval: pushTimeout)
        request.httpMethod = putMethod
        request.setValue("\(bearerPrefix)\(token)", forHTTPHeaderField: authorizationHeader)
        request.setValue(jsonType, forHTTPHeaderField: contentTypeHeader)
        request.httpBody = try JSONEncoder().encode(PushTokens(apnsToken: apnsToken, pushToStartToken: pushToStartToken))
        let (_, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard successStatuses.contains(status) else { throw ProtocolError.refused("the relay answered \(status) to the push tokens") }
        diary.note("push tokens registered with the relay")
    }
}

/// The body of PUT /v1/relay/push, as remote-contract.md names its fields.
private struct PushTokens: Encodable {
    let apnsToken: String
    let pushToStartToken: String?
}

private let authorizationHeader = "Authorization"
private let bearerPrefix = "Bearer "
private let contentTypeHeader = "Content-Type"
private let jsonType = "application/json"
private let putMethod = "PUT"
/// Any 2xx means the relay took the tokens.
private let successStatuses = 200..<300
/// A small request to one host, so a few seconds is plenty before it is tried again next launch.
private let pushTimeout: TimeInterval = 10
