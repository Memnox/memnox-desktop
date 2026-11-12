import XCTest
@testable import MemnoxVoiceCore

/// The agents Memnox Cloud reaches, read only while somebody is signed in, and a handoff answered unsigned through it.
final class WorkspaceAgentsTests: XCTestCase {
    private static let profiles = #"{"profiles":[{"profile":{"id":"agp_1","name":"Support triage","purpose":"Sorts tickets","responsiblePersonId":"usr_ana","projects":[]},"needsResponsiblePerson":false,"connected":true,"agents":[],"connections":[{"machineId":"mch_1","connection":"gateway","label":"Zendesk bot","live":true,"levels":{"context":"mediated","instructions":"mediated","tools":"mediated","activity":"mediated","coordination":"advisory","approval":"mediated","enforcement":"mediated"}}],"levels":{"context":"mediated","instructions":"mediated","tools":"mediated","activity":"mediated","coordination":"advisory","approval":"mediated","enforcement":"mediated"}}]}"#
    private static let mine = #"{"work":[{"id":"wrk_1","workspaceId":"ws_1","agentProfileId":"agp_1","responsiblePersonId":"usr_ana","assignedByPersonId":"usr_ana","target":{"source":"jira","externalId":"PAY-42","url":"https://acme.atlassian.net/browse/PAY-42"},"sessions":[],"attempts":1,"status":"handoff_requested","createdAt":"2026-11-07T09:00:00Z","updatedAt":"2026-11-07T10:00:00Z"}],"handoffs":[{"id":"hnd_9","workspaceId":"ws_1","workId":"wrk_1","fromProfileId":"agp_1","toPersonId":"usr_bo","reason":"Needs a refund approver","refs":[],"state":"requested","requestedBy":"agp_1","requestedAt":"2026-11-07T10:00:00Z"}]}"#

    func testHoldsNothingWithNoAccountSoTheLocalListIsWhole() async {
        let cloud = ScriptedTransport()
        let agents = WorkspaceAgents(reader: HttpWorkspaceInbox(transport: cloud), store: MemoryPersonCredential())
        await agents.refresh()
        XCTAssertFalse(agents.signedIn)
        XCTAssertEqual(agents.remote, [])
        XCTAssertTrue(cloud.sent.isEmpty)
    }

    func testReadsTheWorkspacesJobsAndTheHandoffsWaitingOnThePerson() async throws {
        let cloud = ScriptedTransport()
        cloud.answer("GET /v1/workspaces/ws_1/agent-profiles", 200, Self.profiles)
        cloud.answer("GET /v1/workspaces/ws_1/me/agent-work", 200, Self.mine)
        cloud.answer("POST /v1/workspaces/ws_1/me/handoffs/hnd_9/answer", 201, #"{"id":"wrk_1"}"#)
        let agents = WorkspaceAgents(reader: HttpWorkspaceInbox(transport: cloud), store: MemoryPersonCredential(signedInCredential()))
        await agents.refresh()
        let profile = try XCTUnwrap(agents.remote.first?.profiles.first)
        XCTAssertEqual(profile.responsiblePerson, "you")
        XCTAssertEqual(profile.connections.first?.agentKind, "Zendesk bot")
        XCTAssertEqual(CapabilityLevelLines.headline(profile.levels), .advisory)
        XCTAssertEqual(CapabilityLevelLines.seamRows(profile.levels).map(\.title), ["Everything it runs"])
        let work = try XCTUnwrap(agents.remote.first?.work.first)
        // A person id never reaches the screen: the handoff names a teammate, and the work names the person signed in.
        XCTAssertEqual(work.waitingHandoff?.to.person, "a teammate")
        XCTAssertEqual(work.responsiblePerson, "you")
        XCTAssertEqual(AgentWorkLines.issue(work), "PAY-42")
        let answered = await agents.answer("hnd_9", in: "ws_1", .decline)
        XCTAssertEqual(answered, .done("Declined. The work stays with the agent that has it."))
        let sent = try XCTUnwrap(cloud.sent("POST /v1/workspaces/ws_1/me/handoffs/hnd_9/answer").first)
        XCTAssertEqual(sent.raw, #"{"accept":false}"#)
        XCTAssertEqual(sent.authorization, "Bearer mnx_person")
    }

    func testAsksWhichIssueEachSessionIsOnOnlyWhileSignedIn() async throws {
        let cloud = ScriptedTransport()
        cloud.answer("GET /v1/workspaces/ws_1/work-correlations", 200,
                     #"{"correlations":[{"id":"wcr_1","sessionId":"ses_b","source":"branch","state":"linked","lateMatch":false,"claim":"PAY-42","visible":true,"item":{"provider":"jira","label":"PAY-42","url":"https://acme.atlassian.net/browse/PAY-42"}}]}"#)
        let nobody = WorkspaceAgents(reader: HttpWorkspaceInbox(transport: cloud), store: MemoryPersonCredential())
        let none = await nobody.work(of: ["ses_b"])
        XCTAssertEqual(none, [])
        XCTAssertTrue(cloud.sent.isEmpty)
        let agents = WorkspaceAgents(reader: HttpWorkspaceInbox(transport: cloud), store: MemoryPersonCredential(signedInCredential()))
        let empty = await agents.work(of: [])
        XCTAssertEqual(empty, [])
        XCTAssertTrue(cloud.sent.isEmpty)
        let found = await agents.work(of: ["ses_b", "ses_a"])
        XCTAssertEqual(found.map(WorkCorrelationLines.label), ["PAY-42"])
        let sent = try XCTUnwrap(cloud.sent("GET /v1/workspaces/ws_1/work-correlations").first)
        XCTAssertEqual(sent.query, "session=ses_a%2Cses_b")
        XCTAssertEqual(sent.authorization, "Bearer mnx_person")
    }

    func testLeavesOutAWorkspaceThatCannotSayWhichIssues() async {
        let cloud = ScriptedTransport()
        cloud.answer("GET /v1/workspaces/ws_1/work-correlations", 404, #"{"message":"no route"}"#)
        let agents = WorkspaceAgents(reader: HttpWorkspaceInbox(transport: cloud), store: MemoryPersonCredential(signedInCredential()))
        let found = await agents.work(of: ["ses_a"])
        XCTAssertEqual(found, [])
    }

    func testNamesTheResponsiblePersonWhenTheCloudSendsTheName() throws {
        let named = #"{"profile":{"id":"agp_2","name":"Refunds","responsiblePersonId":"usr_bo"},"needsResponsiblePerson":false,"responsiblePersonName":"Bo Ito"}"#
        let unnamed = #"{"profile":{"id":"agp_3","name":"Billing","responsiblePersonId":"usr_bo"},"needsResponsiblePerson":false}"#
        let orphaned = #"{"profile":{"id":"agp_4","name":"Ops","responsiblePersonId":"usr_gone"},"needsResponsiblePerson":true,"responsiblePersonName":"Cy"}"#
        func view(_ json: String) throws -> ProfileView {
            WorkspaceAgentsLines.profileView(try JSONDecoder().decode(CloudProfileView.self, from: Data(json.utf8)), you: "usr_ana")
        }
        XCTAssertEqual(try view(named).responsiblePerson, "Bo Ito")
        XCTAssertEqual(try view(unnamed).responsiblePerson, "a teammate")
        XCTAssertNil(try view(orphaned).responsiblePerson)
        XCTAssertEqual(WorkspaceAgentsLines.responsibleName(id: "usr_ana", name: "Ana", you: "usr_ana"), "you")
        XCTAssertNil(WorkspaceAgentsLines.responsibleName(id: "", name: "Ana", you: nil))
    }
}
