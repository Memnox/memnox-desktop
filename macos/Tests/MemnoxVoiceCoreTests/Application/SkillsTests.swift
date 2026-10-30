import XCTest

@testable import MemnoxVoiceCore

/// A daemon that answers each request from what it carries, so a give and a take can answer differently.
private final class AnsweringLink: DaemonLink {
    var sent: [DaemonRequest] = []
    let answer: (DaemonRequest) throws -> DaemonResponse

    init(_ answer: @escaping (DaemonRequest) throws -> DaemonResponse) {
        self.answer = answer
    }

    func stream(_ request: DaemonRequest) -> AsyncThrowingStream<DaemonResponse, Error> {
        sent.append(request)
        let response = Result { try answer(request) }
        return AsyncThrowingStream { continuation in
            switch response {
            case .success(let line): continuation.yield(line)
            case .failure(let error): continuation.finish(throwing: error)
            }
            continuation.finish()
        }
    }
}

/// Mirrors the Skills Hub half of shared/tauri-core/test/skills.test.ts.
final class SkillsTests: XCTestCase {
    private static let hubLine = #"{"id":1,"ok":true,"skillsHub":"# + SkillsProtocolTests.hub + "}"

    func testReadsTheHubAndRedrawsFromEveryAnswer() async throws {
        let link = ScriptedLink()
        link.answers["skills-hub"] = [try line(Self.hubLine)]
        let hub = SkillsHub(link: link)
        await hub.refresh()
        XCTAssertEqual(hub.hub?.skills.first?.name, "release-notes")
        XCTAssertFalse(hub.unreadable)
    }

    func testGivesWithASignatureAndTakesAwayAtOnceOneRequestEach() async throws {
        let link = AnsweringLink { request in
            if request.method == "skills-hub" { return try line(Self.hubLine) }
            let proposed = request.skillOn == true ? #","proposed":"prp_"# + (request.skillAgent ?? "") + #"""# : ""
            return try line(#"{"id":2,"ok":true"# + proposed + "}")
        }
        let hub = SkillsHub(link: link)
        await hub.refresh()
        let results = await hub.assign("release-notes", to: ["cursor", "codex-cli"])
        XCTAssertEqual(results, AssignResults(proposed: 2, done: 1, failed: []))
        let assigns = link.sent.filter { $0.method == "skill-assign" }
        XCTAssertEqual(assigns.map(\.skillAgent), ["claude-code", "codex-cli", "cursor"])
        XCTAssertEqual(assigns.map(\.skillOn), [false, true, true])
    }

    func testSaysASyncWithWhatItWroteAndARuntimeThatIsGone() async throws {
        let link = ScriptedLink()
        link.answers["skill-sync"] = [try line(#"{"id":1,"ok":true,"skillsSynced":{"written":2,"removed":0,"files":[],"skipped":[]}}"#)]
        let hub = SkillsHub(link: link)
        let synced = await hub.sync()
        XCTAssertEqual(synced, .done("Wrote 2."))
        let accepted = await hub.accept("release-notes")
        XCTAssertEqual(accepted, .failed("The runtime is not answering."))
    }

    func testSendsTheNameTheVersionAndTheFoundSkillEachChangeNeeds() async throws {
        let link = ScriptedLink()
        link.answers["skill-rollback"] = [try line(#"{"id":1,"ok":true,"proposed":"prp_1"}"#)]
        link.answers["skill-import"] = [try line(#"{"id":2,"ok":true}"#)]
        let hub = SkillsHub(link: link)
        let rolled = await hub.rollback("release-notes", to: "1.1.0")
        XCTAssertEqual(rolled, .proposed("prp_1"))
        let imported = await hub.importFound(id: "f1", name: "frontend-design")
        XCTAssertEqual(imported, .done("frontend-design is in the hub now."))
        XCTAssertEqual(link.sent.map(\.skillVersion), ["1.1.0", nil])
        XCTAssertEqual(link.sent.last?.skillFoundId, "f1")
        XCTAssertNil(hub.busy)
    }
}
