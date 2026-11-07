import XCTest

@testable import MemnoxVoiceCore

/// The Layers model: it reads the layers and the cold cache count, previews a plan, and confirms the very plan shown by
/// sending the same project, agent and keep list with its digest. Skill care notes, calibrates and accepts through put.
final class MemoryLayersTests: XCTestCase {
    static let layers = #"{"projects":[{"name":"acme","path":"/r/acme","agents":["claude-code"],"index":{"path":"MEMORY.md","present":false,"lines":0,"unlinked":0},"routers":[{"agent":"claude-code","path":"CLAUDE.md","present":true,"lines":3,"chars":40,"departments":["macos"],"routed":0}],"skills":[],"keep":[]}],"value":{"searchMedianMs":9,"searches":3}}"#
    static let plan = #"{"project":"/r/acme","digest":"abc","files":[{"path":"MEMORY.md","layer":"index","whole":false,"before":[],"after":["- [A](memory/a.md) one"],"changed":true}]}"#
    static let cost = #"{"days":30,"sessions":1,"turns":4,"coldReloads":1,"reloadedTokens":1000,"reloadCostUsd":0.01,"warmSavingUsd":0.01,"warmHours":4,"unpricedModels":[],"prices":[{"model":"claude-opus-5-5","input":4,"cacheWrite":5,"cacheRead":0.2}]}"#

    func testReadsTheLayersAndTheColdCacheCount() async throws {
        let link = ScriptedLink()
        link.answers["memory-layers"] = [try line(#"{"id":1,"ok":true,"memoryLayers":"# + Self.layers + "}")]
        link.answers["session-cost"] = [try line(#"{"id":2,"ok":true,"sessionCost":"# + Self.cost + "}")]
        let model = MemoryLayers(link: link)
        await model.refresh()
        XCTAssertEqual(model.layers?.projects.first?.routers.first?.departments, ["macos"])
        XCTAssertEqual(model.layers?.value.searches, 3)
        XCTAssertEqual(model.sessionCost?.coldReloads, 1)
        XCTAssertFalse(model.unreadable)
    }

    func testSaysAnOlderRuntimeCannotReadTheLayers() async {
        let link = ScriptedLink()
        let model = MemoryLayers(link: link)
        await model.refresh()
        XCTAssertTrue(model.unreadable)
        XCTAssertNil(model.sessionCost)
    }

    func testConfirmsTheVeryPlanShownWithItsDigest() async throws {
        let link = ScriptedLink()
        link.answers["memory-layers-plan"] = [try line(#"{"id":1,"ok":true,"memoryLayersPlan":"# + Self.plan + "}")]
        link.answers["memory-layers-apply"] = [try line(#"{"id":2,"ok":true,"memoryLayersApplied":{"written":["MEMORY.md"],"unchanged":[]}}"#)]
        let model = MemoryLayers(link: link)
        let previewed = await model.preview(project: "/r/acme", keep: ["release from main"])
        XCTAssertNil(previewed)
        XCTAssertEqual(model.plan?.files.first?.layerKind, .index)
        let written = await model.confirm()
        XCTAssertEqual(written, .written(["MEMORY.md"]))
        let apply = try XCTUnwrap(link.sent.last)
        XCTAssertEqual(apply.method, "memory-layers-apply")
        XCTAssertEqual(apply.memoryLayersDigest, "abc")
        XCTAssertEqual(apply.memoryKeep, ["release from main"])
        XCTAssertEqual(apply.memoryLayersProject, "/r/acme")
        XCTAssertNil(model.plan)
    }

    func testSaysTheRuntimesRefusalOfAStalePlan() async throws {
        let link = ScriptedLink()
        link.answers["memory-layers-plan"] = [try line(#"{"id":1,"ok":true,"memoryLayersPlan":"# + Self.plan + "}")]
        link.answers["memory-layers-apply"] = [try line(#"{"id":2,"ok":false,"error":"These files changed since the plan was shown, so preview it again."}"#)]
        let model = MemoryLayers(link: link)
        _ = await model.preview(project: "/r/acme", keep: [])
        let outcome = await model.confirm()
        XCTAssertEqual(outcome, .failed("These files changed since the plan was shown, so preview it again."))
        XCTAssertNotNil(model.plan)
        let none = await MemoryLayers(link: link).confirm()
        XCTAssertEqual(none, .failed("There is no plan to confirm."))
    }

    func testNotesCalibratesAndAcceptsThroughPutAsTheSkillsOwnProject() async throws {
        let link = ScriptedLink()
        let stats = #"[{"name":"review","uses":2,"failures":1,"refusals":0,"notes":["use the staged diff"],"recentFailures":["exit 1"]}]"#
        let draft = #"{"name":"review","version":"1.0.1","description":"d","instructions":"x","files":[{"path":"a.sh","text":"git diff"}],"tools":["Read"],"mcpServers":[],"dependencies":[],"agents":["claude-code"],"permissions":{"filesystem":[],"network":[],"commands":[]}}"#
        link.answers["skill-stats"] = [try line(#"{"id":1,"ok":true,"skillStats":"# + stats + "}")]
        link.answers["skill-note"] = [try line(#"{"id":2,"ok":true,"skillStats":"# + stats + "}")]
        link.answers["skill-calibrate"] = [try line(#"{"id":3,"ok":true,"skillCalibration":{"name":"review","section":"Known issues / fixes","before":["x"],"after":["x","y"],"draft":"# + draft + #","notes":1,"failures":1}}"#)]
        link.answers["skill-put"] = [try line(#"{"id":4,"ok":true,"proposed":"prp_1"}"#)]
        let care = SkillCare(link: link)
        await care.refresh()
        XCTAssertEqual(care.stats("review")?.failures, 1)
        let noted = await care.note("review", "use the staged diff")
        XCTAssertEqual(noted, .done("Noted for review."))
        XCTAssertEqual(link.sent.last?.skillNote, "use the staged diff")
        _ = await care.calibrate("review")
        let calibration = try XCTUnwrap(care.calibration)
        XCTAssertEqual(SkillCareLines.diff(calibration).map(\.mark), [.same, .added])
        let accepted = await care.accept(calibration, scope: .project, project: "/r/acme")
        XCTAssertEqual(accepted, .proposed("prp_1"))
        let put = try XCTUnwrap(link.sent.last)
        XCTAssertEqual(put.skillDraft?.files, [SkillDraftFile(path: "a.sh", text: "git diff")])
        XCTAssertEqual(put.skillScope, "project")
        XCTAssertEqual(put.skillProject, "/r/acme")
        XCTAssertNil(care.calibration)
    }
}
