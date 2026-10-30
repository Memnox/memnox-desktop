import XCTest

@testable import MemnoxVoiceCore

/// Mirrors the use case half of shared/tauri-core/test/profiles.test.ts.
final class ProfilesTests: XCTestCase {
    private static let backend = #"[{"id":"backend-engineering","name":"Backend Engineering","skills":["release-notes"],"mcpServers":["postgres"],"updatedAt":"2026-10-30T10:00:00Z","missing":[]}]"#

    func testReadsKeepsAppliesAndForgetsRedrawingFromEveryAnswer() async throws {
        let link = ScriptedLink()
        link.answers["profiles"] = [try line(#"{"id":1,"ok":true,"profiles":"# + Self.backend + "}")]
        link.answers["profile-put"] = [try line(#"{"id":2,"ok":true,"profiles":"# + Self.backend + "}")]
        link.answers["profile-apply"] = [try line(#"{"id":3,"ok":true,"profiles":"# + Self.backend + #","profileApplied":{"profile":"Backend Engineering","agent":"claude-code","proposed":["p1"],"already":[],"skipped":[]}}"#)]
        link.answers["profile-remove"] = [try line(#"{"id":4,"ok":true,"profiles":[]}"#)]
        let profiles = Profiles(link: link)
        await profiles.refresh()
        XCTAssertEqual(profiles.profiles?.first?.name, "Backend Engineering")
        let kept = await profiles.put(ProfileDraft(name: "Backend Engineering"))
        XCTAssertEqual(kept, .done("Backend Engineering is kept. It gives nothing until you apply it."))
        let applied = await profiles.apply("backend-engineering", agent: "claude-code", project: " /code/api ")
        XCTAssertEqual(applied, .done("1 proposal waits for your signature with Touch ID on the island."))
        let apply = try XCTUnwrap(link.sent.first { $0.method == "profile-apply" })
        XCTAssertEqual(apply.profileName, "backend-engineering")
        XCTAssertEqual(apply.profileAgent, "claude-code")
        XCTAssertEqual(apply.profileProject, "/code/api")
        let removed = await profiles.remove("backend-engineering")
        XCTAssertEqual(removed, .done("backend-engineering is forgotten. What it already gave stays where it was given."))
        XCTAssertEqual(profiles.profiles, [])
    }

    func testSavesAnEditUnderTheSameNameAndSaysItGrantsNothing() async throws {
        let link = ScriptedLink()
        link.answers["profile-put"] = [try line(#"{"id":1,"ok":true,"profiles":"# + Self.backend + "}")]
        let saved = await Profiles(link: link).put(ProfileDraft(name: "Backend Engineering", skills: ["release-notes"]), editing: true)
        XCTAssertEqual(saved, .done("Backend Engineering is saved. What it already gave stays, and the change gives nothing until you apply it again."))
        XCTAssertEqual(link.sent.first?.profileDraft, ProfileDraft(name: "Backend Engineering", skills: ["release-notes"]))
    }

    func testLeavesTheProjectOutForTheHomeFolderAndSaysARefusal() async throws {
        let link = ScriptedLink()
        link.answers["profile-apply"] = [try line(#"{"id":1,"ok":false,"error":"No profile is called nope."}"#)]
        let refused = await Profiles(link: link).apply("nope", agent: "codex-cli", project: "")
        XCTAssertEqual(refused, .failed("No profile is called nope."))
        XCTAssertNil(link.sent.first?.profileProject)
    }

    func testLaunchesWithAProfileAndSaysBothInOneLine() async throws {
        let link = ScriptedLink()
        link.answers["agent-launch"] = [try line(#"{"id":1,"ok":true,"proposed":"p1","agentLaunched":{"agent":"claude-code","workingDirectory":"/code/api","line":"claude"},"profileApplied":{"profile":"Backend","agent":"claude-code","proposed":["p1","p2"],"already":[],"skipped":[]}}"#)]
        let agents = Agents(link: link)
        let outcome = await agents.launch("claude-code", in: "/code/api", profile: "Backend")
        XCTAssertEqual(link.sent.first?.profileName, "Backend")
        XCTAssertEqual(outcome, .done("Opened claude-code in /code/api, typing claude. 2 proposals wait for your signature with Touch ID on the island."))
    }

    func testRemovesAPersonalSkillFromEveryAgentAtOnce() async throws {
        let link = ScriptedLink()
        link.answers["skill-remove"] = [try line(#"{"id":1,"ok":true,"skillsHub":{"skills":[],"found":[],"agents":[]}}"#)]
        let hub = SkillsHub(link: link)
        let removed = await hub.remove("release-notes")
        XCTAssertEqual(removed, .done("release-notes was taken out of the hub and every agent, its kept versions with it."))
        XCTAssertEqual(link.sent.first?.skillName, "release-notes")
        XCTAssertEqual(hub.hub?.skills, [])
    }
}
