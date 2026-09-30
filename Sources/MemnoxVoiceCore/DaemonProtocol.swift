import Foundation

// The daemon's line protocol, mirrored field for field from memnox-runtime's
// packages/core/src/daemon/protocol.ts, since the two sides only ever meet as JSON.

public enum DaemonMethod: String {
    case ping
    case ask
    case subscribe
    case waiting
    case confirm
    case registerKey = "register-key"
}

public enum EventKind: String {
    case held
    case proposal
    case paused
    case settled
}

public enum ChunkKind: String {
    case text
    case tool
    case done
    case limited
    case failed
}

public enum ProposalAnswer: String {
    case confirmed
    case declined
}

public struct DaemonRequest: Encodable, Equatable {
    public let id: Int
    public let method: String
    public var subject: String?
    public var answer: String?
    public var signature: String?
    public var point: String?
    public var said: String?

    public init(id: Int, method: DaemonMethod) {
        self.id = id
        self.method = method.rawValue
    }
}

public struct DaemonEvent: Decodable, Equatable {
    public let kind: String
    public let subject: String
    public let agent: String
    public let summary: String
    public let at: String
    public let expiresAt: String?

    public var eventKind: EventKind? { EventKind(rawValue: kind) }
}

public struct AskChunk: Decodable, Equatable {
    public let kind: String
    public let text: String?
    public let tool: String?

    public var chunkKind: ChunkKind? { ChunkKind(rawValue: kind) }

    /// Done, limited or failed: the last line of a turn.
    public var endsTurn: Bool {
        chunkKind == .done || chunkKind == .limited || chunkKind == .failed
    }
}

public struct DaemonResponse: Decodable, Equatable {
    public let id: Int
    public let ok: Bool
    public let event: DaemonEvent?
    public let waiting: [DaemonEvent]?
    public let chunk: AskChunk?
    public let outcome: String?
    public let error: String?
}

/// What a confirmation signs, byte for byte what the runtime's `confirmationMessage` builds.
public func confirmationMessage(subject: String, answer: String) -> String {
    "memnox-confirm:v1:\(subject):\(answer)"
}

public enum ProtocolError: Error, Equatable {
    case unreadable(String)
    case refused(String)
    case disconnected
}

public func encodeLine(_ request: DaemonRequest) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    var data = try encoder.encode(request)
    data.append(0x0A)
    return data
}

public func decodeLine(_ line: String) throws -> DaemonResponse {
    guard let data = line.data(using: .utf8) else { throw ProtocolError.unreadable(line) }
    do {
        return try JSONDecoder().decode(DaemonResponse.self, from: data)
    } catch {
        throw ProtocolError.unreadable(line)
    }
}
