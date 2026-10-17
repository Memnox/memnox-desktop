import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Signing in to the team: a code the person approves in the console, asked about every interval,
/// then this Mac's key registered so every yes it gives can be verified.
final class WorkspaceSignInTests: XCTestCase {
    var cloud: ScriptedTransport!
    var store: MemoryPersonCredential!
    var key: PersonKey!
    var clock: Date!
    var slept: [TimeInterval] = []
    var signIn: WorkspaceSignIn!

    private let codeJSON = """
    {"deviceCode":"dc_1","userCode":"ABCD-EFGH","intervalSeconds":5,"expiresAt":1791281400000,\
    "verificationUri":"https://console.memnox.com/apps/connect",\
    "verificationUriComplete":"https://console.memnox.com/apps/connect?code=ABCD-EFGH"}
    """
    private let tokenJSON = #"{"token":"mnx_person","tokenId":"tok_1","personId":"usr_ana","name":"Ana","role":"member","orgId":"org_1"}"#

    override func setUp() {
        cloud = ScriptedTransport()
        store = MemoryPersonCredential()
        key = PersonKey()
        // 2026-10-06T10:00:00Z, ten minutes before the code runs out.
        clock = Date(timeIntervalSince1970: 1_791_280_800)
        slept = []
        signIn = makeSignIn(key: key)
    }

    private func makeSignIn(key: ConfirmKey) -> WorkspaceSignIn {
        WorkspaceSignIn(inbox: HttpWorkspaceInbox(transport: cloud), store: store, key: key,
                        now: { [unowned self] in self.clock },
                        sleep: { [unowned self] seconds in
                            self.slept.append(seconds)
                            self.clock = self.clock.addingTimeInterval(seconds)
                        })
    }

