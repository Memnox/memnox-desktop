import Foundation

/// A finished Noise session over one relay mailbox: JSON lines in, sealed chunks out, and the rekey
/// counted both ways. The same type serves either end, so the test runtime speaks exactly what the phone does.
public actor NoiseTunnel {
    private let socket: RelaySocket
    private let mailbox: Data
    private let transport: NoiseTransport
    private var sent: RekeyCounter
    private var received: RekeyCounter
    private var joiner = LineJoiner()
    private var closed = false

    public init(socket: RelaySocket, mailbox: Data, transport: NoiseTransport, rekeyEvery: Int = NoiseSchedule.rekeyInterval) {
        self.socket = socket
        self.mailbox = mailbox
        self.transport = transport
        sent = RekeyCounter(interval: rekeyEvery)
        received = RekeyCounter(interval: rekeyEvery)
    }

    /// Sends one JSON line, cut into chunks, each sealed as its own transport message.
    public func send(line: Data) async throws {
        guard !closed else { throw ProtocolError.disconnected }
        for chunk in LineChunks.chunks(of: line) {
            let sealed = try transport.encrypt(chunk)
            try await socket.send(RelayFraming.message(mailbox: mailbox, frame: Frame(kind: .transport, body: sealed)))
            if sent.counted() { try transport.rekeyOutgoing() }
        }
    }

    /// The next whole JSON line, throwing ProtocolError.disconnected when the peer closes or the relay drops.
    public func receiveLine() async throws -> Data {
        while true {
            guard !closed else { throw ProtocolError.disconnected }
            let message = try await socket.receive()
            guard let frame = RelayFraming.frame(in: message, mailbox: mailbox) else {
                diary.note("dropped a relay message for another mailbox or of no known kind")
                continue
            }
            switch frame.kind {
            case .close:
                closed = true
                throw ProtocolError.disconnected
            case .handshake:
                diary.note("dropped a handshake message inside a finished session")
                continue
            case .transport:
                let plaintext = try transport.decrypt(frame.body)
                if received.counted() { try transport.rekeyIncoming() }
                if let line = try joiner.push(plaintext) { return line }
            }
        }
    }

    /// Tells the peer this side drops the session, then closes the connection.
    public func close() async {
        guard !closed else { return }
        closed = true
        if let message = try? RelayFraming.message(mailbox: mailbox, frame: Frame(kind: .close, body: Data())) {
            try? await socket.send(message)
        }
        socket.close()
    }
}

/// Sends one handshake message in a frame.
func sendHandshake(_ message: Data, on socket: RelaySocket, mailbox: Data) async throws {
    try await socket.send(RelayFraming.message(mailbox: mailbox, frame: Frame(kind: .handshake, body: message)))
}

/// Waits for the next handshake message, failing on a close and skipping anything else.
func receiveHandshake(on socket: RelaySocket, mailbox: Data) async throws -> Data {
    while true {
        let message = try await socket.receive()
        guard let frame = RelayFraming.frame(in: message, mailbox: mailbox) else { continue }
        switch frame.kind {
        case .handshake: return frame.body
        case .close: throw ProtocolError.disconnected
        case .transport:
            diary.note("dropped a transport message that came before the handshake finished")
            continue
        }
    }
}

/// A JSON line as the daemon reads it: the request without the newline the socket used to end it.
func tunnelLine(_ request: DaemonRequest) throws -> Data {
    var line = try encodeLine(request)
    if line.last == newline { line.removeLast() }
    return line
}

/// Any trailing newline is tolerated on the way in, since the socket protocol ended every line with one.
func trimmedLine(_ line: Data) -> String? {
    String(data: line, encoding: .utf8)?.trimmingCharacters(in: .newlines)
}

private let newline: UInt8 = 0x0A
