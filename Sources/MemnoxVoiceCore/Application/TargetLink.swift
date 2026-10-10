import Foundation

/// The machine the voice and the session views talk to: the daemon on this Mac, or a server it paired with over the relay.
public enum MachineTarget: Equatable, Sendable {
    case thisMac
    /// A server, with the device id this Mac paired as there, which its events name when this Mac asked.
    case server(machineId: String, deviceId: String, name: String)

    public var isRemote: Bool { self != .thisMac }

    public var machineId: String? {
        if case .server(let machineId, _, _) = self { return machineId }
        return nil
    }

    /// The server's name, nil for this Mac, so a label is only added where it says something.
    public var serverName: String? {
        if case .server(_, _, let name) = self { return name }
        return nil
    }
}

/// A DaemonLink over whichever machine is chosen, so the conversation never knows which one it talks to.
/// A request about a subject some machine raised goes back to that machine whatever is chosen, so a held
/// call from this Mac is answered here while a server is picked, and one from a server goes to that server.
/// A server is sent only what RemoteReach allows: a key, the words learnt, what was typed or seen, and
/// pairing all belong to this Mac's own daemon, so they are refused here rather than sent to another machine.
public final class TargetLink: DaemonLink, @unchecked Sendable {
    private let lock = NSLock()
    private let local: DaemonLink
    private var chosen: MachineTarget = .thisMac
    /// Every paired server this Mac can reach, by machine id.
    private var servers: [String: (target: MachineTarget, link: DaemonLink)] = [:]
    /// Which machine raised each subject still worth answering.
    private var raised: [String: MachineTarget] = [:]
    /// Subjects a teammate's machine raised that reached this person through the workspace, answered there and never by a daemon.
    private var workspace = Set<String>()
    /// Every stream that followed the choice and has not ended, so a change of machine ends them.
    private var live: [UUID: Task<Void, Never>] = [:]

    /// Far more subjects than ever wait at once, and still a bound on a map nothing else empties.
    static let subjectsKept = 1_000

    public init(local: DaemonLink) {
        self.local = local
    }

    public var target: MachineTarget {
        lock.lock()
        defer { lock.unlock() }
        return chosen
    }

    public var isRemote: Bool { target.isRemote }

    /// A server this Mac can reach, kept so its held calls are answered through its own link.
    public func register(_ server: MachineTarget, link: DaemonLink) {
        guard let machineId = server.machineId else { return }
        lock.lock()
        servers[machineId] = (server, link)
        lock.unlock()
    }

    /// A server forgotten: nothing is routed to it again, and it stops being the target.
    public func unregister(machineId: String) {
        lock.lock()
        servers[machineId] = nil
        raised = raised.filter { $0.value.machineId != machineId }
        let wasChosen = chosen.machineId == machineId
        lock.unlock()
        if wasChosen { choose(.thisMac) }
    }

    /// Points at a server, or back at this Mac; what was in flight on the old choice ends, while answers to other machines carry on.
    public func choose(_ target: MachineTarget, link: DaemonLink? = nil) {
        if let link { register(target, link: link) }
        lock.lock()
        // A server with no link to reach it is no target at all, so it falls back to this Mac.
        chosen = target.machineId.flatMap { servers[$0] } != nil ? target : .thisMac
        let ending = Array(live.values)
        live = [:]
        lock.unlock()
        for task in ending { task.cancel() }
        diary.note("talking to \(self.target.serverName ?? "this Mac")")
    }

    /// The machine an event came from, so whatever answers its subject goes back there.
    public func remember(subject: String, from machine: MachineTarget) {
        lock.lock()
        if raised.count >= Self.subjectsKept { raised.removeAll() }
        raised[subject] = machine
        lock.unlock()
    }

    /// A subject settled, so nothing more is routed by it.
    public func forget(subject: String) {
        lock.lock()
        raised[subject] = nil
        workspace.remove(subject)
        lock.unlock()
    }

    /// A call the workspace routed to this person: no daemon raised it, so no daemon is ever sent its answer.
    public func rememberWorkspace(subject: String) {
        lock.lock()
        if workspace.count >= Self.subjectsKept { workspace.removeAll() }
        workspace.insert(subject)
        raised[subject] = nil
        lock.unlock()
    }

    /// Whether a subject belongs to the workspace, so its answer goes through the inbox.
    public func belongsToWorkspace(subject: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return workspace.contains(subject)
    }

    /// The machine that raised a subject, nil when none was seen.
    public func machine(for subject: String) -> MachineTarget? {
        lock.lock()
        defer { lock.unlock() }
        return raised[subject]
    }

    /// Whether an answer to this subject reaches a server, which takes no yes without a signature.
    public func reachesAnotherMachine(subject: String) -> Bool {
        (machine(for: subject) ?? target).isRemote
    }

    public func stream(_ request: DaemonRequest) -> AsyncThrowingStream<DaemonResponse, Error> {
        if let subject = request.subject, belongsToWorkspace(subject: subject) {
            return AsyncThrowingStream { $0.finish(throwing: ProtocolError.refused(Self.workspaceOnly(subject))) }
        }
        let (target, link, followsChoice) = route(request)
        if target.isRemote, !RemoteReach.allows(request) {
            return AsyncThrowingStream { $0.finish(throwing: ProtocolError.refused(Self.onlyHere(request.method))) }
        }
        return AsyncThrowingStream { continuation in
            let id = UUID()
            lock.lock()
            // Kept before it can end, so its own forget never runs ahead of the keep.
            let task = Task { [weak self] in
                do {
                    for try await response in link.stream(request) { continuation.yield(response) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                self?.ended(id)
            }
            if followsChoice { live[id] = task }
            lock.unlock()
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The machine that raised the request's subject when one did and is still reachable, else the one chosen.
    private func route(_ request: DaemonRequest) -> (MachineTarget, DaemonLink, Bool) {
        lock.lock()
        defer { lock.unlock() }
        if let subject = request.subject, let machine = raised[subject] {
            if machine == .thisMac { return (.thisMac, local, false) }
            if let id = machine.machineId, let server = servers[id] { return (server.target, server.link, false) }
        }
        let link = chosen.machineId.flatMap { servers[$0]?.link } ?? local
        return (chosen, link, true)
    }

    private func ended(_ id: UUID) {
        lock.lock()
        live[id] = nil
        lock.unlock()
    }

    /// Why a request about a workspace call went nowhere, for the diary and anyone reading the refusal.
    static func workspaceOnly(_ subject: String) -> String {
        "\(subject) reached you through your team's workspace, so it is answered there and never through a machine's daemon"
    }

    /// Why a request stayed home, for the diary and anyone reading the refusal.
    static func onlyHere(_ method: String) -> String {
        "\(method) belongs to this Mac's own daemon, so it is not sent to a server"
    }
}
