import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Memnox Cloud from a script: each route answers from its own queue, and every request is kept to read back.
final class ScriptedTransport: HttpTransport, @unchecked Sendable {
    struct Sent {
        let method: String
        let path: String
        let query: String?
        let authorization: String?
        let body: [String: String]
    }

    private let lock = NSLock()
    private var queues: [String: [(Int, String)]] = [:]
    /// Routes whose last answer was already given, so the next one queued takes its place rather than waiting behind it.
    private var served = Set<String>()
    private var kept: [Sent] = []
    var offline = false

    /// Queues an answer for `POST /v1/...`; the last one queued repeats until another is queued.
    func answer(_ route: String, _ status: Int, _ json: String) {
        lock.lock()
        if served.remove(route) != nil { queues[route] = [] }
        queues[route, default: []].append((status, json))
        lock.unlock()
    }

    var sent: [Sent] {
        lock.lock()
        defer { lock.unlock() }
        return kept
    }

    func sent(_ route: String) -> [Sent] {
        sent.filter { "\($0.method) \($0.path)" == route }
    }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (next, offline) = take(request)
        if offline { throw URLError(.notConnectedToInternet) }
        guard let (status, json) = next else { return (Data(#"{"message":"no route"}"#.utf8), 404) }
        return (Data(json.utf8), status)
    }

    /// Kept apart from `send`, since a lock may not be held across an await.
    private func take(_ request: URLRequest) -> ((Int, String)?, Bool) {
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] } ?? [:]
        lock.lock()
        defer { lock.unlock() }
        kept.append(Sent(method: method, path: path, query: request.url?.query, authorization: request.value(forHTTPHeaderField: "Authorization"), body: body))
        let route = "\(method) \(path)"
        var queue = queues[route] ?? []
        if queue.count == 1 { served.insert(route) }
        let next = queue.count > 1 ? queue.removeFirst() : queue.first
        queues[route] = queue
        return (next, offline)
    }
}

/// A held call as the inbox lists it, with only what a test changes named.
func heldJSON(_ id: String = "apr_1", machineLabel: String? = "build-box", agent: String = "codex",
              expiresAt: String = "2026-10-06T10:30:00.000Z", approvedByYou: Bool = false, ownerName: String? = nil) -> String {
    let label = (machineLabel.map { #","machineLabel":"\#($0)""# } ?? "") + (ownerName.map { #","ownerName":"\#($0)""# } ?? "")
    return """
    {"id":"\(id)","machineId":"mch_91c2"\(label),"machineClass":"server","agent":"\(agent)","operation":"git.push",\
    "target":"main","summary":"Codex wants to push to main.","why":"Pushes to main are held.","reason":"pushes to main are held",\
    "askedAt":"2026-10-06T10:00:00.000Z","expiresAt":"\(expiresAt)","escalated":false,"approvalsNeeded":1,\
    "approvedByYou":\(approvedByYou)}
    """
}

/// A call the inbox lists as settled a moment ago, with only what `include=recent` adds beside its id.
func settledJSON(_ id: String, answer: String? = "once", by: String? = "Ana", on: String? = "Ana's iPhone") -> String {
    var fields = [#""id":"\#(id)""#]
    if let answer { fields.append(#""answer":"\#(answer)""#) }
    if let by { fields.append(#""answeredBy":"\#(by)""#) }
    if let on { fields.append(#""answeredOn":"\#(on)""#) }
    return "{\(fields.joined(separator: ","))}"
}

/// A person signed in with one workspace and a registered device.
func signedInCredential(workspaces: [String] = ["ws_1"]) -> WorkspaceCredential {
    WorkspaceCredential(token: "mnx_person", tokenId: "tok_1", personId: "usr_ana", name: "Ana", orgId: "org_1",
                        workspaces: workspaces, deviceId: "pdv_mac")
}

/// Ten in the morning on the day the fixtures are set, before any of them expires.
let morning = ISO8601DateFormatter().date(from: "2026-10-06T10:05:00Z")! // A literal that always parses.
