import Foundation

/// The daemon reached through the relay: the same DaemonLink the Mac reaches over its socket, so the
/// use cases above it do not know which. One Noise IK session carries every request, routed back by id,
/// and is replaced by a fresh handshake every hour.
public final class NoiseRelayLink: DaemonLink, @unchecked Sendable {
    private let core: LinkCore

    /// `onDone` hears each `done` line the daemon sends once the Mac finished something this phone asked.
    public init(mac: PairedMachine, dialer: RelayDialer, now: @escaping @Sendable () -> Date = { Date.now },
                lifetime: TimeInterval = NoiseSchedule.sessionLifetime, rekeyEvery: Int = NoiseSchedule.rekeyInterval,
                onDone: @escaping @Sendable (String) -> Void = { _ in }) {
        core = LinkCore(mac: mac, dialer: dialer, now: now, lifetime: lifetime, rekeyEvery: rekeyEvery, onDone: onDone)
    }

    public func stream(_ request: DaemonRequest) -> AsyncThrowingStream<DaemonResponse, Error> {
        let core = self.core
        return AsyncThrowingStream { continuation in
            let route = Route(method: request.method, continuation: continuation)
            Task { await core.start(request, route: route) }
            continuation.onTermination = { _ in Task { await core.forget(request.id, route: route) } }
        }
    }

    /// Opens the session now rather than on the first request, so a woken app answers sooner.
    public func connect() async throws {
        _ = try await core.ready()
    }

    /// Sends the close frame, which also ends a drive grant, and drops the session.
    public func close() async {
        await core.close()
    }

    /// How many IK handshakes this link has run, for tests and the diary.
    public var handshakes: Int {
        get async { await core.handshakes }
    }
}

/// One caller waiting on answers to one request.
final class Route: @unchecked Sendable {
    let method: String
    let continuation: AsyncThrowingStream<DaemonResponse, Error>.Continuation

    init(method: String, continuation: AsyncThrowingStream<DaemonResponse, Error>.Continuation) {
        self.method = method
        self.continuation = continuation
    }
}