    func testTheCodeIsShownThenAskedAboutUntilApprovedThenTheKeyIsRegistered() async throws {
        cloud.answer("POST /v1/person/codes", 201, codeJSON)
        cloud.answer("POST /v1/person/tokens", 400, #"{"error":"authorization_pending"}"#)
        cloud.answer("POST /v1/person/tokens", 200, tokenJSON)
        cloud.answer("GET /v1/me", 200, #"{"name":"Ana","workspaces":[{"id":"ws_1","orgId":"org_1"},{"id":"ws_other","orgId":"org_2"}]}"#)
        cloud.answer("POST /v1/me/devices", 201, #"{"id":"pdv_mac","name":"Ana's Mac","kind":"desktop","wakeable":false}"#)
        var shown: [PersonCode] = []

        let outcome = await signIn.signIn(name: "Ana's Mac") { shown.append($0) }

        XCTAssertEqual(shown.map(\.userCode), ["ABCD-EFGH"])
        XCTAssertEqual(shown.first?.page?.absoluteString, "https://console.memnox.com/apps/connect?code=ABCD-EFGH")
        XCTAssertEqual(cloud.sent("POST /v1/person/codes").first?.body, ["name": "Ana's Mac", "kind": "desktop"])
        XCTAssertNil(cloud.sent("POST /v1/person/codes").first?.authorization)
        XCTAssertEqual(cloud.sent("POST /v1/person/tokens").map(\.body), [["deviceCode": "dc_1"], ["deviceCode": "dc_1"]])
        XCTAssertEqual(slept, [5, 5])
        let credential = WorkspaceCredential(token: "mnx_person", tokenId: "tok_1", personId: "usr_ana", name: "Ana", orgId: "org_1",
                                             workspaces: ["ws_1"], deviceId: "pdv_mac")
        XCTAssertEqual(outcome, .signedIn(credential))
        XCTAssertEqual(store.load(), credential)
        XCTAssertEqual(cloud.sent("GET /v1/me").first?.authorization, "Bearer mnx_person")
    }

    func testTheDeviceIsRegisteredWithTheConfirmKeysPoint() async throws {
        cloud.answer("POST /v1/person/codes", 201, codeJSON)
        cloud.answer("POST /v1/person/tokens", 200, tokenJSON)
        cloud.answer("GET /v1/me", 200, #"{"workspaces":[{"id":"ws_1"}]}"#)
        cloud.answer("POST /v1/me/devices", 201, #"{"id":"pdv_mac"}"#)

        _ = await signIn.signIn(name: "Ana's Mac") { _ in }

        let registered = try XCTUnwrap(cloud.sent("POST /v1/me/devices").first)
        XCTAssertEqual(registered.authorization, "Bearer mnx_person")
        XCTAssertEqual(registered.body["name"], "Ana's Mac")
        XCTAssertEqual(registered.body["kind"], "desktop")
        XCTAssertEqual(registered.body["signingPoint"], key.publicPoint)
        let point = try XCTUnwrap(Data(base64Encoded: registered.body["signingPoint"] ?? ""))
        // Uncompressed X9.63: a 0x04 and both coordinates, 65 bytes.
        XCTAssertEqual(point.count, 65)
        XCTAssertEqual(point.first, 0x04)
        XCTAssertEqual(Set(registered.body.keys), ["name", "kind", "signingPoint"])
    }

    func testARefusalInTheConsoleStopsTheAskingAndKeepsNothing() async {
        cloud.answer("POST /v1/person/codes", 201, codeJSON)
        cloud.answer("POST /v1/person/tokens", 403, #"{"error":"access_denied"}"#)

        let outcome = await signIn.signIn(name: "Mac") { _ in }

        XCTAssertEqual(outcome, .stopped(WorkspaceLines.refused("access_denied")))
        XCTAssertEqual(cloud.sent("POST /v1/person/tokens").count, 1)
        XCTAssertTrue(cloud.sent("POST /v1/me/devices").isEmpty)
        XCTAssertNil(store.load())
    }

    func testACodeThatRunsOutStopsTheAsking() async {
        cloud.answer("POST /v1/person/codes", 201, codeJSON)
        cloud.answer("POST /v1/person/tokens", 400, #"{"error":"authorization_pending"}"#)

        let outcome = await signIn.signIn(name: "Mac") { _ in }

        XCTAssertEqual(outcome, .stopped(WorkspaceLines.expired))
        // Ten minutes at five seconds apart.
        XCTAssertEqual(cloud.sent("POST /v1/person/tokens").count, 120)
        XCTAssertNil(store.load())
    }

    func testADroppedPollIsAskedAgainRatherThanEndingTheSignIn() async {
        cloud.answer("POST /v1/person/codes", 201, codeJSON)
        cloud.answer("POST /v1/person/tokens", 502, #"{"message":"bad gateway"}"#)
        cloud.answer("POST /v1/person/tokens", 200, tokenJSON)
        cloud.answer("GET /v1/me", 200, #"{"workspaces":[{"id":"ws_1","orgId":"org_1"}]}"#)
        cloud.answer("POST /v1/me/devices", 201, #"{"id":"pdv_mac"}"#)

        guard case .signedIn = await signIn.signIn(name: "Mac", shown: { _ in }) else { return XCTFail("not signed in") }
        XCTAssertEqual(cloud.sent("POST /v1/person/tokens").count, 2)
    }

    func testAMacWithNoKeyNeverStarts() async {
        signIn = makeSignIn(key: NoKey())

        let outcome = await signIn.signIn(name: "Mac") { _ in }

        XCTAssertEqual(outcome, .stopped(WorkspaceLines.noKey))
        XCTAssertTrue(cloud.sent.isEmpty)
    }

    func testSigningOutRemovesTheDeviceAndForgetsTheCredential() async throws {
        try store.save(signedInCredential())
        cloud.answer("DELETE /v1/me/devices/pdv_mac", 204, "")

        await signIn.signOut()

        XCTAssertEqual(cloud.sent("DELETE /v1/me/devices/pdv_mac").first?.authorization, "Bearer mnx_person")
        XCTAssertNil(store.load())
    }

    func testSigningOutOfflineStillForgetsTheCredentialHere() async throws {
        try store.save(signedInCredential())
        cloud.offline = true

        await signIn.signOut()

        XCTAssertNil(store.load())
    }
}

/// A Mac that could not make a confirmation key.
private final class NoKey: ConfirmKey {
    var publicPoint: String { "" }
    func sign(_ message: String, reason: String) async throws -> String? { nil }
}
