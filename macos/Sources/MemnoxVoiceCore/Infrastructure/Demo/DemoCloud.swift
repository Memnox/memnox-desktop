import Foundation

/// Memnox Cloud as the demo sees it: nothing goes out, so a press that needs the cloud fails as if offline.
public struct OfflineTransport: HttpTransport {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        throw URLError(.notConnectedToInternet)
    }
}

/// The demo person's sign in, held in memory and never written, so the Account page reads as signed in to Acme.
public final class DemoCredentialStore: PersonCredentialStore, @unchecked Sendable {
    private let credential: WorkspaceCredential

    public init(name: String) {
        // Made up ids and no real token, since nothing is ever sent with them.
        credential = WorkspaceCredential(token: "demo", tokenId: "tok_demo", personId: "psn_demo", name: name, orgId: "org_acme",
                                         workspaces: ["ws_acme"], deviceId: "dev_demo")
    }

    public func load() -> WorkspaceCredential? { credential }
    public func save(_ credential: WorkspaceCredential) throws {}
    public func delete() {}
}