/// The session and its routes, kept in one actor so requests, answers and reconnects never race.
actor LinkCore {
    private let mac: PairedMachine
    private let dialer: RelayDialer
    private let now: @Sendable () -> Date
    private let lifetime: TimeInterval
    private let rekeyEvery: Int
    private let onDone: @Sendable (String) -> Void
    private var tunnel: NoiseTunnel?
    private var startedAt: Date?
    private var connecting: Task<NoiseTunnel, Error>?
    private var reader: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var routes: [Int: Route] = [:]
    private(set) var handshakes = 0

    init(mac: PairedMachine, dialer: RelayDialer, now: @escaping @Sendable () -> Date, lifetime: TimeInterval, rekeyEvery: Int,
         onDone: @escaping @Sendable (String) -> Void) {
        self.mac = mac
        self.dialer = dialer
        self.now = now
        self.lifetime = lifetime
        self.rekeyEvery = rekeyEvery
        self.onDone = onDone
    }

    func start(_ request: DaemonRequest, route: Route) async {
        let tunnel: NoiseTunnel
        do {
            // Ready first, since starting over an hour old session ends every route on it.
            tunnel = try await ready()
        } catch {
            diary.note("could not open the relay session for \(request.method): \(error)")
            route.continuation.finish(throwing: ProtocolError.disconnected)
            return
        }
        guard routes[request.id] == nil else {
            route.continuation.finish(throwing: ProtocolError.refused("request \(request.id) is already in flight"))
            return
        }
        routes[request.id] = route
        do {
            try await tunnel.send(line: tunnelLine(request))
        } catch {
            diary.note("could not send \(request.method) through the relay: \(error)")
            if routes[request.id] === route { routes[request.id] = nil }
            route.continuation.finish(throwing: ProtocolError.disconnected)
        }
    }

    func forget(_ id: Int, route: Route) {
        if routes[id] === route { routes[id] = nil }
    }

    /// The live session, a fresh one when there is none or the last is an hour old.
    func ready() async throws -> NoiseTunnel {
        if let tunnel, let startedAt {
            guard sessionExpired(startedAt: startedAt, now: now(), lifetime: lifetime) else { return tunnel }
            diary.note("the relay session is an hour old, so it starts over with a fresh handshake")
            await drop(tunnel, because: SessionRenewed())
        }
        if let connecting { return try await connecting.value }
        let task = Task { try await self.handshake() }
        connecting = task
        defer { connecting = nil }
        return try await task.value
    }

    func close() async {
        if let tunnel { await drop(tunnel) }
    }

    /// The phone opens with IK, already knowing the runtime's static key from pairing.
    private func handshake() async throws -> NoiseTunnel {
        let socket = try await dialer.dial(mac.relayURL, token: mac.relayToken)
        do {
            let handshake = try NoiseHandshake.initiator(.ik, localPrivate: mac.phonePrivateKey, remotePublic: mac.runtimeStatic)
            try await sendHandshake(handshake.writeMessage(Data()), on: socket, mailbox: mac.mailbox)
            _ = try handshake.readMessage(await receiveHandshake(on: socket, mailbox: mac.mailbox))
            guard handshake.isFinished else { throw ProtocolError.refused("the IK handshake did not finish in two messages") }
            let tunnel = NoiseTunnel(socket: socket, mailbox: mac.mailbox, transport: try handshake.intoTransport(), rekeyEvery: rekeyEvery)
            self.tunnel = tunnel
            startedAt = now()
            handshakes += 1
            diary.note("relay session open to \(mac.machine)")
            reader = Task { await self.read(tunnel) }
            timer = Task { await self.expire(tunnel) }
            return tunnel
        } catch {
            socket.close()
            throw error
        }
    }

    private func read(_ tunnel: NoiseTunnel) async {
        while true {
            do {
                deliver(try await tunnel.receiveLine())
            } catch {
                if self.tunnel === tunnel {
                    diary.note("the relay session closed: \(error)")
                    await drop(tunnel)
                }
                return
            }
        }
    }

    /// Starts over an hour on even with nothing sent, so a quiet subscription never outlives its key.
    private func expire(_ tunnel: NoiseTunnel) async {
        try? await Task.sleep(nanoseconds: UInt64(lifetime * Double(nanosecondsPerSecond)))
        guard !Task.isCancelled, self.tunnel === tunnel else { return }
        diary.note("the relay session reached its hour, so it closes for a fresh handshake")
        await drop(tunnel, because: SessionRenewed())
    }

    private func deliver(_ line: Data) {
        guard let text = trimmedLine(line) else { return }
        if let response = try? decodeLine(text) {
            if let route = routes[response.id] {
                route.continuation.yield(response)
                if isLastLine(response, for: route.method) {
                    routes[response.id] = nil
                    route.continuation.finish()
                }
            }
            if let done = response.done { onDone(done.text) }
            return
        }
        if let stray = try? JSONDecoder().decode(StrayLine.self, from: Data(text.utf8)), let done = stray.done {
            onDone(done.text)
            return
        }
        diary.note("dropped a line from the runtime this app cannot read")
    }

    /// Ends the session and every stream on it, since the daemon forgets a session's requests with it.
    /// A renewal on schedule says so, so a subscription opens again at once rather than after a pause.
    private func drop(_ old: NoiseTunnel, because reason: Error = ProtocolError.disconnected) async {
        guard tunnel === old else { return }
        tunnel = nil
        startedAt = nil
        reader?.cancel()
        timer?.cancel()
        reader = nil
        timer = nil
        let waiting = routes.values
        routes = [:]
        for route in waiting { route.continuation.finish(throwing: reason) }
        await old.close()
    }
}

/// A done line that came without the id of any request.
private struct StrayLine: Decodable {
    let done: DoneLine?
}

private let nanosecondsPerSecond: UInt64 = 1_000_000_000
