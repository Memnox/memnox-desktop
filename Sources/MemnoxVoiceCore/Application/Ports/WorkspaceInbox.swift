import Foundation

/// Where asking whether the person approved the code stands.
public enum CodeRedemption: Equatable, Sendable {
    /// Nobody has answered in the console yet, so the asking goes on.
    case pending
    case granted(PersonToken)
    /// Refused, expired or spent: the cloud's word for it, and the asking stops.
    case stopped(String)
}

/// Why the workspace would not do what was asked, in the statuses the inbox contract names.
public enum WorkspaceInboxError: Error, Equatable, Sendable {
    /// 401: the credential was revoked or the member suspended, so the person signs in again.
    case signedOut
    /// 403: the call has not reached this person, or a yes whose signature did not verify.
    case notReached(String)
    /// 404: no machine holds that call, or the device is not this person's.
    case notFound(String)
    /// 409: answered already, or the machine stopped waiting.
    case settled(String)
    /// Any other status, with the cloud's words.
    case refused(Int, String)
    /// Nothing came back at all.
    case unreachable(String)
}

/// The person's side of Memnox Cloud: signing in with a code, registering this Mac's key, and the held calls
/// routed to them. The workspace decides who a call reaches; this only carries what it says.
public protocol WorkspaceInbox: AnyObject, Sendable {
    /// Opens a sign in for this Mac, named as the person will see it in the console.
    func startSignIn(name: String) async throws -> PersonCode
    /// Asks once whether the person approved the code.
    func redeem(deviceCode: String) async throws -> CodeRedemption
    /// The workspaces the credential reaches.
    func workspaces(token: String) async throws -> [WorkspaceRef]
    /// Registers this Mac with the public half of its confirmation key, which every yes is verified against.
    func registerDevice(name: String, signingPoint: String, token: String) async throws -> RegisteredDevice
    /// Removes this Mac, which also revokes the credential that registered it.
    func removeDevice(_ id: String, token: String) async throws
    /// The open calls routed to the person in one workspace, oldest first, and those settled a moment ago with who answered.
    func held(in workspace: String, token: String) async throws -> [WorkspaceHeldCall]
    /// One answer; a yes carries the signature, a deny goes without one.
    func answer(_ call: String, in workspace: String, answer: HoldAnswer, deviceId: String, signature: String?,
                token: String) async throws -> InboxAnswerReply
}

/// Where the signed in person's credential is kept between launches. It is a bearer token, so the real one is the Keychain.
public protocol PersonCredentialStore: AnyObject, Sendable {
    func load() -> WorkspaceCredential?
    func save(_ credential: WorkspaceCredential) throws
    func delete()
}
