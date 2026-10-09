import Foundation

/// How signing in to the team ended.
public enum SignInOutcome: Equatable, Sendable {
    case signedIn(WorkspaceCredential)
    /// Why not, in words the person can act on.
    case stopped(String)
}

/// Signs the person in to their Memnox Cloud workspace with a code they approve in the console, then
/// registers this Mac's confirmation key so every yes it gives can be verified. The console decides;
/// this carries the code, keeps the credential and names the key.
public final class WorkspaceSignIn {
    private let inbox: WorkspaceInbox
    private let store: PersonCredentialStore
    private let key: ConfirmKey
    private let now: () -> Date
    private let sleep: (TimeInterval) async throws -> Void

    /// The cloud asks for five seconds; never faster than one, whatever a misconfigured answer says.
    static let shortestInterval: TimeInterval = 1

    public init(inbox: WorkspaceInbox, store: PersonCredentialStore, key: ConfirmKey, now: @escaping () -> Date = Date.init,
                sleep: @escaping (TimeInterval) async throws -> Void = WorkspaceSignIn.taskSleep) {
        self.inbox = inbox
        self.store = store
        self.key = key
        self.now = now
        self.sleep = sleep
    }

    public static func taskSleep(_ seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// The person signed in on this Mac, nil when nobody is.
    public var current: WorkspaceCredential? { store.load() }

    /// Runs the code flow; `shown` hears the code the moment there is one, for the person to approve in the console.
    public func signIn(name: String, shown: @escaping (PersonCode) -> Void) async -> SignInOutcome {
        // A Mac with no key could sign in and then never say yes, which reads as a broken button later.
        guard !key.publicPoint.isEmpty else { return .stopped(WorkspaceLines.noKey) }
        let code: PersonCode
        do {
            code = try await inbox.startSignIn(name: name)
        } catch {
            diary.note("could not start a team sign in: \(error)")
            return .stopped(WorkspaceLines.unreachable)
        }
        shown(code)
        switch await approval(of: code) {
        case .granted(let token): return await finish(token, name: name)
        case .stopped(let why): return .stopped(why)
        }
    }

    /// How the asking ended: the token, or why there is none.
    private enum Approval {
        case granted(PersonToken)
        case stopped(String)
    }

    /// Asks every interval until the console answers or the code runs out.
    private func approval(of code: PersonCode) async -> Approval {
        let interval = max(code.intervalSeconds, Self.shortestInterval)
        while now() < code.expiry {
            do {
                try await sleep(interval)
            } catch {
                return .stopped(WorkspaceLines.cancelled)
            }
            do {
                switch try await inbox.redeem(deviceCode: code.deviceCode) {
                case .pending: continue
                case .granted(let token): return .granted(token)
                case .stopped(let word): return .stopped(WorkspaceLines.refused(word))
                }
            } catch {
                // A dropped request is asked again on the next interval, since the code is still good.
                diary.note("asking about the team sign in failed: \(error)")
            }
        }
        return .stopped(WorkspaceLines.expired)
    }

    /// Finds the workspaces to poll, registers the key and keeps the credential; a credential kept without a device could never say yes.
    private func finish(_ token: PersonToken, name: String) async -> SignInOutcome {
        let workspaces: [String]
        let device: RegisteredDevice
        do {
            let reached = try await inbox.workspaces(token: token.token)
            // Only the organisation that granted the token, since that is the one the person approved this Mac for.
            let inOrg = reached.filter { $0.orgId == nil || $0.orgId == token.orgId }.map(\.id)
            workspaces = inOrg.isEmpty ? reached.map(\.id) : inOrg
            guard !workspaces.isEmpty else { return .stopped(WorkspaceLines.noWorkspace) }
            device = try await inbox.registerDevice(name: name, signingPoint: key.publicPoint, token: token.token)
        } catch {
            diary.note("could not finish the team sign in: \(error)")
            return .stopped(WorkspaceLines.unreachable)
        }
        let credential = WorkspaceCredential(token: token.token, tokenId: token.tokenId, personId: token.personId, name: token.name,
                                             orgId: token.orgId, workspaces: workspaces, deviceId: device.id)
        do {
            try store.save(credential)
        } catch {
            diary.note("could not keep the team credential: \(error)")
            // Removing the device revokes the credential too, so nothing is left signed in that this Mac forgot.
            try? await inbox.removeDevice(device.id, token: token.token)
            return .stopped(WorkspaceLines.notKept)
        }
        diary.note("signed in to the team as \(token.name), \(workspaces.count) workspaces, device \(device.id)")
        return .signedIn(credential)
    }

    /// Removes this Mac from the workspace, which revokes its credential, then forgets the credential here
    /// whatever the cloud said, since a Mac signed out locally must never keep answering.
    public func signOut() async {
        guard let credential = store.load() else { return }
        do {
            try await inbox.removeDevice(credential.deviceId, token: credential.token)
        } catch {
            diary.note("removing this Mac from the team did not go through: \(error)")
        }
        store.delete()
        diary.note("signed out of the team")
    }
}
