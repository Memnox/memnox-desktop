import Foundation

/// How connecting to a server went.
public enum ServerConnection: Equatable, Sendable {
    case connected(PairedMachine)
    /// Why not, in words the person can act on.
    case refused(String)
}

/// Pairs this Mac with a server over the relay, from the memnox://pair link `memnox pair` printed there,
/// and keeps the servers paired. The server decides; this only carries the handshake and keeps the result.
public final class ServerPairing {
    private let pairer: Pairer
    private let store: PairedStore
    private let now: () -> Date

    public init(pairer: Pairer, store: PairedStore, now: @escaping () -> Date = Date.init) {
        self.pairer = pairer
        self.store = store
        self.now = now
    }

    /// Every server this Mac is paired with, oldest pairing first.
    public func servers() -> [PairedMachine] {
        store.all()
    }

    /// Runs the pairing; `code` hears the six digits the moment both ends have them, for the person to type on the server.
    public func connect(link: String, name: String, code: @escaping @Sendable (String) -> Void) async -> ServerConnection {
        let invitation: PairingInvitation
        do {
            invitation = try PairingInvitation(link: link, now: now())
        } catch let why as InvitationError {
            return .refused(ServerPairingLines.refused(why))
        } catch {
            return .refused(ServerPairingLines.refused(.unreadable))
        }
        diary.note("pairing with the server \(invitation.machine)")
        let server: PairedMachine
        do {
            server = try await pairer.pair(invitation, name: name, code: code)
        } catch let why as PairingFailure {
            diary.note("pairing with \(invitation.machine) stopped: \(why)")
            return .refused(ServerPairingLines.failed(why))
        } catch {
            diary.note("pairing with \(invitation.machine) failed: \(error)")
            return .refused(ServerPairingLines.unreachable)
        }
        do {
            try store.save(server)
        } catch {
            diary.note("could not keep \(server.machine) in the keychain: \(error)")
            return .refused(ServerPairingLines.notKept)
        }
        return .connected(server)
    }

    /// Forgets a server here; the server keeps its device record until somebody revokes it there.
    public func forget(_ machineId: String) {
        store.forget(machineId: machineId)
        diary.note("forgot the server \(machineId)")
    }
}

/// The confirmation key with this Mac's own words on the sheet, since the relay pairer was written for a phone.
public final class ReasonedKey: ConfirmKey {
    private let key: ConfirmKey
    private let reason: String

    public init(_ key: ConfirmKey, reason: String) {
        self.key = key
        self.reason = reason
    }

    public var publicPoint: String { key.publicPoint }

    public func sign(_ message: String, reason _: String) async throws -> String? {
        try await key.sign(message, reason: reason)
    }
}
