import Foundation
import XCTest

@testable import MemnoxVoiceCore

/// Profiles with jobs and connections, templates and agent work as the runtime's daemon/profiles.ts and daemon/work.ts
/// write them, so a field renamed on one side fails here rather than as an empty page.
final class AgentWorkProtocolTests: XCTestCase {
    private static let levels = #"{"context":"mediated","instructions":"mediated","tools":"enforced","activity":"mediated","coordination":"mediated","approval":"enforced","enforcement":{"shell":"observed","filesystem":"enforced","git":"none","network":"none","browser":"none","mcp":"enforced"}}"#

    func testReadsAProfileWithItsJobConnectionsAndLevels() throws {
        let connection = #"{"id":"con_claude-code","profileId":"backend","kind":"runtime_hook","agentKind":"claude-code","agentId":"agt_claude-code","mediation":"interposed","firstSeen":"2026-11-01T10:00:00Z","lastSeen":"2026-11-07T10:00:00Z","status":"live","levels":"# + Self.levels + "}"
        let profile = #"{"id":"backend","name":"Backend","skills":[],"mcpServers":[],"updatedAt":"2026-11-07T10:00:00Z","missing":[],"purpose":"Builds the API","role":"developer","responsibilities":["run the tests"],"responsiblePerson":"Bo","projects":["/code/api"],"connections":["# + connection + #"],"levels":"# + Self.levels + "}"
        let response = try decode(#"{"id":1,"ok":true,"profiles":["# + profile + "]}")
        let read = try XCTUnwrap(response.profiles?.first)
        XCTAssertEqual(read.purpose, "Builds the API")
        XCTAssertEqual(read.responsibilities, ["run the tests"])
        XCTAssertEqual(read.responsiblePerson, "Bo")
        XCTAssertFalse(read.isDefault)
        XCTAssertTrue(read.hasAgent)
        XCTAssertEqual(read.connections.first?.connectionKind, .runtimeHook)
        XCTAssertEqual(read.connections.first?.mediationKind, .interposed)
        XCTAssertEqual(read.connections.first?.connectionStatus, .live)
        XCTAssertEqual(read.levels.tools, .enforced)
        XCTAssertEqual(read.levels.enforcement["git"], .noEvidence)
    }

    func testReadsAProfileFromARuntimeBeforeJobsAsOneWithNoAgentBehindIt() throws {
        let response = try decode(#"{"id":1,"ok":true,"profiles":[{"id":"b","name":"B","skills":[],"mcpServers":[],"updatedAt":"2026-11-07T10:00:00Z","missing":[]}]}"#)
        let read = try XCTUnwrap(response.profiles?.first)
        XCTAssertFalse(read.hasAgent)
        XCTAssertEqual(read.levels, .outside)
        XCTAssertEqual(read.projects, [])
    }

    func testReadsALevelThisAppDoesNotKnowAsTheWeakest() throws {
        let odd = #"{"context":"certain","instructions":"mediated","tools":"none","activity":"none","coordination":"none","approval":"none","enforcement":{}}"#
        let levels = try JSONDecoder().decode(CapabilityLevels.self, from: Data(odd.utf8))
        XCTAssertEqual(levels.context, .noEvidence)
        XCTAssertEqual(levels.instructions, .mediated)
    }

    func testReadsTemplates() throws {
        let response = try decode(#"{"id":1,"ok":true,"templates":[{"id":"code-review","name":"Code Review","purpose":"Reads a change","role":"reviewer","responsibilities":["read the diff"],"suggestedSkills":["review"],"suggestedRules":["Never push."],"suggestedConnections":["claude-code"]}]}"#)
        XCTAssertEqual(response.templates?.first?.suggestedRules, ["Never push."])
    }

    func testReadsAgentWorkWithAWaitingHandoff() throws {
        let work = #"{"id":"agw_1","profileId":"backend","responsiblePerson":"Bo","target":{"source":"linear","externalId":"LIN-123","url":"https://linear.app/acme/issue/LIN-123","title":"Fix login"},"sessions":["s1"],"attempts":1,"status":"handoff_requested","progress":[{"at":"2026-11-07T10:00:00Z","by":"s1","note":"Tests pass","refs":[{"kind":"commit","id":"abc"}]}],"handoffs":[{"id":"hnd_1","from":{"profileId":"backend"},"to":{"profileId":"review"},"reason":"Needs review","refs":[],"state":"requested","requestedAt":"2026-11-07T10:01:00Z"}],"createdAt":"2026-11-07T09:00:00Z","updatedAt":"2026-11-07T10:01:00Z"}"#
        let response = try decode(#"{"id":1,"ok":true,"agentWork":["# + work + "]}")
        let read = try XCTUnwrap(response.agentWork?.first)
        XCTAssertEqual(read.workStatus, .handoffRequested)
        XCTAssertEqual(read.target.tracker, .linear)
        XCTAssertEqual(read.latestProgress?.note, "Tests pass")
        XCTAssertEqual(read.waitingHandoff?.id, "hnd_1")
        let event = try decode(#"{"id":0,"ok":true,"event":{"kind":"work","subject":"agw_1","agent":"backend","summary":"LIN-123: Tests pass","at":"2026-11-07T10:01:00Z","workChanged":"# + work + "}}")
        XCTAssertEqual(event.event?.eventKind, .work)
        XCTAssertEqual(event.event?.workChanged?.id, "agw_1")
    }

    func testWritesTheWorkAndBindFieldsOnlyWhenSet() throws {
        var start = DaemonRequest(id: 1, method: .workStart)
        start.workProfile = "backend"
        start.workTarget = "LIN-123"
        let started = try written(start)
        XCTAssertTrue(started.contains(#""method":"work-start""#))
        XCTAssertTrue(started.contains(#""workTarget":"LIN-123""#))
        XCTAssertFalse(started.contains("workTracker"))
        var answer = DaemonRequest(id: 2, method: .handoffAnswer)
        answer.handoffId = "hnd_1"
        answer.handoffAnswer = HandoffAnswerWord.accept.rawValue
        XCTAssertTrue(try written(answer).contains(#""handoffAnswer":"accept""#))
        var bind = DaemonRequest(id: 3, method: .profileBind)
        bind.profileName = "backend"
        bind.agentId = "agt_claude-code"
        XCTAssertTrue(try written(bind).contains(#""agentId":"agt_claude-code""#))
        var copy = DaemonRequest(id: 4, method: .profileFromTemplate)
        copy.templateId = "code-review"
        copy.templateSkills = ["review"]
        XCTAssertTrue(try written(copy).contains(#""templateSkills":["review"]"#))
    }

    private func decode(_ text: String) throws -> DaemonResponse {
        try JSONDecoder().decode(DaemonResponse.self, from: Data(text.utf8))
    }

    private func written(_ request: DaemonRequest) throws -> String {
        try XCTUnwrap(String(data: JSONEncoder().encode(request), encoding: .utf8))
    }
}
